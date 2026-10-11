import XCTest
@testable import SSTVCore

final class Robot36DecoderTests: XCTestCase {
    func decode(_ signal: SignalFactory, chunk: Int, manual: Bool = false) throws -> DecoderSnapshot {
        var decoder = try SSTVDecoder(sampleRate: signal.rate, manual: manual)
        for start in stride(from: 0, to: signal.samples.count, by: chunk) {
            try decoder.append(samples: Array(signal.samples[start..<min(start + chunk, signal.samples.count)]))
        }
        try decoder.finish()
        return decoder.snapshot
    }
    func testImageAndStreaming() throws {
        for rate in [44100.0, 48000.0] {
            var signal = SignalFactory(rate: rate)
            signal.vis(); signal.image(); signal.tone(1900, 0.02)
            let result = try decode(signal, chunk: 4096)
            XCTAssertEqual(result.lines, 240)
            XCTAssertEqual(result.pixels.count, 320 * 240 * 3)
            var error = 0.0
            for y in 0..<240 {
                for x in 0..<320 {
                    let expected = SignalFactory.rgb(x: x, y: y)
                    for c in 0..<3 { error += abs(Double(result.pixels[(y * 320 + x) * 3 + c]) - expected[c]) }
                }
            }
            XCTAssertLessThan(error / Double(result.pixels.count), 12)
            let alternate = try decode(signal, chunk: 317)
            XCTAssertEqual(result.pixels, alternate.pixels)
        }
    }
    func testManualClockDrift() throws {
        var signal = SignalFactory(rate: 48000, scale: 1.006)
        signal.tone(1900, 0.05); signal.image(); signal.tone(1900, 0.02)
        let result = try decode(signal, chunk: 1024, manual: true)
        XCTAssertEqual(result.lines, 240)
        for y in [10, 100, 200, 238] {
            let p = (y * 320 + 60) * 3
            XCTAssertGreaterThan(result.pixels[p], result.pixels[p + 2] + 50)
        }
    }
    func testManualAcceptsValidVISAndIgnoresIsolatedPulse() throws {
        var signal = SignalFactory(rate: 48000)
        signal.tone(1900, 0.03); signal.tone(1200, 0.009); signal.tone(1900, 0.2)
        signal.vis(); signal.image(); signal.tone(1900, 0.02)
        XCTAssertEqual(try decode(signal, chunk: 511, manual: true).lines, 240)
    }

    func testExactEndWithoutTrailingTone() throws {
        for rate in [44100.0, 48000.0] {
            var signal = SignalFactory(rate: rate)
            signal.vis(); signal.image()
            XCTAssertEqual(try decode(signal, chunk: 1024).lines, 240)
        }
    }

    func testFinishFailureIsStable() throws {
        var signal = SignalFactory(rate: 48000)
        signal.vis(); signal.image(lines: 4); signal.tone(1900, 0.005)
        var decoder = try SSTVDecoder(sampleRate: 48000)
        try decoder.append(samples: signal.samples)
        var first: DecoderError?
        do { try decoder.finish() } catch { first = error as? DecoderError }
        let count = decoder.lines
        XCTAssertThrowsError(try decoder.finish()) { XCTAssertEqual($0 as? DecoderError, first) }
        XCTAssertEqual(decoder.lines, count)
    }

    func testEmptyEarlyEndAndReset() throws {
        var decoder = try SSTVDecoder(sampleRate: 48000)
        XCTAssertThrowsError(try decoder.finish())
        for _ in 0..<3 {
            try decoder.reset()
            var signal = SignalFactory(rate: 48000)
            signal.vis(); signal.image(lines: 4); signal.tone(1900, 0.005)
            try decoder.append(samples: signal.samples)
            XCTAssertThrowsError(try decoder.finish())
            XCTAssertGreaterThan(decoder.lines, 0)
        }
    }
}

extension Robot36DecoderTests {
    func testOneMissingSyncCanCoastButTwoMustFail() throws {
        for missing in [1, 2] {
            var signal = SignalFactory(rate: 48000)
            signal.vis()
            let imageStart = signal.samples.count
            signal.image(); signal.tone(1900, 0.02)
            for row in 20..<(20 + missing) {
                let start = imageStart + Int(Double(row) * Robot36.line * signal.rate)
                for index in start..<(start + Int(Robot36.sync * signal.rate)) {
                    signal.samples[index] = Float(0.75 * sin(2 * .pi * 1900 * Double(index) / signal.rate))
                }
            }
            if missing == 1 {
                XCTAssertEqual(try decode(signal, chunk: 317).lines, 240)
            } else {
                XCTAssertThrowsError(try decode(signal, chunk: 317)) {
                    XCTAssertEqual($0 as? DecoderError, .signalLost)
                }
            }
        }
    }

    func testPixelNullIsBounded() throws {
        for duration in [0.0002, 0.003] {
            var signal = SignalFactory(rate: 48000)
            signal.image(lines: 4); signal.tone(1900, 0.02)
            var demodulator = try FrequencyDemodulator(sampleRate: signal.rate)
            var robot = Robot36Decoder(start: 0)
            var failure: DecoderError?
            do {
                for pcm in signal.samples {
                    guard let sample = demodulator.append(pcm) else { continue }
                    let dropout = (0.17..<(0.17 + duration)).contains(sample.time)
                    let pixel = FrequencySample(time: sample.time, hertz: sample.hertz, magnitude: dropout ? 0 : sample.magnitude)
                    try robot.append(pixel, control: sample)
                }
            } catch { failure = error as? DecoderError }
            if duration < 0.001 {
                XCTAssertNil(failure)
                XCTAssertGreaterThanOrEqual(robot.lines, 3)
            } else { XCTAssertEqual(failure, .signalLost) }
        }
    }

    func testLowVolumeNoisyImage() throws {
        var signal = SignalFactory(rate: 48000)
        signal.vis(); signal.image(); signal.tone(1900, 0.02)
        var seed: UInt64 = 42
        for i in signal.samples.indices {
            seed = seed &* 6364136223846793005 &+ 1
            let noise = (Float(seed >> 40) / Float(1 << 24) * 2 - 1) * 0.004
            signal.samples[i] = signal.samples[i] * 0.025 + noise
        }
        let result = try decode(signal, chunk: 1024)
        XCTAssertEqual(result.lines, 240)
        var error = 0.0
        for y in 0..<240 {
            for x in 0..<320 {
                let expected = SignalFactory.rgb(x: x, y: y)
                for c in 0..<3 { error += abs(Double(result.pixels[(y * 320 + x) * 3 + c]) - expected[c]) }
            }
        }
        XCTAssertLessThan(error / Double(result.pixels.count), 20)
    }
}

import XCTest
@testable import SSTVCore

final class VISDecoderTests: XCTestCase {
    func decode(code: Int = 8, badParity: Bool = false) throws -> Int? {
        var signal = SignalFactory(rate: 48000)
        signal.vis(code: code, badParity: badParity)
        signal.tone(1500, 0.02)
        var demodulator = try FrequencyDemodulator(sampleRate: 48000)
        var vis = VISDecoder()
        for pcm in signal.samples {
            if let frequency = demodulator.append(pcm), let result = try vis.append(frequency) { return result.code }
        }
        return nil
    }
    func testRobot36VIS() throws { XCTAssertEqual(try decode(), 8) }
    func testParityRejected() { XCTAssertThrowsError(try decode(badParity: true)) { XCTAssertEqual($0 as? DecoderError, .badParity) } }
    func testUnsupportedMode() { XCTAssertThrowsError(try decode(code: 44)) { XCTAssertEqual($0 as? DecoderError, .unsupportedMode(44)) } }
}

extension VISDecoderTests {
    func testShortTransitionGapKeepsHeaderButLongGapDoesNot() throws {
        for gap in [0.008, 0.025] {
            var signal = SignalFactory(rate: 48000)
            signal.vis(); signal.tone(1500, 0.02)
            var demodulator = try FrequencyDemodulator(sampleRate: 48000)
            var vis = VISDecoder()
            var result: Int?
            for pcm in signal.samples {
                guard let f = demodulator.append(pcm) else { continue }
                let transition = f.time >= 0.311 && f.time < 0.311 + gap
                let input = FrequencySample(time: f.time, hertz: transition ? 1600 : f.hertz, magnitude: f.magnitude)
                if let decoded = try vis.append(input) { result = decoded.code }
            }
            XCTAssertEqual(result, gap < 0.010 ? 8 : nil)
        }
    }

    func testVISWithBriefFrequencyOutliers() throws {
        var signal = SignalFactory(rate: 48000)
        signal.vis(); signal.tone(1500, 0.02)
        var demodulator = try FrequencyDemodulator(sampleRate: 48000)
        var vis = VISDecoder()
        var result: Int?
        for pcm in signal.samples {
            guard let f = demodulator.append(pcm) else { continue }
            let glitch = (0.1...0.1005).contains(f.time) || (0.4...0.4005).contains(f.time)
            let input = FrequencySample(time: f.time, hertz: glitch ? 2800 : f.hertz, magnitude: f.magnitude)
            if let decoded = try vis.append(input) { result = decoded.code }
        }
        XCTAssertEqual(result, 8)
    }

    func testLowVolumeVISWithNoise() throws {
        var signal = SignalFactory(rate: 48000)
        signal.vis(); signal.tone(1500, 0.02)
        var demodulator = try FrequencyDemodulator(sampleRate: 48000)
        var vis = VISDecoder()
        var seed: UInt64 = 42
        var result: Int?
        for pcm in signal.samples {
            seed = seed &* 6364136223846793005 &+ 1
            let noise = (Float(seed >> 40) / Float(1 << 24) * 2 - 1) * 0.008
            if let f = demodulator.append(pcm * 0.025 + noise), let decoded = try vis.append(f) { result = decoded.code }
        }
        XCTAssertEqual(result, 8)
    }
}

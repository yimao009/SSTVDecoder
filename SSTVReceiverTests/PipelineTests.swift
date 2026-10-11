import XCTest
import AVFoundation
import ImageIO
@testable import SSTVCore
@testable import SSTVAudio
@testable import SSTVImaging

final class PipelineTests: XCTestCase {
    func testWAVToPNG() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "robot36", withExtension: "wav", subdirectory: "Fixtures"))
        let reader = try AudioFileService(url: url)
        var decoder = try SSTVDecoder(sampleRate: reader.sampleRate)
        while let samples = try reader.read() { try decoder.append(samples: samples) }
        try decoder.finish()
        let data = try ImageExporter.png(pixels: decoder.snapshot.pixels)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 320); XCTAssertEqual(image.height, 240)
        XCTAssertGreaterThan(data.count, 1000)
        var error = 0.0
        for y in 0..<240 {
            for x in 0..<320 {
                for c in 0..<3 {
                    error += abs(Double(decoder.snapshot.pixels[(y * 320 + x) * 3 + c]) - SignalFactory.rgb(x: x, y: y)[c].rounded())
                }
            }
        }
        let mae = error / Double(320 * 240 * 3)
        print("Independent WAV RGB mean absolute error: \(mae)")
        XCTAssertLessThan(mae, 12)
        if let path = ProcessInfo.processInfo.environment["SSTV_TEST_PNG"] {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }

    func testTruncatedWAVRejected() throws {
        let source = try XCTUnwrap(Bundle.module.url(forResource: "robot36", withExtension: "wav", subdirectory: "Fixtures"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(contentsOf: source).prefix(1000).write(to: url)
        XCTAssertThrowsError(try AudioFileService(url: url)) { XCTAssertEqual($0 as? DecoderError, .invalidWAV) }
    }

    func testQueueBoundAndReuse() throws {
        let queue = PCMBufferQueue()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        for pass in 0..<3 {
            for index in 0..<16 {
                for frame in 0..<1024 { buffer.floatChannelData![0][frame] = Float(index + pass) }
                XCTAssertTrue(queue.push(buffer))
            }
            XCTAssertFalse(queue.push(buffer))
            for index in 0..<16 { XCTAssertEqual(queue.pop()?.first, Float(index + pass)) }
            XCTAssertNil(queue.pop())
        }
    }

    func testPNGRejectsWrongBuffer() { XCTAssertThrowsError(try ImageExporter.png(pixels: [])) }

    func testSilenceAndSignalLoss() throws {
        var decoder = try SSTVDecoder(sampleRate: 48000)
        try decoder.append(samples: .init(repeating: 0, count: 48000))
        XCTAssertThrowsError(try decoder.finish()) { XCTAssertEqual($0 as? DecoderError, .weakSignal) }
        try decoder.reset()
        var signal = SignalFactory(rate: 48000)
        signal.vis(); signal.image(lines: 2); signal.tone(1900, 0.3)
        XCTAssertThrowsError(try decoder.append(samples: signal.samples)) { XCTAssertEqual($0 as? DecoderError, .signalLost) }
    }
}

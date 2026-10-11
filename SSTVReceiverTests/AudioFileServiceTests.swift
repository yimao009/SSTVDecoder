import XCTest
import AVFoundation
@testable import SSTVAudio

final class AudioFileServiceTests: XCTestCase {
    func testStereoAndSampleRate() throws {
        for rate in [44100.0, 48000.0] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
            defer { try? FileManager.default.removeItem(at: url) }
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
            do {
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
                pcm.frameLength = 8000
                for i in 0..<8000 { pcm.floatChannelData![0][i] = 0.2; pcm.floatChannelData![1][i] = 0.6 }
                try file.write(from: pcm)
            }
            let reader = try AudioFileService(url: url)
            XCTAssertEqual(reader.sampleRate, rate)
            var total = 0
            while let chunk = try reader.read() {
                total += chunk.count
                XCTAssertEqual(chunk[0], 0.4, accuracy: 0.0001)
            }
            XCTAssertEqual(total, 8000)
            XCTAssertEqual(reader.progress, 1)
        }
    }
    func testCommonPCMEncodings() throws {
        for (bits, floating) in [(8, false), (16, false), (24, false), (32, false), (32, true), (64, true)] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
            defer { try? FileManager.default.removeItem(at: url) }
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: bits,
                AVLinearPCMIsFloatKey: floating, AVLinearPCMIsBigEndianKey: false
            ]
            do {
                let file = try AVAudioFile(forWriting: url, settings: settings)
                let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 100))
                pcm.frameLength = 100
                for i in 0..<100 { pcm.floatChannelData![0][i] = 0.125 }
                try file.write(from: pcm)
            }
            let reader = try AudioFileService(url: url)
            let samples = try XCTUnwrap(reader.read())
            XCTAssertEqual(samples.count, 100)
            XCTAssertEqual(samples[0], 0.125, accuracy: 0.01, "PCM \(bits) float=\(floating)")
        }
    }

    func testInvalidFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try AudioFileService(url: url))
    }
}

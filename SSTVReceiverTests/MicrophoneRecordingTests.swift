import XCTest
@testable import SSTVCore
@testable import SSTVAudio

final class MicrophoneRecordingTests: XCTestCase {
    func testCompleteAcousticRecordingInBothModes() throws {
        guard let url = Bundle.module.url(forResource: "robot36-microphone-complete", withExtension: "wav", subdirectory: "Fixtures") else {
            throw XCTSkip("Optional private microphone fixture is not included in the repository")
        }
        var automatic: [UInt8]?
        for manual in [false, true] {
            let reader = try AudioFileService(url: url)
            var decoder = try SSTVDecoder(sampleRate: reader.sampleRate, manual: manual)
            while let chunk = try reader.read() { try decoder.append(samples: chunk) }
            try decoder.finish()
            XCTAssertEqual(decoder.lines, 240)
            if manual { XCTAssertEqual(decoder.snapshot.pixels, automatic) }
            else { automatic = decoder.snapshot.pixels }
            // Check recognizable bar colors in both halves, not just a line count.
            for y in [30, 90, 150, 210] {
                for (x, channel) in [(60, 0), (100, 1), (140, 2)] {
                    let pixels = decoder.snapshot.pixels
                    let offset = (y * 320 + x) * 3
                    for other in 0..<3 where other != channel {
                        XCTAssertGreaterThan(pixels[offset + channel], pixels[offset + other])
                    }
                }
            }
        }
    }

    func testAcousticPrefixAcquiresVISAndDecodesLines() throws {
        guard let url = Bundle.module.url(forResource: "robot36-microphone-prefix", withExtension: "wav", subdirectory: "Fixtures") else {
            throw XCTSkip("Optional private microphone fixture is not included in the repository")
        }
        for manual in [false, true] {
            let reader = try AudioFileService(url: url)
            var decoder = try SSTVDecoder(sampleRate: reader.sampleRate, manual: manual)
            while let chunk = try reader.read() { try decoder.append(samples: chunk) }
            XCTAssertGreaterThanOrEqual(decoder.lines, 20)
            XCTAssertTrue(decoder.detected)
            XCTAssertFalse(decoder.completed)
            // This is deliberately a four-second excerpt, not a full frame.
            XCTAssertThrowsError(try decoder.finish()) { error in
                guard case .incomplete = error as? DecoderError else {
                    return XCTFail("Expected incomplete recording, got \(error)")
                }
            }
        }
    }
}

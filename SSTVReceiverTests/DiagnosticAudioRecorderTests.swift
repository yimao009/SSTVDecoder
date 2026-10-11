import XCTest
@testable import SSTVAudio
@testable import SSTVCore

final class DiagnosticAudioRecorderTests: XCTestCase {
    func testExactPCMAndSampleRateRoundTrip() throws {
        for rate in [44100.0, 48000.0] {
            let recorder = try DiagnosticAudioRecorder(sampleRate: rate)
            defer { try? FileManager.default.removeItem(at: recorder.url) }
            let samples = (0..<20003).map { Float(sin(Double($0) * 0.19) * 0.3) }
            try recorder.append(Array(samples.prefix(997)))
            try recorder.append(Array(samples.dropFirst(997)))
            let reader = try AudioFileService(url: XCTUnwrap(recorder.finish()))
            XCTAssertEqual(reader.sampleRate, rate)
            var restored: [Float] = []
            while let chunk = try reader.read() { restored += chunk }
            XCTAssertEqual(restored, samples)
        }
    }

    func testDurationLimitAndEmptyCleanup() throws {
        let recorder = try DiagnosticAudioRecorder(sampleRate: 8000)
        defer { try? FileManager.default.removeItem(at: recorder.url) }
        for _ in 0..<46 { try recorder.append([Float](repeating: 0.1, count: 8000)) }
        let reader = try AudioFileService(url: XCTUnwrap(recorder.finish()))
        var frames = 0
        while let chunk = try reader.read() { frames += chunk.count }
        XCTAssertEqual(frames, 45 * 8000)
        var empty: DiagnosticAudioRecorder? = try DiagnosticAudioRecorder(sampleRate: 48000)
        let emptyURL = try XCTUnwrap(empty?.url)
        XCTAssertNil(empty?.finish())
        empty = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyURL.path))
        XCTAssertThrowsError(try DiagnosticAudioRecorder(sampleRate: .nan))
    }

    func testRecordedFixtureStillDecodes240Lines() throws {
        let source = try XCTUnwrap(Bundle.module.url(forResource: "robot36", withExtension: "wav", subdirectory: "Fixtures"))
        let original = try AudioFileService(url: source)
        let recorder = try DiagnosticAudioRecorder(sampleRate: original.sampleRate)
        defer { try? FileManager.default.removeItem(at: recorder.url) }
        while let samples = try original.read() { try recorder.append(samples) }
        let reader = try AudioFileService(url: XCTUnwrap(recorder.finish()))
        var decoder = try SSTVDecoder(sampleRate: reader.sampleRate)
        while let samples = try reader.read() { try decoder.append(samples: samples) }
        try decoder.finish()
        XCTAssertEqual(decoder.lines, 240)
        XCTAssertGreaterThanOrEqual(decoder.snapshot.syncPulses, 239)
        XCTAssertGreaterThan(decoder.snapshot.receivedSeconds, 36)
        try decoder.reset()
        XCTAssertEqual(decoder.snapshot.syncPulses, 0)
        XCTAssertEqual(decoder.snapshot.receivedSeconds, 0)
    }
}

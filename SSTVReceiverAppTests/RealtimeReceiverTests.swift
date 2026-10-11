import XCTest
import AVFoundation
@testable import SSTVDemo

@MainActor
private final class ReplayAudioInput: AudioInputProviding {
    var onEvent: (@MainActor (AudioInputService.Event) -> Void)?
    private let url: URL
    private let silenceAfterSeconds: Double?
    private var producer: Task<Void, Never>?
    private var sink: AsyncThrowingStream<Void, Error>.Continuation?
    private(set) var starts = 0

    init(url: URL, silenceAfterSeconds: Double? = nil) {
        self.url = url
        self.silenceAfterSeconds = silenceAfterSeconds
    }
    func requestPermission() async -> Bool { true }
    func start() async throws -> AudioInputService.Session {
        starts += 1
        let queue = PCMBufferQueue()
        let stream = AsyncThrowingStream<Void, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        sink = stream.continuation
        let tap = AudioInputService.makeTap(queue: queue, sink: stream.continuation)
        let url = url
        let silenceAfterSeconds = silenceAfterSeconds
        producer = Task.detached {
            do {
                let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024))
                let clock = ContinuousClock()
                let began = clock.now
                var frames: Int64 = 0
                while file.framePosition < file.length {
                    try Task.checkCancellation()
                    try file.read(into: buffer, frameCount: 1024)
                    if let silenceAfterSeconds, Double(frames) / file.processingFormat.sampleRate >= silenceAfterSeconds {
                        for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][index] = 0 }
                    }
                    tap(buffer, AVAudioTime(sampleTime: frames, atRate: file.processingFormat.sampleRate))
                    frames += Int64(buffer.frameLength)
                    // Deliver at the recording's actual sample cadence, not file speed.
                    try await clock.sleep(until: began + .seconds(Double(frames) / file.processingFormat.sampleRate))
                }
                stream.continuation.finish()
            } catch is CancellationError {
                stream.continuation.finish()
            } catch { stream.continuation.finish(throwing: error) }
        }
        return .init(sampleRate: 48000, inputName: "Recorded microphone replay", queue: queue, events: stream.stream)
    }
    func pause() { producer?.cancel(); producer = nil; sink?.finish(); sink = nil }
    func stop() { pause() }
}

@MainActor
final class RealtimeReceiverTests: XCTestCase {
    func testStopDuringRecoveryClosesRecordingAndKeepsPreview() async throws {
        guard let url = Bundle(for: Self.self).url(forResource: "robot36-microphone-complete", withExtension: "wav", subdirectory: "Fixtures") else {
            throw XCTSkip("Optional private microphone fixture is not included in the repository")
        }
        let input = ReplayAudioInput(url: url, silenceAfterSeconds: 3)
        let model = ReceiverViewModel(audioInput: input)
        model.recordDiagnostics = true
        defer {
            model.stop()
            if let url = model.diagnosticURL { try? FileManager.default.removeItem(at: url) }
        }
        model.startMicrophone()
        let deadline = ContinuousClock.now + .seconds(8)
        while !model.detail.contains("继续监听") {
            guard model.busy, ContinuousClock.now < deadline else { XCTFail(model.detail); return }
            try await Task.sleep(for: .milliseconds(20))
        }
        let retainedLines = model.lines
        XCTAssertGreaterThan(retainedLines, 0)
        model.stop()
        while model.diagnosticURL == nil {
            guard ContinuousClock.now < deadline else { XCTFail("Recording did not close after stop"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(model.busy)
        XCTAssertFalse(model.usingMicrophone)
        XCTAssertFalse(model.showingError)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.lines, retainedLines)
        XCTAssertNotNil(model.image)
        XCTAssertEqual(input.starts, 1)
    }

    func testLostFrameKeepsListeningAndAcceptsNextTransmission() async throws {
        guard let fixture = Bundle(for: Self.self).url(forResource: "robot36-microphone-complete", withExtension: "wav", subdirectory: "Fixtures") else {
            throw XCTSkip("Optional private microphone fixture is not included in the repository")
        }
        let damaged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: damaged) }
        do {
            let source = try AVAudioFile(forReading: fixture)
            let output = try AVAudioFile(forWriting: damaged, settings: source.processingFormat.settings)
            let prefix = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 144000))
            try source.read(into: prefix, frameCount: 144000)
            try output.write(from: prefix)
            let silence = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 19200))
            silence.frameLength = 19200
            silence.floatChannelData![0].initialize(repeating: 0, count: 19200)
            try output.write(from: silence)
            source.framePosition = 0
            let chunk = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4096))
            while source.framePosition < source.length {
                try source.read(into: chunk)
                try output.write(from: chunk)
            }
        }
        let input = ReplayAudioInput(url: damaged)
        let model = ReceiverViewModel(audioInput: input)
        model.recordDiagnostics = true
        defer {
            model.stop()
            if let url = model.diagnosticURL { try? FileManager.default.removeItem(at: url) }
        }
        model.startMicrophone()
        var recovered = false
        let deadline = ContinuousClock.now + .seconds(48)
        while model.busy || model.diagnosticURL == nil {
            if model.detail.contains("继续监听") {
                recovered = true
                XCTAssertGreaterThan(model.lines, 0)
                XCTAssertNotNil(model.image)
                XCTAssertTrue(model.busy)
                XCTAssertTrue(model.usingMicrophone)
                XCTAssertFalse(model.showingError)
            }
            if model.state == .failed { break }
            guard ContinuousClock.now < deadline else { XCTFail("Recovery timed out: \(model.detail)"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(recovered)
        XCTAssertEqual(input.starts, 1, "Recovery must not restart hardware or recording")
        XCTAssertEqual(model.state, .completed, model.detail)
        XCTAssertEqual(model.lines, 240)
        XCTAssertNotNil(model.pngData)
        if let recording = model.diagnosticURL {
            let file = try AVAudioFile(forReading: recording)
            XCTAssertGreaterThan(Double(file.length) / file.processingFormat.sampleRate, 40)
        } else { XCTFail("Diagnostic recording was lost") }
    }

    func testMicrophonePathPublishesWhileAudioIsStillArriving() async throws {
        guard let url = Bundle(for: Self.self).url(forResource: "robot36-microphone-complete", withExtension: "wav", subdirectory: "Fixtures") else {
            throw XCTSkip("Optional private microphone fixture is not included in the repository")
        }
        let input = ReplayAudioInput(url: url)
        let model = ReceiverViewModel(audioInput: input)
        model.recordDiagnostics = true
        defer {
            model.stop()
            if let url = model.diagnosticURL { try? FileManager.default.removeItem(at: url) }
        }
        model.startMicrophone()
        let deadline = ContinuousClock.now + .seconds(45)
        var sawPartialImage = false
        while model.busy || model.diagnosticURL == nil {
            if model.lines > 0 && model.lines < 240 {
                sawPartialImage = true
                XCTAssertTrue(model.usingMicrophone)
                XCTAssertNotNil(model.image)
            }
            if model.state == .failed { break }
            guard ContinuousClock.now < deadline else { XCTFail("Live receive timed out: \(model.detail)"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(sawPartialImage, "The preview must update before reception ends")
        XCTAssertEqual(input.starts, 1)
        XCTAssertEqual(model.state, .completed, model.detail)
        XCTAssertEqual(model.lines, 240)
        XCTAssertNotNil(model.pngData)
        XCTAssertNotNil(model.diagnosticURL)
    }
}

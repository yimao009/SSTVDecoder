import AVFoundation
import XCTest
@testable import SSTVDemo

@MainActor
final class AudioInputServiceTests: XCTestCase {
    func testAudioCallbackFromBackgroundThread() async throws {
        let queue = PCMBufferQueue()
        let stream = AsyncThrowingStream<Void, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let callback = AudioInputService.makeTap(queue: queue, sink: stream.continuation)
        defer { stream.continuation.finish() }

        try await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
            let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
            pcm.frameLength = 1024
            for i in 0..<1024 { pcm.floatChannelData![0][i] = 0.25 }
            callback(pcm, AVAudioTime(sampleTime: 0, atRate: 48000))
        }.value

        XCTAssertEqual(queue.pop(), [Float](repeating: 0.25, count: 1024))
        var events = stream.stream.makeAsyncIterator()
        let event: Void? = try await events.next()
        XCTAssertNotNil(event)
    }

    func testAudioCallbackReportsOverflowFromBackgroundThread() async throws {
        let queue = PCMBufferQueue()
        let stream = AsyncThrowingStream<Void, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let callback = AudioInputService.makeTap(queue: queue, sink: stream.continuation)
        defer { stream.continuation.finish() }

        try await Task.detached {
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
            let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
            pcm.frameLength = 1024
            for i in 0..<1024 { pcm.floatChannelData![0][i] = 0 }
            for _ in 0..<17 { callback(pcm, AVAudioTime(sampleTime: 0, atRate: 48000)) }
        }.value

        do {
            for try await _ in stream.stream { }
            XCTFail("Overflow must terminate the audio stream with an error")
        } catch {
            XCTAssertEqual(error as? DecoderError, .overloaded)
        }
    }
}

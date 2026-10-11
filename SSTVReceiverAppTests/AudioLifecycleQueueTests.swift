import XCTest
@testable import SSTVDemo

private actor LifecycleProbe {
    private(set) var events = [String]()
    private(set) var usedMainThread = false
    private var continuation: CheckedContinuation<Void, Never>?

    func startAndWait() async {
        record("starting")
        await withCheckedContinuation { continuation = $0 }
        record("started")
    }

    func record(_ event: String) {
        usedMainThread = usedMainThread || Thread.isMainThread
        events.append(event)
    }

    func release() { continuation?.resume(); continuation = nil }
    var waiting: Bool { continuation != nil }
}

@MainActor
final class AudioLifecycleQueueTests: XCTestCase {
    func testStopAndRestartWaitForCancelledPendingActivation() async throws {
        let queue = AudioLifecycleQueue()
        let probe = LifecycleProbe()
        let start = queue.enqueue { await probe.startAndWait() }
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await probe.waiting) {
            guard ContinuousClock.now < deadline else { XCTFail("Activation never began"); return }
            await Task.yield()
        }
        start.cancel()
        let stop = queue.enqueue { await probe.record("stopped") }
        let restart = queue.enqueue { await probe.record("restarted") }
        let pending = await probe.events
        XCTAssertEqual(pending, ["starting"])
        await probe.release()
        try await start.value
        try await stop.value
        try await restart.value
        let events = await probe.events
        let mainThread = await probe.usedMainThread
        XCTAssertEqual(events, ["starting", "started", "stopped", "restarted"])
        XCTAssertFalse(mainThread)
    }

    func testFailedActivationDoesNotSkipCleanup() async throws {
        let queue = AudioLifecycleQueue()
        let probe = LifecycleProbe()
        let start: Task<Void, Error> = queue.enqueue {
            await probe.record("failed")
            throw InputError.unavailable
        }
        let stop = queue.enqueue { await probe.record("stopped") }
        do { try await start.value; XCTFail("Expected activation error") } catch { }
        try await stop.value
        let events = await probe.events
        XCTAssertEqual(events, ["failed", "stopped"])
    }
}

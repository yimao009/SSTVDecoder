import XCTest
@testable import SSTVDemo

@MainActor
final class ReceiverViewModelTests: XCTestCase {
    private func fixture() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "robot36", withExtension: "wav", subdirectory: "Fixtures"))
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !condition() {
            if ContinuousClock.now >= deadline { XCTFail("Timed out waiting for decoding state"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testFileCompletesWithoutMicrophone() async throws {
        let model = ReceiverViewModel()
        model.importFile(try fixture())
        try await waitUntil { !model.busy }
        XCTAssertEqual(model.state, .completed)
        XCTAssertEqual(model.lines, 240)
        XCTAssertNotNil(model.pngData)
        XCTAssertEqual(model.image?.width, 320)
        XCTAssertFalse(model.usingMicrophone)
    }

    func testAcousticRecordingProducesImageInReceiver() async throws {
        guard let url = Bundle(for: Self.self).url(forResource: "robot36-microphone-complete", withExtension: "wav", subdirectory: "Fixtures") else {
            throw XCTSkip("Optional private microphone fixture is not included in the repository")
        }
        let model = ReceiverViewModel()
        model.importFile(url)
        try await waitUntil { !model.busy }
        XCTAssertEqual(model.state, .completed)
        XCTAssertEqual(model.lines, 240)
        XCTAssertNotNil(model.pngData)
        XCTAssertEqual(model.image?.width, 320)
        XCTAssertEqual(model.image?.height, 240)
        XCTAssertFalse(model.showingError)
    }

    func testCancelThenRestartIgnoresStaleResult() async throws {
        let model = ReceiverViewModel()
        let url = try fixture()
        model.importFile(url)
        try await waitUntil { model.lines > 0 || !model.busy }
        model.stop()
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.state, .idle)
        model.importFile(url)
        try await waitUntil { !model.busy }
        XCTAssertEqual(model.state, .completed)
        XCTAssertEqual(model.lines, 240)
    }

    func testImmediateStopAndInvalidFile() async throws {
        let model = ReceiverViewModel()
        model.importFile(try fixture())
        model.stop()
        XCTAssertEqual(model.state, .idle)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        model.importFile(missing)
        try await waitUntil { !model.busy }
        XCTAssertEqual(model.state, .failed)
        XCTAssertTrue(model.showingError)
        XCTAssertNil(model.pngData)
        model.stop()
        XCTAssertEqual(model.state, .idle)
    }
}

import XCTest
@testable import SSTVCore

final class SyncDetectorTests: XCTestCase {
    func testPulseLocationsFromPCM() throws {
        var signal = SignalFactory(rate: 44100)
        signal.tone(1900, 0.05)
        for _ in 0..<4 { signal.tone(1200, 0.009); signal.tone(1900, 0.141) }
        var demodulator = try FrequencyDemodulator(sampleRate: 44100)
        var sync = SyncDetector()
        var starts = [Double]()
        for pcm in signal.samples {
            if let f = demodulator.append(pcm), let start = sync.append(f) { starts.append(start) }
        }
        XCTAssertEqual(starts.count, 4)
        for (i, start) in starts.enumerated() { XCTAssertEqual(start, 0.05 + Double(i) * 0.15, accuracy: 0.0007) }
    }
}

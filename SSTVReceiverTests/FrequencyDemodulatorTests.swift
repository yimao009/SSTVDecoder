import XCTest
@testable import SSTVCore

final class FrequencyDemodulatorTests: XCTestCase {
    func testKnownTones() throws {
        for rate in [44100.0, 48000.0] {
            for tone in [1200.0, 1500.0, 1900.0, 2300.0] {
                var demodulator = try FrequencyDemodulator(sampleRate: rate)
                var frequencies = [Double]()
                for i in 0..<Int(rate * 0.15) {
                    if let result = demodulator.append(Float(0.8 * sin(2 * .pi * tone * Double(i) / rate))), result.time > 0.02 {
                        frequencies.append(result.hertz)
                    }
                }
                XCTAssertFalse(frequencies.isEmpty)
                XCTAssertLessThan(frequencies.map { abs($0 - tone) }.max() ?? .infinity, 6, "\(rate) / \(tone)")
            }
        }
    }
    func testInvalidSampleRate() {
        XCTAssertThrowsError(try FrequencyDemodulator(sampleRate: 0))
        XCTAssertThrowsError(try FrequencyDemodulator(sampleRate: .nan))
    }
}

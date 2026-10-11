import Foundation

struct SyncDetector {
    private var window = [FrequencySample]()
    private var start: Double?
    private var end: Double?
    mutating func append(_ input: FrequencySample) -> Double? {
        // Average several cycles of frequency ripple in an acoustic recording.
        // This path detects sync only; image samples keep their original timing.
        window.append(input)
        while let first = window.first, first.time < input.time - 0.002 { window.removeFirst() }
        let valid = window.filter(\.valid)
        let frequency = valid.reduce(0.0) { $0 + $1.hertz } / Double(max(1, valid.count))
        let time = ((window.first?.time ?? input.time) + input.time) / 2
        let inSync = !valid.isEmpty && Double(valid.count) >= Double(window.count) * 0.8
            && abs(frequency - Robot36.syncFrequency) < 65
        if inSync {
            if start == nil { start = time }
            end = nil
        } else if let start {
            // Bridge sub-millisecond outliers, retaining the first edge time
            // so confirmation latency does not move the scanline clock.
            if end == nil { end = time }
            guard let end, time - end >= 0.001 else { return nil }
            self.start = nil
            self.end = nil
            // Reject VIS start/stop pulses and short noise bursts.
            if (0.0065...0.0115).contains(end - start) {
                // Threshold crossings move inward through the FIR transition. Center the
                // known-width pulse on both edges rather than delaying every line start.
                return (start + end - Robot36.sync) / 2
            }
        }
        return nil
    }
}

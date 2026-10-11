import Foundation

/// A short, bounded window for tone detection only; never smooth image pixel data.
/// Timestamping its center preserves protocol timing despite the detection latency.
struct FrequencyMedianFilter {
    let duration: Double
    private var samples = [FrequencySample]()

    init(duration: Double) { self.duration = duration }

    mutating func append(_ sample: FrequencySample) -> FrequencySample {
        samples.append(sample)
        while let first = samples.first, first.time < sample.time - duration { samples.removeFirst() }
        let valid = samples.filter(\.valid)
        let frequencies = valid.map(\.hertz).sorted()
        let usable = !valid.isEmpty && Double(valid.count) >= Double(samples.count) * 0.8
        return FrequencySample(
            time: ((samples.first?.time ?? sample.time) + sample.time) / 2,
            hertz: frequencies.isEmpty ? 0 : frequencies[frequencies.count / 2],
            magnitude: usable ? valid.reduce(0.0) { $0 + $1.magnitude } / Double(valid.count) : 0
        )
    }
}

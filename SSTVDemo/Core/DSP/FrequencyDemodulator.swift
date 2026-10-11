import Foundation
import Accelerate

struct FrequencyDemodulator {
    let sampleRate: Double
    private let filter: BandpassFilter
    private let stride: Int
    private var ring: [Double]
    private var position = 0
    private var count = 0
    private var previous: (Double, Double)?

    init(sampleRate: Double, controlTones: Bool = false) throws {
        guard sampleRate.isFinite, (8000...192000).contains(sampleRate) else { throw DecoderError.invalidSampleRate }
        self.sampleRate = sampleRate
        filter = BandpassFilter(sampleRate: sampleRate, controlTones: controlTones)
        stride = max(1, Int(sampleRate / 12000))
        ring = .init(repeating: 0, count: filter.count * 2)
    }

    mutating func append(_ value: Float) -> FrequencySample? {
        ring[position] = value.isFinite ? Double(value) : 0
        ring[position + filter.count] = ring[position]
        position = (position + 1) % filter.count
        count += 1
        guard count >= filter.count, count % stride == 0 else { return nil }
        var re = 0.0, im = 0.0
        // Mirrored ring exposes a contiguous window; vDSP keeps FIR work fast in Debug too.
        ring.withUnsafeBufferPointer { history in
            filter.real.withUnsafeBufferPointer { coefficients in
                vDSP_dotprD(history.baseAddress! + position, 1, coefficients.baseAddress!, 1, &re, vDSP_Length(filter.count))
            }
            filter.imaginary.withUnsafeBufferPointer { coefficients in
                vDSP_dotprD(history.baseAddress! + position, 1, coefficients.baseAddress!, 1, &im, vDSP_Length(filter.count))
            }
        }
        defer { previous = (re, im) }
        guard let previous else { return nil }
        let phase = atan2(im * previous.0 - re * previous.1, re * previous.0 + im * previous.1)
        let frequency = phase * sampleRate / (2 * .pi * Double(stride))
        let time = (Double(count - 1) - Double(filter.count - 1) / 2 - Double(stride) / 2) / sampleRate
        return FrequencySample(time: time, hertz: frequency, magnitude: hypot(re, im))
    }
}

import Foundation

struct VISDecoder {
    private var headerFilter = FrequencyMedianFilter(duration: 0.002)
    private var tone = 0
    private var runStart = 0.0
    private var candidateTone = 0
    private var candidateStart = 0.0
    private var bitSum = 0.0
    private var bitValidCount = 0
    private var bitCount = 0
    private var stage = 0
    private var deadline = 0.0
    private var frameStart: Double?
    private var bitIndex = 0
    private var code = 0
    private var ones = 0

    mutating func append(_ sample: FrequencySample) throws -> (code: Int, imageStart: Double)? {
        if let start = frameStart {
            let target = start + (Double(bitIndex) + 1.5) * Robot36.visBit
            // Average the central 10 ms of each 30 ms symbol instead of trusting
            // one instantaneous estimate, which is vulnerable to acoustic noise.
            if sample.time >= target - 0.005 && sample.time < target + 0.005 {
                bitCount += 1
                if sample.valid { bitSum += sample.hertz; bitValidCount += 1 }
            }
            if sample.time >= target + 0.005 {
                guard bitValidCount > 0, Double(bitValidCount) >= Double(bitCount) * 0.8 else {
                    self = VISDecoder(); throw DecoderError.badParity
                }
                let frequency = bitSum / Double(bitValidCount)
                bitSum = 0; bitValidCount = 0; bitCount = 0
                if bitIndex < 8 {
                    let one = abs(frequency - Robot36.visOne) < 45
                    let zero = abs(frequency - Robot36.visZero) < 45
                    guard one || zero else { self = VISDecoder(); throw DecoderError.badParity }
                    if one { ones += 1; if bitIndex < 7 { code |= 1 << bitIndex } }
                } else {
                    let result = code
                    let valid = abs(frequency - Robot36.syncFrequency) < 45 && ones % 2 == 0
                    self = VISDecoder()
                    guard valid else { throw DecoderError.badParity }
                    guard result == Robot36.vis else { throw DecoderError.unsupportedMode(result) }
                    return (result, start + 10 * Robot36.visBit)
                }
                bitIndex += 1
            }
            return nil
        }
        // Header tones last at least 10 ms. A 2 ms median suppresses acoustic
        // frequency jitter without smoothing the image's much faster pixel data.
        let filtered = headerFilter.append(sample)
        let frequency = filtered.hertz
        let time = filtered.time
        if stage > 0 && time > deadline { stage = 0 }
        let next = !filtered.valid ? 0 : abs(frequency - Robot36.center) < 70 ? 1900 : abs(frequency - Robot36.syncFrequency) < 45 ? 1200 : 0
        if next == tone {
            candidateTone = tone
        } else if next != candidateTone {
            candidateTone = next
            candidateStart = time
        } else if time - candidateStart >= 0.0015 {
            // Short outliers must not split a 300 ms leader into invalid fragments.
            // Keep the original edge timestamp rather than adding debounce latency.
            let transition = candidateStart
            let length = transition - runStart
            if length >= 0.004 {
                switch (stage, tone) {
                case (_, 0) where length <= 0.010:
                    // Acoustic transitions can briefly leave both tone bands.
                    // Preserve the sequence, but never extend its deadline.
                    break
                case (0, 1900) where length >= 0.25:
                    stage = 1; deadline = transition + 0.04
                case (1, 1200) where (0.006...0.018).contains(length):
                    stage = 2; deadline = transition + 0.4
                case (2, 1900) where length >= 0.25:
                    stage = 3; deadline = transition + 0.06
                case (3, 1200) where (0.024...0.036).contains(length):
                    frameStart = runStart; bitIndex = 0; code = 0; ones = 0
                default: stage = 0
                }
            }
            tone = next; runStart = transition
        }
        return nil
    }
}

import Foundation

struct Robot36Decoder {
    private(set) var pixels = [UInt8](repeating: 32, count: Robot36.width * Robot36.height * 3)
    private(set) var lines = 0
    private(set) var syncPulses = 0
    private var sync = SyncDetector()
    private let requiresAcquisition: Bool
    private var start: Double?
    private var period = Robot36.line
    private var missingSyncs = 0
    private var samples = [FrequencySample]()
    private var lastCr = [Double](repeating: 128, count: Robot36.width)
    private var lastCb = [Double](repeating: 128, count: Robot36.width)
    private var previousY: [Double]?
    private var previousIsCr: Bool?

    init(start: Double? = nil) { self.requiresAcquisition = start == nil; self.start = start; samples.reserveCapacity(4000) }

    mutating func append(_ sample: FrequencySample, control: FrequencySample) throws {
        guard lines < Robot36.height else { return }
        samples.append(sample)
        if let detected = sync.append(control) {
            syncPulses += 1
            if let start {
                let interval = detected - start
                if (0.14...0.16).contains(interval) {
                    missingSyncs = 0
                    period = interval
                    try decodeLine(start: start, duration: interval)
                    self.start = detected
                    samples.removeAll { $0.time < detected - 0.001 }
                } else if interval > 0.16 {
                    if requiresAcquisition && lines == 0 { self.start = detected }
                    else { throw DecoderError.signalLost }
                }
            } else {
                start = detected
                samples.removeAll { $0.time < detected - 0.001 }
            }
        }
        if let start {
            if lines == Robot36.height - 1 && sample.time >= start + period {
                try decodeLine(start: start, duration: period)
            } else if sample.time > start + period + 0.025 {
                if requiresAcquisition && lines == 0 {
                    self.start = nil
                    samples.removeAll(keepingCapacity: true)
                } else if lines > 0 && missingSyncs == 0 {
                    // Once locked, one missing pulse need not discard valid image
                    // audio. Coast for exactly one line; require the next sync.
                    try decodeLine(start: start, duration: period)
                    missingSyncs = 1
                    self.start = start + period
                    samples.removeAll { $0.time < start + period - 0.001 }
                } else { throw DecoderError.signalLost }
            }
        } else if samples.count > 4000 {
            samples.removeFirst(2000)
        }
    }

    mutating func finish() throws {
        guard lines < Robot36.height else { return }
        if let start, let last = samples.last, last.time >= start + period - 0.0005 {
            // At EOF, the measured sync clock can overshoot by a fraction of a
            // millisecond. Sample within the actual endpoint, only within the
            // accepted timing uncertainty; never read or invent audio past EOF.
            try decodeLine(start: start, duration: min(period, last.time - start))
        }
        if lines < Robot36.height { throw DecoderError.incomplete(lines) }
    }

    private mutating func decodeLine(start: Double, duration: Double) throws {
        guard lines < Robot36.height else { return }
        let scale = duration / Robot36.line
        func frequency(at relative: Double) -> Double? {
            let time = start + relative * scale
            var low = 0, high = samples.count
            while low < high {
                let mid = (low + high) / 2
                if samples[mid].time < time { low = mid + 1 } else { high = mid }
            }
            guard low > 0, low < samples.count else { return nil }
            // Destructive interference can null one phase estimate. Bridge only
            // a sub-millisecond gap, never an absent scanline or sustained fade.
            var left = low - 1, right = low
            while left > 0 && !samples[left].valid && time - samples[left].time < 0.0005 { left -= 1 }
            while right < samples.count - 1 && !samples[right].valid && samples[right].time - time < 0.0005 { right += 1 }
            let a = samples[left], b = samples[right]
            guard a.valid, b.valid, b.time - a.time <= 0.001 else { return nil }
            let fraction = (time - a.time) / max(0.000001, b.time - a.time)
            return a.hertz + fraction * (b.hertz - a.hertz)
        }
        // The separator lasts 4.5 ms. A single phase estimate can spike far
        // outside its tone in acoustic input; average its central 2 ms instead.
        let separatorCenter = start + (Robot36.separatorStart + Robot36.separator / 2) * scale
        let separatorSamples = samples.filter { abs($0.time - separatorCenter) < 0.001 * scale }
        let validSeparator = separatorSamples.filter(\.valid)
        let separator = validSeparator.reduce(0.0) { $0 + $1.hertz } / Double(max(1, validSeparator.count))
        guard !validSeparator.isEmpty, Double(validSeparator.count) >= Double(separatorSamples.count) * 0.8,
              abs(separator - Robot36.black) < 150 || abs(separator - Robot36.white) < 150 else {
            throw DecoderError.signalLost
        }
        let isCr = separator < Robot36.center
        if let previousIsCr, previousIsCr == isCr { throw DecoderError.signalLost }
        var y = [Double](), chroma = [Double]()
        for x in 0..<Robot36.width {
            let fraction = (Double(x) + 0.5) / Double(Robot36.width)
            guard let luma = frequency(at: Robot36.yStart + fraction * Robot36.luminance),
                  let color = frequency(at: Robot36.chromaStart + fraction * Robot36.chroma) else {
                throw DecoderError.signalLost
            }
            y.append(max(0, min(255, (luma - Robot36.black) * 255 / 800)))
            chroma.append(max(0, min(255, (color - Robot36.black) * 255 / 800)))
        }
        if isCr { lastCr = chroma } else { lastCb = chroma }
        // A pair shares Cr and Cb; redraw the previous line once its missing chroma arrives.
        if let previousY, previousIsCr == true, !isCr { write(row: lines - 1, y: previousY) }
        write(row: lines, y: y)
        previousY = y; previousIsCr = isCr
        lines += 1
    }

    private mutating func write(row: Int, y: [Double]) {
        for x in 0..<Robot36.width {
            let cr = lastCr[x] - 128, cb = lastCb[x] - 128
            let values = [y[x] + 1.402 * cr, y[x] - 0.344136 * cb - 0.714136 * cr, y[x] + 1.772 * cb]
            for c in 0..<3 { pixels[(row * Robot36.width + x) * 3 + c] = UInt8(max(0, min(255, values[c].rounded()))) }
        }
    }
}

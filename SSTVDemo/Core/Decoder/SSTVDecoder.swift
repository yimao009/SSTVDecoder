import Foundation

public struct DecoderSnapshot: Sendable {
    public let pixels: [UInt8]
    public let lines: Int
    public let detected: Bool
    public let receivedSeconds: Double
    public let syncPulses: Int
    public var completed: Bool { lines == 240 }
}

/// Value-type engine owned exclusively by the input task. No main actor or audio APIs.
public struct SSTVDecoder {
    private let sampleRate: Double
    private let manual: Bool
    private var demodulator: FrequencyDemodulator
    private var controlDemodulator: FrequencyDemodulator
    private var pendingImageSamples = [FrequencySample]()
    private var vis = VISDecoder()
    private var searchingSync = SyncDetector()
    private var searchSyncPulses = 0
    private var robot: Robot36Decoder?
    private var sampleCount = 0
    private var peak: Float = 0
    private var terminalError: DecoderError?
    public var lines: Int { robot?.lines ?? 0 }
    public var detected: Bool { robot != nil && (!manual || lines > 0) }
    public var completed: Bool { lines == Robot36.height }
    public var elapsed: Double { Double(sampleCount) / sampleRate }
    public var snapshot: DecoderSnapshot {
        .init(pixels: robot?.pixels ?? [UInt8](repeating: 32, count: Robot36.width * Robot36.height * 3), lines: lines, detected: detected, receivedSeconds: elapsed, syncPulses: searchSyncPulses + (robot?.syncPulses ?? 0))
    }

    public init(sampleRate: Double, manual: Bool = false) throws {
        self.sampleRate = sampleRate; self.manual = manual
        demodulator = try FrequencyDemodulator(sampleRate: sampleRate)
        controlDemodulator = try FrequencyDemodulator(sampleRate: sampleRate, controlTones: true)
        if manual { robot = Robot36Decoder() }
    }

    public mutating func reset() throws { self = try SSTVDecoder(sampleRate: sampleRate, manual: manual) }

    public mutating func append(samples: [Float]) throws {
        if let terminalError { throw terminalError }
        guard !completed else { return }
        do {
            for sample in samples {
                sampleCount += 1; peak = max(peak, abs(sample))
                try demodulate(sample)
                if completed { break }
            }
        } catch let error as DecoderError { terminalError = error; throw error }
    }

    private mutating func demodulate(_ value: Float, endingAt: Double? = nil) throws {
        if let sample = demodulator.append(value) { pendingImageSamples.append(sample) }
        guard let control = controlDemodulator.append(value) else { return }
        // Align the two FIR group delays before using control timing for pixels.
        while pendingImageSamples.count > 1 && pendingImageSamples[1].time <= control.time {
            pendingImageSamples.removeFirst()
        }
        guard let sample = pendingImageSamples.first, sample.time <= control.time else { return }
        if let endingAt, sample.time > endingAt { return }
        pendingImageSamples.removeFirst()
        // A narrow-band residual alone is not evidence of a control tone.
        let usable = control.valid && control.magnitude >= sample.magnitude * 0.25
        let syncSample = FrequencySample(time: sample.time, hertz: control.hertz, magnitude: usable ? control.magnitude : 0)
        let headerSample = usable && (1000...1400).contains(control.hertz) ? syncSample : sample
        try process(sample, control: syncSample, header: headerSample)
    }

    private mutating func process(_ sample: FrequencySample, control: FrequencySample, header: FrequencySample) throws {
        if robot == nil, searchingSync.append(control) != nil { searchSyncPulses += 1 }
        if manual && lines == 0, let header = try? vis.append(header) {
            robot = Robot36Decoder(start: header.imageStart)
        } else if robot != nil { try robot?.append(sample, control: control) }
        else if let header = try vis.append(header) { robot = Robot36Decoder(start: header.imageStart) }
    }

    public mutating func finish() throws {
        if let terminalError { throw terminalError }
        if completed { return }
        do {
            guard sampleCount > 0 else { throw DecoderError.noSignal }
            // Flush only the FIR delay; timestamps still refer to the original audio.
            for _ in 0..<Int(sampleRate * 0.006) {
                try demodulate(0, endingAt: elapsed)
            }
            guard peak > 0.0002 else { throw DecoderError.weakSignal }
            guard robot != nil else { throw DecoderError.noSignal }
            try robot?.finish()
        } catch let error as DecoderError { terminalError = error; throw error }
    }
}

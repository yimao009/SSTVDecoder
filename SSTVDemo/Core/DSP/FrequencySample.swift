struct FrequencySample: Sendable {
    let time: Double
    let hertz: Double
    let magnitude: Double
    var valid: Bool { magnitude > 0.0001 && hertz.isFinite }
}

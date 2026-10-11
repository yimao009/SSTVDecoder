import Foundation

/// Complex FIR extracts the positive-frequency band (analytic signal).
/// Equivalent to band limiting followed by Hilbert quadrature, with a known group delay.
struct BandpassFilter {
    let real: [Double]
    let imaginary: [Double]
    var count: Int { real.count }
    init(sampleRate: Double, controlTones: Bool = false) {
        let half = Int(ceil(sampleRate * (controlTones ? 0.003 : 0.0018)))
        let bandwidth = controlTones ? 200.0 : 1100.0
        let center = controlTones ? Robot36.syncFrequency : Robot36.center
        var real = [Double](), imaginary = [Double]()
        for index in -half...half {
            let x = Double(index)
            let lowpass = index == 0 ? 2 * bandwidth / sampleRate : sin(2 * .pi * bandwidth * x / sampleRate) / (.pi * x)
            let window = 0.42 + 0.5 * cos(.pi * x / Double(half)) + 0.08 * cos(2 * .pi * x / Double(half))
            let phase = 2 * .pi * center * x / sampleRate
            real.append(2 * lowpass * window * cos(phase))
            imaginary.append(2 * lowpass * window * sin(phase))
        }
        self.real = real.reversed()
        self.imaginary = imaginary.reversed()
    }
}

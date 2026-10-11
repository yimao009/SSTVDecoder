import Foundation

/// Independent transmitter fixture: cumulative timing avoids per-pixel rounding drift.
struct SignalFactory {
    let rate: Double
    var scale = 1.0
    var phase = 0.0
    var end = 0.0
    var samples = [Float]()
    mutating func tone(_ frequency: Double, _ duration: Double) {
        end += duration * rate * scale
        while samples.count < Int(end.rounded()) {
            samples.append(Float(0.75 * sin(phase)))
            phase += 2 * .pi * frequency / rate
            if phase > 2 * .pi { phase -= 2 * .pi }
        }
    }
    mutating func vis(code: Int = 8, badParity: Bool = false) {
        tone(1900, 0.3); tone(1200, 0.01); tone(1900, 0.3); tone(1200, 0.03)
        for bit in 0..<7 { tone(code & (1 << bit) == 0 ? 1300 : 1100, 0.03) }
        let parity = code.nonzeroBitCount % 2 == 1
        tone(parity != badParity ? 1100 : 1300, 0.03)
        tone(1200, 0.03)
    }
}

extension SignalFactory {
    static func rgb(x: Int, y: Int) -> [Double] {
        let colors: [[Double]] = [[230,220,210],[220,30,40],[30,210,40],[30,40,220],[210,210,30],[30,210,210],[210,30,210],[30,30,30]]
        return colors[min(7, x / 40)].map { $0 * (y < 120 ? 1 : 0.55) }
    }
    mutating func image(lines: Int = 240) {
        for row in 0..<lines {
            tone(1200, 0.009); tone(1500, 0.003)
            let rgb = (0..<320).map { Self.rgb(x: $0, y: row) }
            let y = rgb.map { 0.299 * $0[0] + 0.587 * $0[1] + 0.114 * $0[2] }
            for value in y { tone(1500 + 800 * value / 255, 0.088 / 320) }
            tone(row % 2 == 0 ? 1500 : 2300, 0.0045); tone(1900, 0.0015)
            for col in 0..<320 {
                let chroma = row % 2 == 0 ? 128 + (rgb[col][0] - y[col]) / 1.402 : 128 + (rgb[col][2] - y[col]) / 1.772
                tone(1500 + 800 * chroma / 255, 0.044 / 320)
            }
        }
    }
}

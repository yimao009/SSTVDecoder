import Foundation

public enum Robot36 {
    public static let width = 320
    public static let height = 240
    static let vis = 8
    static let syncFrequency = 1200.0
    static let black = 1500.0
    static let white = 2300.0
    static let center = 1900.0
    static let sync = 0.009
    static let porch = 0.003
    static let luminance = 0.088
    static let separator = 0.0045
    static let chromaPorch = 0.0015
    static let chroma = 0.044
    static let line = sync + porch + luminance + separator + chromaPorch + chroma
    static let yStart = sync + porch
    static let separatorStart = yStart + luminance
    static let chromaStart = separatorStart + separator + chromaPorch
    static let visBit = 0.030
    static let visOne = 1100.0
    static let visZero = 1300.0
}

public enum DecoderError: Error, LocalizedError, Sendable, Equatable {
    case invalidSampleRate, unsupportedMode(Int), badParity, noSignal, weakSignal
    case signalLost, incomplete(Int), invalidWAV, unsupportedWAV, overloaded
    public var errorDescription: String? {
        switch self {
        case .invalidSampleRate: "不支持此采样率，请使用 8–192 kHz 音频。"
        case .unsupportedMode(let code): "检测到 VIS \(code)，当前仅支持 Robot 36（VIS 8）。"
        case .badParity: "VIS 校验失败，请改善信号或尝试手动 Robot 36。"
        case .noSignal: "没有检测到 SSTV 信号，请检查音源或尝试手动模式。"
        case .weakSignal: "音频信号过弱，请靠近音源或提高输入音量。"
        case .signalLost: "扫描行同步丢失，请重新接收完整信号。"
        case .incomplete(let lines): "音频提前结束，仅恢复了 \(lines)/240 行。"
        case .invalidWAV: "WAV 文件为空、损坏或无法读取。"
        case .unsupportedWAV: "请选择单声道或双声道的 PCM / IEEE Float WAV 文件。"
        case .overloaded: "音频处理跟不上输入，已停止以避免生成错位图片。请重试。"
        }
    }
}

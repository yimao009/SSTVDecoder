import Foundation

enum ReceiverState: String, Sendable {
    case idle, listening, detecting, decoding, completed, failed
    var title: String {
        switch self {
        case .idle: "等待开始"
        case .listening: "正在监听音频"
        case .detecting: "检测 SSTV 信号"
        case .decoding: "正在恢复图片"
        case .completed: "图片生成完成"
        case .failed: "接收未完成"
        }
    }
}

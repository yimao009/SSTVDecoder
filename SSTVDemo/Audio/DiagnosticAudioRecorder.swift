import AVFoundation

/// Opt-in capture of the exact mono PCM passed to the decoder. Owned by its
/// background task; never called by the audio tap. Bounded to 45 seconds on disk.
final class DiagnosticAudioRecorder {
    private(set) var url: URL
    private var file: AVAudioFile?
    private let buffer: AVAudioPCMBuffer
    private let limit: Int
    private(set) var frames = 0
    private var delivered = false

    init(sampleRate: Double, directory: URL = FileManager.default.temporaryDirectory) throws {
        guard sampleRate.isFinite, (8000...192000).contains(sampleRate),
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else {
            throw DiagnosticRecordingError.failed
        }
        self.buffer = buffer
        limit = Int(sampleRate * 45)
        url = directory.appendingPathComponent("SSTV-diagnostic-\(UUID().uuidString).wav")
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false
        ])
    }

    func append(_ samples: [Float]) throws {
        guard let file else { return }
        var offset = 0
        while offset < samples.count && frames < limit {
            let count = min(Int(buffer.frameCapacity), samples.count - offset, limit - frames)
            guard let channel = buffer.floatChannelData?[0] else { throw DiagnosticRecordingError.failed }
            for index in 0..<count { channel[index] = samples[offset + index] }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer)
            offset += count; frames += count
        }
    }

    func finish() -> URL? {
        file = nil // Close before sharing so the WAV header contains the final frame count.
        delivered = frames > 0
        return delivered ? url : nil
    }

    deinit {
        file = nil
        if !delivered { try? FileManager.default.removeItem(at: url) }
    }
}

enum DiagnosticRecordingError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "无法保存诊断录音，请检查手机可用空间后重试。" }
}

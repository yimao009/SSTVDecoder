import AVFoundation
#if SWIFT_PACKAGE
import SSTVCore
#endif

/// Owned by one decoding task; file data is never retained beyond the current chunk.
public final class AudioFileService {
    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer
    private let url: URL
    private let scoped: Bool
    public let sampleRate: Double
    public var progress: Double { Double(file.framePosition) / Double(max(1, file.length)) }

    public init(url: URL) throws {
        self.url = url
        scoped = url.startAccessingSecurityScopedResource()
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try Self.validateWAV(handle)
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let source = file.fileFormat.streamDescription.pointee
            guard source.mFormatID == kAudioFormatLinearPCM,
                  (1...2).contains(file.processingFormat.channelCount) else { throw DecoderError.unsupportedWAV }
            sampleRate = file.processingFormat.sampleRate
            guard (8000...192000).contains(sampleRate) else { throw DecoderError.invalidSampleRate }
            guard file.length > 0, let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else {
                throw DecoderError.invalidWAV
            }
            buffer = pcm
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw (error as? DecoderError) ?? .invalidWAV
        }
    }

    private static func validateWAV(_ handle: FileHandle) throws {
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let header = try handle.read(upToCount: 12) ?? Data()
        guard header.count == 12,
              String(data: header.prefix(4), encoding: .ascii) == "RIFF",
              String(data: header.suffix(4), encoding: .ascii) == "WAVE" else { throw DecoderError.unsupportedWAV }
        func uint32(_ bytes: Data, _ offset: Int) -> UInt64 {
            (0..<4).reduce(0) { $0 | (UInt64(bytes[offset + $1]) << ($1 * 8)) }
        }
        let end = uint32(header, 4) + 8
        guard end <= size, end >= 12 else { throw DecoderError.invalidWAV }
        var offset: UInt64 = 12
        var alignment: UInt64 = 0
        var dataBytes: UInt64 = 0
        while offset + 8 <= end {
            try handle.seek(toOffset: offset)
            let chunk = try handle.read(upToCount: 8) ?? Data()
            guard chunk.count == 8 else { throw DecoderError.invalidWAV }
            let length = uint32(chunk, 4)
            guard length <= end - offset - 8 else { throw DecoderError.invalidWAV }
            let id = String(data: chunk.prefix(4), encoding: .ascii)
            if id == "fmt " {
                guard length >= 16 else { throw DecoderError.invalidWAV }
                let format = try handle.read(upToCount: 16) ?? Data()
                guard format.count == 16 else { throw DecoderError.invalidWAV }
                let encoding = UInt16(format[0]) | UInt16(format[1]) << 8
                guard [1, 3, 0xfffe].contains(encoding) else { throw DecoderError.unsupportedWAV }
                alignment = UInt64(format[12]) | UInt64(format[13]) << 8
            } else if id == "data" { dataBytes += length }
            offset += 8 + length + length % 2
        }
        guard alignment > 0, dataBytes > 0, dataBytes % alignment == 0, offset == end else {
            throw DecoderError.invalidWAV
        }
    }

    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }

    public func read() throws -> [Float]? {
        guard file.framePosition < file.length else { return nil }
        do { try file.read(into: buffer, frameCount: buffer.frameCapacity) }
        catch { throw DecoderError.invalidWAV }
        guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { throw DecoderError.invalidWAV }
        let count = Int(buffer.frameLength)
        var mono = [Float](repeating: 0, count: count)
        for channel in 0..<Int(buffer.format.channelCount) {
            for i in 0..<count {
                let value = channels[channel][i]
                guard value.isFinite else { throw DecoderError.invalidWAV }
                mono[i] += value / Float(buffer.format.channelCount)
            }
        }
        return mono
    }
}

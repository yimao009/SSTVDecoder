import AVFoundation
import Foundation

/// Every mutable field and slot is protected by lock. The audio producer uses try-lock,
/// never waits or allocates sample arrays, and reports overflow rather than dropping PCM.
final class PCMBufferQueue: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity = 16
    private let maxFrames = 8192
    private let storage: [UnsafeMutablePointer<Float>]
    private var lengths = [Int](repeating: 0, count: 16)
    private var head = 0
    private var tail = 0
    private var count = 0

    init() {
        storage = (0..<16).map { _ in .allocate(capacity: 8192) }
    }
    deinit { for pointer in storage { pointer.deallocate() } }

    func push(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard lock.try() else { return false }
        defer { lock.unlock() }
        let frames = Int(buffer.frameLength)
        guard count < capacity, frames <= maxFrames, frames > 0,
              let channels = buffer.floatChannelData else { return false }
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0, !buffer.format.isInterleaved else { return false }
        let slot = storage[tail]
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channelCount { sum += channels[channel][frame] }
            slot[frame] = sum / Float(channelCount)
        }
        lengths[tail] = frames
        tail = (tail + 1) % capacity; count += 1
        return true
    }

    func pop() -> [Float]? {
        lock.lock(); defer { lock.unlock() }
        guard count > 0 else { return nil }
        let samples = Array(UnsafeBufferPointer(start: storage[head], count: lengths[head]))
        head = (head + 1) % capacity; count -= 1
        return samples
    }
}

import AVFoundation

@MainActor
protocol AudioInputProviding: AnyObject {
    var onEvent: (@MainActor (AudioInputService.Event) -> Void)? { get set }
    func requestPermission() async -> Bool
    func start() async throws -> AudioInputService.Session
    func pause()
    func stop()
}

@MainActor
final class AudioInputService: AudioInputProviding {
    enum Event: Sendable { case interrupted, interruptionEnded(Bool), routeChanged }
    struct Session: Sendable {
        let sampleRate: Double
        let inputName: String
        let queue: PCMBufferQueue
        let events: AsyncThrowingStream<Void, Error>
    }
    var onEvent: (@MainActor (Event) -> Void)?
    private let worker = AudioEngineWorker()
    private let operations = AudioLifecycleQueue()
    private var observers = [NSObjectProtocol]()

    func requestPermission() async -> Bool { await AVAudioApplication.requestRecordPermission() }

    func start() async throws -> Session {
        try Task.checkCancellation()
        observeIfNeeded()
        let worker = worker
        let operation = operations.enqueue { try await worker.start() }
        let session = try await operation.value
        try Task.checkCancellation()
        return session
    }

    // AVAudioEngine invokes this on its audio thread. Creating a non-Sendable
    // closure inside start() inherits MainActor and traps under Swift 6.
    nonisolated static func makeTap(
        queue: PCMBufferQueue,
        sink: AsyncThrowingStream<Void, Error>.Continuation
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { @Sendable buffer, _ in
            if queue.push(buffer) { sink.yield(()) }
            else { sink.finish(throwing: DecoderError.overloaded) }
        }
    }

    func pause() {
        let worker = worker
        operations.enqueue { await worker.pause() }
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        let worker = worker
        operations.enqueue { await worker.stop() }
    }

    private func observeIfNeeded() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            let event: Event = type == .began ? .interrupted : .interruptionEnded(AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume))
            Task { @MainActor [weak self] in self?.onEvent?(event) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: value),
                  [.newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange].contains(reason) else { return }
            Task { @MainActor [weak self] in self?.onEvent?(.routeChanged) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onEvent?(.routeChanged) }
        })
    }
}

enum InputError: Error, LocalizedError {
    case denied, unavailable
    var errorDescription: String? {
        switch self {
        case .denied: "麦克风权限未开启，请在系统设置中允许访问麦克风。仍可导入 WAV 文件。"
        case .unavailable: "无法启动麦克风，可能被其他应用占用或输入设备不可用。请检查后重试。"
        }
    }
}

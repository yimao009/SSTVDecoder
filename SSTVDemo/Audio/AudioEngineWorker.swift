import AVFoundation

/// Engine and session mutations stay on this actor, away from the UI executor.
/// Methods contain no suspension points, so activation cannot interleave with teardown.
actor AudioEngineWorker {
    private var engine: AVAudioEngine?
    private var continuation: AsyncThrowingStream<Void, Error>.Continuation?
    private var active = false

    func start() throws -> AudioInputService.Session {
        pause()
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setPreferredIOBufferDuration(0.02)
            try audioSession.setActive(true)
            active = true
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, (8000...192000).contains(format.sampleRate), format.commonFormat == .pcmFormatFloat32 else {
                throw InputError.unavailable
            }
            let queue = PCMBufferQueue()
            let stream = AsyncThrowingStream<Void, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
            continuation = stream.continuation
            input.installTap(onBus: 0, bufferSize: 1024, format: format,
                             block: AudioInputService.makeTap(queue: queue, sink: stream.continuation))
            self.engine = engine
            engine.prepare()
            try engine.start()
            return AudioInputService.Session(sampleRate: format.sampleRate, inputName: audioSession.currentRoute.inputs.map(\.portName).joined(separator: "、"), queue: queue, events: stream.stream)
        } catch {
            stop()
            throw InputError.unavailable
        }
    }

    func pause() {
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil
        continuation?.finish(); continuation = nil
    }

    func stop() {
        pause()
        guard active else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            active = false
        } catch {
            // Keep ownership if deactivation fails, allowing the next stop to retry.
        }
    }
}

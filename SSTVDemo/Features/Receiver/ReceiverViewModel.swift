import SwiftUI
import Observation

@MainActor @Observable
final class ReceiverViewModel {
    private(set) var state = ReceiverState.idle
    private(set) var image: CGImage?
    private(set) var lines = 0
    private(set) var inputProgress = 0.0
    private(set) var level = 0.0
    private(set) var busy = false
    private(set) var detail = "导入 WAV，或通过麦克风接收 Robot 36。"
    private(set) var pngData: Data?
    var manualMode = false
    var recordDiagnostics = false
    private(set) var diagnosticURL: URL?
    private(set) var inputDescription = "尚未启动麦克风"
    private(set) var receivedSeconds = 0.0
    private(set) var syncPulses = 0
    @ObservationIgnored private var captureID = UUID()
    var errorMessage: String?
    var showingError = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let audioInput: any AudioInputProviding
    @ObservationIgnored private var microphoneRequested = false
    @ObservationIgnored private var interrupted = false
    private(set) var usingMicrophone = false

    init(audioInput: any AudioInputProviding = AudioInputService()) {
        self.audioInput = audioInput
        audioInput.onEvent = { [weak self] event in self?.handleAudioEvent(event) }
    }

    deinit { task?.cancel() }

    func startMicrophone() {
        stop()
        microphoneRequested = true
        beginMicrophone()
    }

    private func beginMicrophone() {
        task?.cancel(); audioInput.pause()
        let id = UUID(); generation = id
        busy = true; usingMicrophone = true; state = .listening
        image = nil; lines = 0; pngData = nil; level = 0; inputProgress = 0
        detail = "正在准备麦克风，请稍候再播放音频。"
        let manual = manualMode
        let capture = recordDiagnostics
        let recordingID = UUID(); captureID = recordingID
        let previousRecording = diagnosticURL
        if capture { diagnosticURL = nil }
        inputDescription = "正在准备输入"; receivedSeconds = 0; syncPulses = 0
        task = Task { [weak self] in
            guard let self else { return }
            guard await audioInput.requestPermission() else {
                fail(InputError.denied.localizedDescription, id: id); return
            }
            guard generation == id, !Task.isCancelled else { return }
            do {
                let session = try await audioInput.start()
                // Stop or restart may have arrived while activation was in progress.
                guard generation == id, !Task.isCancelled else { return }
                inputDescription = "\(session.inputName) · \(Int(session.sampleRate)) Hz"
                detail = "麦克风已就绪，请从头播放完整 Robot 36 音频。"
                task = Task.detached(priority: .userInitiated) { [weak self] in
                    var recording: DiagnosticAudioRecorder?
                    do {
                        if capture {
                            if let previousRecording { try? FileManager.default.removeItem(at: previousRecording) }
                            recording = try DiagnosticAudioRecorder(sampleRate: session.sampleRate)
                        }
                        var decoder = try SSTVDecoder(sampleRate: session.sampleRate, manual: manual)
                        var rendered = 0
                        var lastMeter = 0.0
                        var quietDuration = 0.0
                        var totalSeconds = 0.0
                        var previousSyncPulses = 0
                        var recoveryMessage: String?
                        receiving: for try await _ in session.events {
                            while let samples = session.queue.pop() {
                                try Task.checkCancellation()
                                try recording?.append(samples)
                                totalSeconds += Double(samples.count) / session.sampleRate
                                let rms = sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count)))
                                quietDuration = rms < 0.0002 ? quietDuration + Double(samples.count) / session.sampleRate : 0
                                if quietDuration > 8 && recoveryMessage == nil { throw DecoderError.weakSignal }
                                do {
                                    try decoder.append(samples: samples)
                                } catch let error as DecoderError where error == .signalLost || error == .badParity {
                                    recoveryMessage = error == .signalLost ? "扫描行同步丢失" : "VIS 校验失败"
                                    let snapshot = decoder.snapshot
                                    previousSyncPulses += snapshot.syncPulses
                                    await self?.applyMicrophone(snapshot, rms: rms, elapsed: totalSeconds,
                                                               pulses: previousSyncPulses, recovery: recoveryMessage, id: id)
                                    // Keep capture and its recording alive. A new VIS establishes
                                    // a frame boundary; never splice the remainder onto old rows.
                                    decoder = try SSTVDecoder(sampleRate: session.sampleRate)
                                    rendered = 0; lastMeter = totalSeconds
                                    continue
                                }
                                if decoder.lines > 0 { recoveryMessage = nil }
                                if decoder.lines >= rendered + 2 || totalSeconds - lastMeter >= 0.1 {
                                    rendered = decoder.lines; lastMeter = totalSeconds
                                    await self?.applyMicrophone(decoder.snapshot, rms: rms, elapsed: totalSeconds,
                                                               pulses: previousSyncPulses + decoder.snapshot.syncPulses,
                                                               recovery: recoveryMessage, id: id)
                                }
                                if decoder.completed {
                                    let snapshot = decoder.snapshot
                                    let png = try ImageExporter.png(pixels: snapshot.pixels)
                                    try Task.checkCancellation()
                                    await self?.complete(snapshot, png: png, id: id, totalSeconds: totalSeconds,
                                                        totalPulses: previousSyncPulses + snapshot.syncPulses)
                                    break receiving
                                }
                                if decoder.elapsed > 60 && !decoder.detected && recoveryMessage == nil { throw DecoderError.noSignal }
                            }
                        }
                        if !decoder.completed {
                            try Task.checkCancellation()
                            throw DecoderError.signalLost
                        }
                    } catch is CancellationError {
                    } catch { await self?.fail(error.localizedDescription, id: id) }
                    if let url = recording?.finish() {
                        let retained = await self?.publishRecording(url, id: recordingID) ?? false
                        if !retained { try? FileManager.default.removeItem(at: url) }
                    }
                }
            } catch { fail(error.localizedDescription, id: id) }
        }
    }

    private func publishRecording(_ url: URL, id: UUID) -> Bool {
        guard captureID == id else { return false }
        diagnosticURL = url
        return true
    }

    private func applyMicrophone(_ snapshot: DecoderSnapshot, rms: Double, elapsed: Double,
                                 pulses: Int, recovery: String?, id: UUID) {
        guard generation == id else { return }
        if recovery == nil || snapshot.lines > 0 { apply(snapshot, progress: 0, id: id) }
        receivedSeconds = elapsed
        syncPulses = pulses
        level = max(0, min(1, (20 * log10(max(rms, 0.000001)) + 60) / 60))
        if let recovery {
            state = .detecting
            detail = "\(recovery)，已保留 \(lines) 行。继续监听，请从头重播带前导的完整音频。"
            return
        }
        if elapsed < 0.5 { state = .listening }
        if !snapshot.detected {
            if rms < 0.0002 {
                detail = "麦克风已就绪，输入音量较低；请播放音频并检查输入电平。"
            } else {
                detail = manualMode
                    ? "已收到音频，正在寻找 Robot 36 行同步。"
                    : "已收到音频，等待 Robot 36 VIS；请从音频开头播放。"
            }
        }
        if rms > 0.85 { detail = "输入音量过高，请降低音源音量，避免削波。" }
    }

    private func handleAudioEvent(_ event: AudioInputService.Event) {
        guard microphoneRequested else { return }
        switch event {
        case .interrupted:
            interrupted = true
            generation = UUID(); task?.cancel(); task = nil; audioInput.pause()
            state = .listening; level = 0
            detail = "音频已中断，恢复后将重新等待完整 SSTV 信号。"
        case .interruptionEnded(let shouldResume):
            interrupted = false
            if shouldResume { beginMicrophone() }
            else { fail("音频中断已结束，请点击开始接收重新启动。", id: generation) }
        case .routeChanged:
            if !interrupted { beginMicrophone() }
        }
    }

    func importFile(_ url: URL) {
        stop()
        let id = UUID(); generation = id
        busy = true; state = .detecting; image = nil; lines = 0; pngData = nil; inputProgress = 0
        receivedSeconds = 0; syncPulses = 0; inputDescription = "文件输入"
        detail = "读取 \(url.lastPathComponent)"
        let manual = manualMode
        task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let reader = try AudioFileService(url: url)
                var decoder = try SSTVDecoder(sampleRate: reader.sampleRate, manual: manual)
                var rendered = 0
                var reported = 0.0
                while let samples = try reader.read() {
                    try Task.checkCancellation()
                    try decoder.append(samples: samples)
                    if decoder.lines >= rendered + 2 || reader.progress >= reported + 0.02 {
                        rendered = decoder.lines; reported = reader.progress
                        await self?.apply(decoder.snapshot, progress: reported, id: id)
                    }
                    if decoder.completed { break }
                }
                try Task.checkCancellation()
                try decoder.finish()
                let snapshot = decoder.snapshot
                let png = try ImageExporter.png(pixels: snapshot.pixels)
                try Task.checkCancellation()
                await self?.complete(snapshot, png: png, id: id)
            } catch is CancellationError {
                // Explicit stop owns the UI transition; stale tasks never publish.
            } catch { await self?.fail(error.localizedDescription, id: id) }
        }
    }

    private func apply(_ snapshot: DecoderSnapshot, progress: Double, id: UUID) {
        guard generation == id else { return }
        if lines != snapshot.lines {
            image = ImageRenderer.image(from: snapshot.pixels)
            lines = snapshot.lines
        }
        receivedSeconds = snapshot.receivedSeconds
        syncPulses = snapshot.syncPulses
        inputProgress = progress
        state = snapshot.detected ? .decoding : .detecting
        detail = snapshot.detected ? "Robot 36 · 320 × 240 · 本机解码" : "正在寻找 \(manualMode ? "Robot 36 行同步" : "VIS 前导信号")"
    }

    private func complete(_ snapshot: DecoderSnapshot, png: Data, id: UUID,
                          totalSeconds: Double? = nil, totalPulses: Int? = nil) {
        guard generation == id else { return }
        apply(snapshot, progress: 1, id: id)
        if let totalSeconds { receivedSeconds = totalSeconds }
        if let totalPulses { syncPulses = totalPulses }
        audioInput.stop(); microphoneRequested = false; usingMicrophone = false
        pngData = png; state = .completed; busy = false; level = 0; task = nil
        detail = "已恢复 240 行，可以保存或分享 PNG。"
    }

    private func fail(_ message: String, id: UUID) {
        guard generation == id else { return }
        audioInput.stop(); microphoneRequested = false; usingMicrophone = false
        busy = false; state = .failed; level = 0; detail = message; task = nil
        showError(message)
    }

    func showError(_ message: String) { errorMessage = message; showingError = true }

    func stop() {
        generation = UUID(); task?.cancel(); task = nil; busy = false; level = 0
        microphoneRequested = false; usingMicrophone = false; interrupted = false; audioInput.stop()
        if state != .completed { state = .idle; detail = lines > 0 ? "已停止，保留当前预览。可以重新接收。" : "等待开始" }
    }
}

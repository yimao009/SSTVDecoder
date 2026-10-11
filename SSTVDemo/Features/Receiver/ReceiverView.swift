import SwiftUI
import UniformTypeIdentifiers

struct ReceiverView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ReceiverViewModel()
    @State private var importing = false
    @State private var exporting = false
    @State private var showingImage = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                preview
                controls
                Text(model.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                diagnostics
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.035, green: 0.05, blue: 0.065))
        .preferredColorScheme(.dark)
        .tint(.cyan)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.wav]) { result in
            switch result {
            case .success(let url): model.importFile(url)
            case .failure(let error): model.showError(error.localizedDescription)
            }
        }
        .fileExporter(isPresented: $exporting, document: model.pngData.map(PNGDocument.init), contentType: .png, defaultFilename: "SSTV-Robot36") { result in
            if case .failure(let error) = result { model.showError("保存失败：\(error.localizedDescription)") }
        }
        .alert("接收提示", isPresented: $model.showingError) {
            Button("知道了", role: .cancel) { }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $showingImage) {
            NavigationStack {
                if let image = model.image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
                        .padding().navigationTitle("Robot 36")
                        .toolbar { Button("关闭") { showingImage = false } }
                }
            }.preferredColorScheme(.dark)
        }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.stop() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SSTV Decoder", systemImage: "antenna.radiowaves.left.and.right")
                .font(.title2.bold())
            Text(model.state.title).font(.subheadline).foregroundStyle(.cyan)
        }
    }

    private var preview: some View {
        VStack(spacing: 14) {
            ZStack {
                Color(white: 0.125)
                if let image = model.image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path").font(.largeTitle).foregroundStyle(.cyan.opacity(0.7))
                        Text("等待图像信号").font(.headline)
                        Text("Robot 36 · 320 × 240").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityLabel("解码图像，已恢复 \(model.lines) 行，共 240 行")
            HStack {
                Text("ROBOT 36").font(.caption.monospaced().bold())
                Spacer()
                Text("\(model.lines) / 240 行").font(.caption.monospacedDigit())
            }
            ProgressView(value: Double(model.lines), total: 240).accessibilityLabel("图像恢复进度")
            if model.state == .completed {
                Button("查看完整图片", systemImage: "arrow.up.left.and.arrow.down.right") { showingImage = true }
                    .font(.subheadline)
            }
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("接收诊断") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("保存诊断录音", isOn: $model.recordDiagnostics)
                    .disabled(model.busy)
                Text("开启后保存实际送入解码器的麦克风音频，最多 45 秒，仅保存在本机。停止后可重新解码或分享；下次诊断录音会替换旧文件。")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.inputDescription).font(.caption)
                Text("已处理音频 \(model.receivedSeconds, specifier: "%.1f") 秒 · 同步脉冲 \(model.syncPulses)")
                    .font(.caption.monospacedDigit())
                if let url = model.diagnosticURL {
                    Button("重新解码诊断录音", systemImage: "waveform") { model.importFile(url) }
                        .disabled(model.busy)
                    ShareLink(item: url) {
                        Label("分享诊断 WAV", systemImage: "square.and.arrow.up")
                    }.disabled(model.busy)
                }
            }.padding(.top, 12)
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            Toggle(model.manualMode ? "手动 Robot 36" : "自动 Robot 36", isOn: $model.manualMode).disabled(model.busy)
            Text(model.manualMode
                 ? "手动寻找行同步；适用于 VIS 缺失，从下一条完整扫描行开始尝试恢复。"
                 : "自动识别 VIS 前导信号；请从音频开头播放。")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.usingMicrophone ? "麦克风输入电平" : "音频输入电平").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: model.level).accessibilityLabel("音频输入电平")
            }
            if model.busy {
                Button("停止接收", systemImage: "stop.fill") { model.stop() }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            }
            if !model.busy {
                Button("开始接收", systemImage: "mic.fill") { model.startMicrophone() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            if model.busy && !model.usingMicrophone {
                ProgressView("文件读取", value: model.inputProgress).font(.caption)
            }
            Button("导入 WAV 音频", systemImage: "waveform.badge.plus") { importing = true }
                .buttonStyle(.bordered).disabled(model.busy)
            HStack {
                Button("保存 PNG", systemImage: "square.and.arrow.down") { exporting = true }
                    .disabled(model.pngData == nil)
                Spacer()
                if let data = model.pngData {
                    ShareLink(item: PNGShare(data: data), preview: SharePreview("SSTV Robot 36", image: Image(systemName: "photo"))) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }.font(.subheadline)
        }
    }
}

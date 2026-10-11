# SSTV Decoder

**简体中文** | [English](README.en.md)

使用 Swift 6 和 SwiftUI 编写的 iPhone **Robot 36 SSTV（慢扫描电视）接收器**。支持麦克风实时接收和本地 WAV 导入，将音频转换为 320 × 240 彩色图像，并导出 PNG。音频与图像均在本机处理，无账号、服务器或第三方运行依赖。

> 当前为开发中的原型。文件解码与自动化实时重放已通过验证；实际扬声器、房间和麦克风环境下仍可能失步，不应视为已经完成真机可靠性验收。

![测试音频解码结果](Documentation/decoded-color-bars.png)

## 功能

- 自动识别 Robot 36 VIS 前导；支持无 VIS 时手动寻找行同步。
- 边接收边显示扫描行、图像预览和输入电平，无需等到停止后解析。
- 导入单声道或双声道 PCM / IEEE Float WAV。
- 保存和分享 PNG，查看完整图像。
- 麦克风失步或 VIS 校验失败后保留预览、继续监听，等待新的完整信号。
- 可选本地诊断录音、实际输入设备与采样率、已处理时长和同步脉冲统计。
- 支持主动停止、音频中断处理；进入后台停止接收。

## 环境要求

- macOS 与支持 Swift 6、iOS 17 SDK 的 Xcode（建议 Xcode 16 或更新版本）。
- iPhone：iOS 17 或更新版本；真机安装需要在 Xcode 中选择自己的开发团队。
- Swift Package 测试要求 macOS 14 或更新版本，使用系统 Accelerate、AVFoundation 等框架。
- Python 3 仅用于重新生成测试音频，不是 App 的运行依赖。

项目名和 Scheme 均为 `SSTVDemo`，App 显示名称为 `SSTV Decoder`。界面目前为中文；本仓库提供中英文使用说明。

## 安装并运行

1. 下载仓库 ZIP 并解压，或使用 Git 克隆仓库。
2. 双击 `SSTVDemo.xcodeproj`，选择 **SSTVDemo** Scheme。
3. 首次验证可选择 iPhone 模拟器，通过文件导入测试。
4. 真机测试时连接 iPhone，在 **Signing & Capabilities → Team** 选择自己的开发团队。如有签名冲突，将 Bundle Identifier 改为自己的唯一标识。
5. 选择真机，点击 **Run ▶︎** 或按 **⌘R**。修改代码后也要重新运行，手机上的 App 才会更新。

无需安装 CocoaPods 或额外 Swift Package 依赖。

## 第一次使用：先导入测试音频

1. 将 [robot36.wav](SSTVReceiverTests/Fixtures/robot36.wav) 保存到手机“文件”中。
2. 打开 App，保持 **自动 Robot 36**，点击 **导入 WAV 音频**。
3. 选择测试文件，等待扫描行达到 **240/240**。
4. 点击 **保存 PNG** 或 **分享**。

测试音频约 36.94 秒，48 kHz、16-bit、单声道，来源是项目自带的确定性生成器。原图见 [source.png](SSTVReceiverTests/Fixtures/source.png)。文件处理不限于播放速度，通常会比实际播放更快；导入不需要麦克风权限。

## 麦克风实时接收

1. 保持 App 在前台，选择 **自动 Robot 36**。
2. 点击 **开始接收**，首次使用时允许麦克风权限。
3. 等待“麦克风已就绪”的提示，再用另一台设备**从头播放完整音频**。
4. 正常情况下，播放期间就会逐行出现图像。输入电平变化只表示有声音，不代表已识别到 SSTV。
5. 达到 240 行后可保存图片；也可点击 **停止接收**结束。

### 自动 / 手动开关

| 开关 | 显示名称 | 用途 |
| --- | --- | --- |
| 关闭 | 自动 Robot 36 | 默认选项。检测完整 VIS 前导，适用于测试 WAV 和完整传输。 |
| 打开 | 手动 Robot 36 | 已确认音源是 Robot 36，但缺少 VIS 时使用。寻找相邻行同步；缺少的图像行不能恢复。 |

接收期间不能切换模式。失步后的自动恢复要求新的完整 VIS；对于没有 VIS 的音频，请停止后再以手动模式重新开始。

### 提示“扫描行同步丢失”时

当前帧已无法可靠继续。App 会保留已恢复的图像，继续监听；**从头重播完整音频**后开始一幅新图像。停止按钮仍然有效。队列过载、输入设备错误或录音写入错误仍可能终止接收。

## 诊断录音

1. 展开页面底部 **接收诊断**，开启 **保存诊断录音**（默认关闭）。
2. 开始接收后播放音频。即使失步，也先让本轮音频完整播完。
3. 点击停止，再选择 **重新解码诊断录音**或 **分享诊断 WAV**。

保存的是实际送入解码器的单声道 Float PCM，使用设备实际采样率，**最多 45 秒**。录音只暂存在本机，不自动上传；下次诊断录音会替换旧文件。它可能包含周围声音，分享前请自行确认内容。

## 支持范围与限制

- 仅支持 Robot 36，输出 320 × 240；不支持其他 SSTV 模式或发送功能。
- WAV：PCM 8/16/24/32-bit、IEEE Float 32/64-bit，单/双声道；拒绝压缩 WAV、损坏或截断文件。
- 接受 8–192 kHz 输入，主要验证 44.1/48 kHz；麦克风按硬件实际采样率处理。
- 不支持后台接收、自动存入相册或跨帧拼图。
- 噪声、回声、削波和信号衰落仍会影响颜色与同步。允许一次已锁定时钟下的同步缺失，不无限预测缺失行。
- 已提供的声学录音可完整解码，但不同真机环境的稳定性、电话中断和长时间资源使用仍需进一步验证。

## 开发与测试

在项目根目录运行核心测试：

```sh
swift test --scratch-path /tmp/SSTVReceiver-tests -c release
```

在 Xcode 中选择可用的 iPhone 模拟器，按 **⌘U** 运行 App 测试。也可先查看可用设备，再将其 ID 填入命令：

```sh
xcodebuild -showdestinations -project SSTVDemo.xcodeproj -scheme SSTVDemo
xcodebuild -project SSTVDemo.xcodeproj -scheme SSTVDemo \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -derivedDataPath /tmp/SSTVReceiver-build CODE_SIGNING_ALLOWED=NO test
```

重新生成合成测试资源（仅 Python 标准库）：

```sh
python3 scripts/generate_fixture.py
```

公开仓库包含合成 WAV 和图像，不包含私人麦克风录音。依赖 `robot36-microphone-prefix.wav` / `robot36-microphone-complete.wav` 的声学测试，在文件缺失时明确跳过；其他测试照常执行。已有合法本地测试录音时可放入 `SSTVReceiverTests/Fixtures/`，这些文件被 Git 忽略。

## 项目结构

```text
SSTVDemo/
  Audio/                 音频输入、会话生命周期、WAV 和诊断录音
  Core/DSP/              FIR 滤波、相位差解调、频率处理
  Core/Decoder/          VIS、行同步、Robot 36 与图像帧解码
  Features/Receiver/     SwiftUI 页面与接收状态管理
  Imaging/               RGB 图像与 PNG 导出
SSTVReceiverTests/       核心、文件、队列、图像测试与合成资源
SSTVReceiverAppTests/    iOS 接收状态、回调和实时重放测试
scripts/                测试信号生成器
Documentation/          示例图片
```

文件导入与麦克风使用同一套解码核心。音频回调只写入有界 PCM 队列，后台任务负责解码，MainActor 更新界面；不在音频回调里写磁盘或处理图像。

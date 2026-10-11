# SSTV Decoder

[简体中文](README.md) | **English**

A native iPhone **Robot 36 SSTV (Slow Scan Television) receiver** built with Swift 6 and SwiftUI. Decode microphone audio or local WAV files into 320 × 240 color images and export PNGs. All audio and image processing runs on-device, without accounts, servers, or third-party runtime dependencies.

> This is a development prototype. File decoding and automated real-time replay have been verified. Actual speaker, room, and microphone conditions can still cause synchronization loss; field reliability has not been fully validated.

![Decoded synthetic test signal](Documentation/decoded-color-bars.png)

## Features

- Automatic Robot 36 VIS detection and manual line synchronization for signals without VIS.
- Progressive image preview, scanline count, and input level during reception; stopping is not required to decode.
- Mono/stereo PCM and IEEE Float WAV import.
- PNG saving, system sharing, and full-image preview.
- Keeps the partial preview and continues listening after microphone synchronization or VIS parity failures, waiting for a new complete transmission.
- Optional local diagnostic recording, actual input device/sample rate, processed duration, and sync pulse count.
- Explicit stop and audio interruption handling; reception stops in the background.

## Requirements

- macOS and Xcode supporting Swift 6 and the iOS 17 SDK; Xcode 16 or newer is recommended.
- iPhone running iOS 17 or later. Select your own development team in Xcode for device installation.
- macOS 14 or later for Swift Package tests, which use Apple frameworks including Accelerate and AVFoundation.
- Python 3 only if regenerating the test audio; the app does not require Python.

The project and scheme are named `SSTVDemo`; the app display name is `SSTV Decoder`. The app UI is currently in Chinese. Both Chinese and English usage guides are provided here.

## Build and run

1. Download and extract the repository ZIP, or clone the repository with Git.
2. Open `SSTVDemo.xcodeproj` and select the **SSTVDemo** scheme.
3. For an initial check, choose an iPhone simulator and test WAV import.
4. For a physical device, connect your iPhone and select your team under **Signing & Capabilities → Team**. If signing conflicts occur, change the Bundle Identifier to your own unique identifier.
5. Select the device and click **Run ▶︎** or press **⌘R**. Run again after code changes to update the app on your phone.

No CocoaPods installation or additional Swift Package dependencies are needed.

## First test: import a WAV file

1. Save [robot36.wav](SSTVReceiverTests/Fixtures/robot36.wav) to the Files app on your phone.
2. Keep **自动 Robot 36** (Automatic Robot 36) selected and tap **导入 WAV 音频** (Import WAV).
3. Choose the test file and wait for **240/240** scanlines.
4. Tap **保存 PNG** (Save PNG) or **分享** (Share).

The deterministic synthetic fixture is approximately 36.94 seconds long: 48 kHz, 16-bit, mono. See [source.png](SSTVReceiverTests/Fixtures/source.png) for the source image. File processing is not limited to playback speed and normally completes faster than playback. Importing does not require microphone permission.

## Live microphone reception

1. Keep the app in the foreground and select **自动 Robot 36** (Automatic Robot 36).
2. Tap **开始接收** (Start receiving), allowing microphone access when prompted.
3. Wait for the microphone-ready message, then play the **entire audio from the beginning on another device**.
4. The image should appear progressively during playback. A moving input meter only confirms sound input, not SSTV detection.
5. Save the image when 240 lines are complete, or tap **停止接收** (Stop receiving) to end the session.

### Automatic / manual switch

| Switch | UI label | Purpose |
| --- | --- | --- |
| Off | 自动 Robot 36 | Default. Detects a complete VIS header; use for the included WAV and complete transmissions. |
| On | 手动 Robot 36 | Use only when the source is known to be Robot 36 but lacks VIS. Acquires adjacent line sync pulses; missing image lines cannot be recovered. |

The mode cannot be changed while receiving. Automatic recovery after a lost frame requires a new complete VIS header. For audio without VIS, stop and explicitly restart in manual mode.

### “扫描行同步丢失” (scanline synchronization lost)

The current frame cannot reliably continue. The app retains its partial preview and keeps listening. **Replay the entire audio from the beginning** to start a new image. You can still stop reception manually. Queue overload, input device errors, or recording write failures can still stop the session.

## Diagnostic recordings

1. Expand **接收诊断** (Reception diagnostics) and enable **保存诊断录音** (Save diagnostic recording), which is off by default.
2. Start receiving and play the audio. If synchronization is lost, let the current playback finish.
3. Stop reception, then select **重新解码诊断录音** (Decode recording again) or **分享诊断 WAV** (Share diagnostic WAV).

The recording contains the same mono Float PCM passed to the decoder at the actual hardware sample rate, limited to **45 seconds**. It stays in temporary local storage and is never uploaded automatically. The next diagnostic recording replaces the previous file. Recordings can contain ambient sound; review them before sharing.

## Supported inputs and limitations

- Robot 36 only, producing 320 × 240 images. Other SSTV modes and transmission are not supported.
- WAV: PCM 8/16/24/32-bit and IEEE Float 32/64-bit, mono or stereo. Compressed, malformed, and truncated WAV files are rejected.
- Accepted sample rates: 8–192 kHz; testing focuses on 44.1/48 kHz. Microphone processing uses the actual hardware sample rate.
- No background reception, automatic Photos saving, or stitching different frames together.
- Noise, echoes, clipping, and fading can affect colors and synchronization. Once locked, the decoder tolerates one missing sync pulse; it does not indefinitely predict missing lines.
- Supplied acoustic recordings have been decoded completely, but reliability across physical devices, phone-call interruptions, and long-running resource usage still needs further validation.

## Development and tests

Run core tests from the repository root:

```sh
swift test --scratch-path /tmp/SSTVReceiver-tests -c release
```

Select an available iPhone simulator in Xcode and press **⌘U** for app tests. Alternatively, list destinations and substitute your simulator ID:

```sh
xcodebuild -showdestinations -project SSTVDemo.xcodeproj -scheme SSTVDemo
xcodebuild -project SSTVDemo.xcodeproj -scheme SSTVDemo \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -derivedDataPath /tmp/SSTVReceiver-build CODE_SIGNING_ALLOWED=NO test
```

Regenerate synthetic fixtures using only the Python standard library:

```sh
python3 scripts/generate_fixture.py
```

The public repository includes synthetic audio and images, but excludes private microphone recordings. Acoustic tests requiring `robot36-microphone-prefix.wav` or `robot36-microphone-complete.wav` explicitly skip when those files are absent; other tests still run. If you have authorized local fixtures, place them in `SSTVReceiverTests/Fixtures/`. These recordings are ignored by Git.

## Project layout

```text
SSTVDemo/
  Audio/                 Audio input, session lifecycle, WAV and diagnostic recording
  Core/DSP/              FIR filtering, phase demodulation, frequency processing
  Core/Decoder/          VIS, line synchronization, Robot 36 frame decoding
  Features/Receiver/     SwiftUI screen and reception state management
  Imaging/               RGB rendering and PNG export
SSTVReceiverTests/       Core, file, queue, image tests and synthetic fixtures
SSTVReceiverAppTests/    iOS state, callback, and real-time replay tests
scripts/                Test signal generator
Documentation/          Example images
```

File import and microphone reception share the same decoder. The audio callback writes only to a bounded PCM queue; a background task decodes it and MainActor updates the UI. Disk writes and image processing do not run in the audio callback.

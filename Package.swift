// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SSTVReceiver",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "SSTVCore", targets: ["SSTVCore"])],
    targets: [
        .target(name: "SSTVCore", path: "SSTVDemo/Core"),
        .target(name: "SSTVAudio", dependencies: ["SSTVCore"], path: "SSTVDemo/Audio", exclude: ["AudioInputService.swift", "AudioEngineWorker.swift", "AudioLifecycleQueue.swift"]),
        .target(name: "SSTVImaging", dependencies: ["SSTVCore"], path: "SSTVDemo/Imaging"),
        .testTarget(name: "SSTVReceiverTests", dependencies: ["SSTVCore", "SSTVAudio", "SSTVImaging"], path: "SSTVReceiverTests", resources: [.copy("Fixtures")])
    ])

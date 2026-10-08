// swift-tools-version:5.9
// 核心逻辑（数据、统计、语音解析）单独成包，可在 Mac 上用 `swift test` 直接跑测试。
// App 本身请用 LiftNote.xcodeproj 打开。
import PackageDescription

let package = Package(
    name: "LiftNoteCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LiftNoteCore", targets: ["LiftNoteCore"]),
    ],
    targets: [
        .target(name: "LiftNoteCore", path: "LiftNote/Core"),
        .testTarget(name: "LiftNoteCoreTests", dependencies: ["LiftNoteCore"], path: "Tests/LiftNoteCoreTests"),
    ]
)

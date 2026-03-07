// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MicBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MicBar",
            path: "MicBar",
            exclude: ["Info.plist"],
            resources: [.process("Resources")]
        )
    ]
)

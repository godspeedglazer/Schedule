// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keen",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Keen",
            path: "Sources/Keen",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "KeenTests",
            dependencies: ["Keen"],
            path: "Tests/KeenTests"
        ),
    ]
)

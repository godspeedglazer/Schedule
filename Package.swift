// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sched",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sched",
            path: "Sources/Sched",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SchedTests",
            dependencies: ["Sched"],
            path: "Tests/SchedTests"
        ),
    ]
)

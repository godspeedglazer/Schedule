// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sched",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sched", targets: ["Sched"]),
    ],
    targets: [
        .executableTarget(
            name: "Sched",
            path: "Sources/Sched",
            resources: [.process("Resources")],
            swiftSettings: [
                // 1.0.3 is a stabilization release. Keep the Swift 6 toolchain,
                // but compile this target in Swift 5 language mode until the
                // AppKit/MainActor migration is completed and verified on macOS.
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "SchedTests",
            dependencies: ["Sched"],
            path: "Tests/SchedTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)

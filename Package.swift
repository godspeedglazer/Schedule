// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Sched",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "Sched", targets: ["Sched"])],
    targets: [.executableTarget(name: "Sched", path: "Sources/Sched")]
)

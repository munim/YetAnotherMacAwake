// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacAwake",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MacAwake", path: "Sources/MacAwake")
    ]
)

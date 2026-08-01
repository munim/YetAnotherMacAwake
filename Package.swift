// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YetAnotherMacAwake",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "YetAnotherMacAwake", path: "Sources/YetAnotherMacAwake")
    ]
)


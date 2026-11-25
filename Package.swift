// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZADFont",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ZADFont", path: "Sources/ZADFont")
    ]
)

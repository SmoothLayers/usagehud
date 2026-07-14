// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageHUD",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "UsageHUD", targets: ["UsageHUD"]),
    ],
    targets: [
        .executableTarget(name: "UsageHUD"),
        .testTarget(name: "UsageHUDTests", dependencies: ["UsageHUD"]),
    ],
    swiftLanguageModes: [.v5]
)

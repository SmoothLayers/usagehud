// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageHUD",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "UsageHUD", targets: ["UsageHUD"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),
    ],
    targets: [
        .executableTarget(
            name: "UsageHUD",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(name: "UsageHUDTests", dependencies: ["UsageHUD"]),
    ],
    swiftLanguageModes: [.v5]
)

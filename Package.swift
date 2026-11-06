// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LaunchpadOS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LaunchpadOS", targets: ["LaunchpadOS"])
    ],
    targets: [
        .executableTarget(name: "LaunchpadOS")
    ]
)

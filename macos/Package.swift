// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FullSail",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FullSail", targets: ["FullSail"])],
    targets: [
        .target(name: "SailCore"),
        .executableTarget(name: "FullSail", dependencies: ["SailCore"]),
        .testTarget(name: "SailCoreTests", dependencies: ["SailCore"])
    ]
)

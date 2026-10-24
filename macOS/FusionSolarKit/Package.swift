// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "FusionSolarKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FusionSolarKit", targets: ["FusionSolarKit"])
    ],
    targets: [
        .target(name: "FusionSolarKit"),
        .testTarget(name: "FusionSolarKitTests", dependencies: ["FusionSolarKit"])
    ]
)

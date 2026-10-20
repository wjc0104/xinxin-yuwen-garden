// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "GardenCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "GardenCore", targets: ["GardenCore"])],
    targets: [
        .target(name: "GardenCore"),
        .testTarget(name: "GardenCoreTests", dependencies: ["GardenCore"])
    ]
)

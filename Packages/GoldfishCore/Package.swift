// swift-tools-version: 5.9
import PackageDescription

// Pure Swift logic for Goldfish. Foundation only, so it can be tested with
// `swift test` on any Mac without a simulator or a phone.
let package = Package(
    name: "GoldfishCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "GoldfishCore", targets: ["GoldfishCore"]),
    ],
    targets: [
        .target(name: "GoldfishCore"),
        .testTarget(name: "GoldfishCoreTests", dependencies: ["GoldfishCore"]),
    ]
)

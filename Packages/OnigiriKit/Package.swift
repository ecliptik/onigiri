// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OnigiriKit",
    platforms: [
        .iOS("18.0"),
        .watchOS("10.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "OnigiriKit", targets: ["OnigiriKit"])
    ],
    targets: [
        .target(name: "OnigiriKit"),
        .testTarget(name: "OnigiriKitTests", dependencies: ["OnigiriKit"]),
    ]
)

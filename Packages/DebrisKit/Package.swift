// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DebrisKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DebrisKit", targets: ["DebrisKit"]),
        .executable(name: "debris", targets: ["debris"]),
    ],
    targets: [
        .target(name: "DebrisKit"),
        .executableTarget(name: "debris", dependencies: ["DebrisKit"]),
        .testTarget(name: "DebrisKitTests", dependencies: ["DebrisKit"]),
    ]
)

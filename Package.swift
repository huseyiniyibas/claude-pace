// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudePace",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudePace", targets: ["ClaudePace"]),
    ],
    targets: [
        .target(name: "ClaudePaceCore"),
        .executableTarget(name: "ClaudePace", dependencies: ["ClaudePaceCore"]),
        .testTarget(name: "ClaudePaceCoreTests", dependencies: ["ClaudePaceCore"]),
        .testTarget(name: "ClaudePaceTests", dependencies: ["ClaudePace", "ClaudePaceCore"]),
    ]
)

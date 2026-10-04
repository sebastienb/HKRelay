// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "HomeKitLink",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BridgeCore", targets: ["BridgeCore"]),
        .library(name: "BridgeServer", targets: ["BridgeServer"]),
        .executable(name: "homekitlink", targets: ["homekitlink"])
    ],
    targets: [
        .target(name: "BridgeCore"),
        .target(
            name: "BridgeServer",
            dependencies: ["BridgeCore"]
        ),
        .executableTarget(
            name: "homekitlink",
            dependencies: ["BridgeCore"]
        ),
        .testTarget(
            name: "BridgeCoreTests",
            dependencies: ["BridgeCore"]
        ),
        .testTarget(
            name: "BridgeServerTests",
            dependencies: ["BridgeServer", "BridgeCore"]
        )
    ]
)

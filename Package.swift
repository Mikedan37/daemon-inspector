// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "daemon-inspector",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // CLI executable
        .executable(
            name: "daemon-inspector",
            targets: ["InspectorCLI"]
        ),
        // Library products for embedding
        .library(
            name: "DaemonInspectorCore",
            targets: ["Model", "Collector", "Inspector"]
        ),
        .library(
            name: "DaemonInspectorStorage",
            targets: ["Storage"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "0.1.3")
    ],
    targets: [
        .target(
            name: "Model",
            dependencies: []
        ),
        .target(
            name: "Collector",
            dependencies: ["Model"]
        ),
        .target(
            name: "Storage",
            dependencies: ["Model", .product(name: "BlazeDBCore", package: "BlazeDB")]
        ),
        .target(
            name: "TerminalUI",
            dependencies: ["Model"]
        ),
        .target(
            name: "Inspector",
            dependencies: []
        ),
        .executableTarget(
            name: "InspectorCLI",
            dependencies: ["Model", "Collector", "Storage", "TerminalUI", "Inspector"]
        ),
        .testTarget(
            name: "DaemonInspectorTests",
            dependencies: ["Model", "Storage"]
        ),
        .testTarget(
            name: "InspectorTests",
            dependencies: ["Inspector"]
        )
    ]
)

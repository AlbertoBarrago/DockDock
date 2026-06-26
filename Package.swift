// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DockDock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DockDock",
            path: "Sources/DockDock"
        )
    ]
)

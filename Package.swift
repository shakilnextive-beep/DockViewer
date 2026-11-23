// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DockViewer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DockViewer", path: "Sources/DockViewer")
    ]
)

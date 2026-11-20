// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DockOrganizer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DockOrganizer", path: "Sources")
    ]
)

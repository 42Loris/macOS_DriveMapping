// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DriveMapping",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DriveMapping",
            path: "Sources/DriveMapping"
        )
    ]
)

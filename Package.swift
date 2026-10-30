// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AppleToDo",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AppleToDoCore"),
        .executableTarget(
            name: "AppleToDoCLI",
            dependencies: ["AppleToDoCore"]
        ),
        .testTarget(
            name: "AppleToDoCoreTests",
            dependencies: ["AppleToDoCore"]
        ),
    ]
)

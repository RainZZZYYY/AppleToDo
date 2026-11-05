// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AppleToDo",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 首个第三方依赖（ADR-0006：Core 零依赖，CLI 壳最小依赖）
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "AppleToDoCore"),
        .target(name: "AppleToDoLLM"),
        .executableTarget(
            name: "appletodo",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "AppleToDoCore",
            ]
        ),
        .executableTarget(
            name: "appletodo-bar",
            dependencies: ["AppleToDoCore"]
        ),
        .testTarget(
            name: "AppleToDoCoreTests",
            dependencies: ["AppleToDoCore"]
        ),
    ]
)

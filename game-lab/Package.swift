// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AibouGameLab",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CircuitCore", targets: ["CircuitCore"]),
        .executable(name: "GameLabCLI", targets: ["GameLabCLI"])
    ],
    targets: [
        .target(name: "CircuitCore", path: "Sources/Core"),
        .executableTarget(name: "GameLabCLI", dependencies: ["CircuitCore"], path: "Sources/GameLabCLI"),
        .testTarget(name: "CoreTests", dependencies: ["CircuitCore"], path: "Tests/CoreTests")
    ]
)

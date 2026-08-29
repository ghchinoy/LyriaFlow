// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LyriaFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LyriaFlowSpike", targets: ["LyriaFlowSpike"]),
        .executable(name: "LyriaFlow", targets: ["LyriaFlow"]),
        .library(name: "LyriaFlowKit", targets: ["LyriaFlowKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LyriaFlowKit",
            path: "Sources/LyriaFlowKit"
        ),
        .executableTarget(
            name: "LyriaFlowSpike",
            dependencies: ["LyriaFlowKit"],
            path: "Sources/LyriaFlowSpike"
        ),
        .executableTarget(
            name: "LyriaFlow",
            dependencies: ["LyriaFlowKit"],
            path: "Sources/LyriaFlow"
        ),
        .testTarget(
            name: "LyriaFlowTests",
            dependencies: ["LyriaFlowKit"],
            path: "Tests/LyriaFlowTests"
        )
    ]
)

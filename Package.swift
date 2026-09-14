// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlickyAshtray",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FlickyAshtray", targets: ["FlickyAshtray"])
    ],
    targets: [
        .executableTarget(
            name: "FlickyAshtray",
            path: "Sources/FlickyAshtray"
        ),
        .testTarget(
            name: "FlickyAshtrayTests",
            dependencies: ["FlickyAshtray"],
            path: "tests/FlickyAshtrayTests"
        )
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalmBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CalmBar", targets: ["CalmBar"]),
        .executable(name: "CalmBarHelper", targets: ["CalmBarHelper"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CalmBarKit",
            dependencies: [],
            path: "Sources/CalmBarKit"
        ),
        .target(
            name: "CommandPaletteKit",
            dependencies: [],
            path: "Sources/CommandPaletteKit"
        ),
        .executableTarget(
            name: "CalmBar",
            dependencies: ["CalmBarKit", "CommandPaletteKit"],
            path: "Sources/CalmBar"
        ),
        .executableTarget(
            name: "CalmBarHelper",
            dependencies: ["CalmBarKit"],
            path: "Sources/CalmBarHelper"
        ),
        .testTarget(
            name: "CommandPaletteKitTests",
            dependencies: ["CommandPaletteKit"],
            path: "Tests/CommandPaletteKitTests"
        ),
        .testTarget(
            name: "CalmBarTests",
            dependencies: ["CalmBarKit", "CalmBar", "CommandPaletteKit"],
            path: "Tests/CalmBarTests"
        )
    ]
)

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
    dependencies: [
        // 自动更新：ad-hoc 签名无法走 Apple 官方更新通道，使用 Sparkle EdDSA 更新。
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
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
            dependencies: [
                "CalmBarKit",
                "CommandPaletteKit",
                .product(name: "Sparkle", package: "Sparkle")
            ],
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

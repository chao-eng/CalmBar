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
        .executableTarget(
            name: "CalmBar",
            dependencies: ["CalmBarKit"],
            path: "Sources/CalmBar"
        ),
        .executableTarget(
            name: "CalmBarHelper",
            dependencies: ["CalmBarKit"],
            path: "Sources/CalmBarHelper"
        ),
        .testTarget(
            name: "CalmBarTests",
            dependencies: ["CalmBarKit", "CalmBar"],
            path: "Tests/CalmBarTests"
        )
    ]
)

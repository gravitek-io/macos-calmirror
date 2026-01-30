// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CalmMirror",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "CalmMirrorCore", targets: ["CalmMirrorCore"]),
        .executable(name: "CalmMirrorApp", targets: ["CalmMirrorApp"]),
        .executable(name: "calmirror", targets: ["calmirror"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        // Shared core library: models, engine, storage, calendar access
        .target(
            name: "CalmMirrorCore",
            path: "Sources/CalmMirrorCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // SwiftUI windowed application for rule configuration and log viewing
        .executableTarget(
            name: "CalmMirrorApp",
            dependencies: ["CalmMirrorCore"],
            path: "Sources/CalmMirrorApp",
            exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // CLI executable invoked by launchd and interactive use
        .executableTarget(
            name: "calmirror",
            dependencies: [
                "CalmMirrorCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/calmirror",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Unit tests for the core library
        .testTarget(
            name: "CalmMirrorCoreTests",
            dependencies: ["CalmMirrorCore"],
            path: "Tests/CalmMirrorCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

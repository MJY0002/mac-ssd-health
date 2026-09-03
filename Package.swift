// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SSDHealth",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SSDHealthCore",
            targets: ["SSDHealthCore"]
        ),
        .library(
            name: "SSDHealthService",
            targets: ["SSDHealthService"]
        ),
        .library(
            name: "SSDHealthUI",
            targets: ["SSDHealthUI"]
        ),
        .executable(
            name: "SSDHealthApp",
            targets: ["SSDHealthApp"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SSDHealthCore",
            dependencies: [],
            path: "Sources/SSDHealthCore"
        ),
        .target(
            name: "SSDHealthService",
            dependencies: ["SSDHealthCore"],
            path: "Sources/SSDHealthService"
        ),
        .target(
            name: "SSDHealthUI",
            dependencies: ["SSDHealthCore", "SSDHealthService"],
            path: "Sources/SSDHealthUI"
        ),
        .executableTarget(
            name: "SSDHealthApp",
            dependencies: ["SSDHealthCore", "SSDHealthService", "SSDHealthUI"],
            path: "Sources/SSDHealthApp",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "SSDHealthCoreTests",
            dependencies: ["SSDHealthCore"],
            path: "Tests/SSDHealthCoreTests"
        ),
        .testTarget(
            name: "SSDHealthServiceTests",
            dependencies: ["SSDHealthService", "SSDHealthCore"],
            path: "Tests/SSDHealthServiceTests"
        ),
        .testTarget(
            name: "SSDHealthE2ETests",
            dependencies: ["SSDHealthCore", "SSDHealthService"],
            path: "Tests/SSDHealthE2ETests"
        ),
        .testTarget(
            name: "SSDHealthUITests",
            dependencies: ["SSDHealthUI", "SSDHealthCore", "SSDHealthService"],
            path: "Tests/SSDHealthUITests"
        )
    ]
)

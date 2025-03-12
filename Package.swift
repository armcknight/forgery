// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "forgery",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "forgery", targets: ["forgery"]),
        .library(name: "forgery-lib", targets: ["forgery-lib"])
    ],
    dependencies: [
        .package(name: "OctoKit", path: "octokit"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
        .package(name: "git-kit", path: "git-kit"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/binarybirds/shell-kit", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "forgery",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "forgery-lib",
            ]
        ),
        .target(name: "forgery-lib", dependencies:[
            .product(name: "OctoKit", package: "OctoKit"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "GitKit", package: "git-kit"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "ShellKit", package: "shell-kit"),
        ]
        )
    ]
)

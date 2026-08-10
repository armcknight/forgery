// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "forgery",
    platforms: [
        // swift-subprocess (via git-kit 2.0) declares a floor of macOS 13.
        .macOS(.v13),
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
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "0.4.0"),
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
            .product(name: "Subprocess", package: "swift-subprocess"),
        ]
        ),
        .testTarget(
            name: "forgery-libTests",
            dependencies: [
                "forgery-lib",
                .product(name: "GitKit", package: "git-kit"),
            ]
        ),
        .testTarget(
            name: "forgeryTests",
            dependencies: [
                "forgery-lib",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        )
    ]
)

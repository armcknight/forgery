// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "forgery",
    products: [
        .executable(
            name: "forgery",
            targets: ["forgery"]),
    ],
    dependencies: [
        .package(name: "OctoKit", path: "octokit"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
        .package(name: "git-kit", path: "git-kit"),
    ],
    targets: [
        .executableTarget(
            name: "forgery",
            dependencies: [
                .product(name: "OctoKit", package: "OctoKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "GitKit", package: "git-kit"),
            ]),
        .testTarget(
            name: "forgeryTests",
            dependencies: ["forgery"]),
    ]
)
// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "update-appcast",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/loopwerk/Parsley", from: "0.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "update-appcast", dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Parsley", package: "Parsley"),
            ]
        ),
    ]
)

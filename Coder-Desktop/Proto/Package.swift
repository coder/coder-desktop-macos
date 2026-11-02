// swift-tools-version: 6.0

// The protocol definitions used by Coder Desktop. The Swift code for each
// target is generated at build time from its .proto files, as configured by its
// grpc-swift-proto-generator-config.json.
//
// Coder Desktop pins the exact dependency versions in project.yml.

import PackageDescription

let generator = Target.PluginUsage.plugin(name: "GRPCProtobufGenerator", package: "grpc-swift-protobuf")

let package = Package(
    name: "Proto",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VPNProto", targets: ["VPNProto"]),
        .library(name: "MutagenProto", targets: ["MutagenProto"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.39.0"),
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.4"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.5.0"),
    ],
    targets: [
        // Messages for the tunnel protocol shared with coder/coder.
        .target(
            name: "VPNProto",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            plugins: [generator]
        ),
        // Messages and gRPC clients for the Mutagen daemon, vendored by
        // scripts/mutagen-proto.sh.
        .target(
            name: "MutagenProto",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
            ],
            plugins: [generator]
        ),
    ]
)

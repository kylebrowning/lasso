// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "grantiva",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "grantiva", targets: ["grantiva"]),
        .library(name: "GrantivaCore", targets: ["GrantivaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.3.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.11.0"),
    ],
    targets: [
        .executableTarget(name: "grantiva", dependencies: ["GrantivaCLI"]),
        .target(
            name: "GrantivaCLI",
            dependencies: [
                "GrantivaCore", "GrantivaAPI", "GrantivaMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "GrantivaMCP",
            dependencies: [
                "GrantivaCore",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .target(
            name: "GrantivaCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Yams", package: "Yams"),
            ],
            resources: [
                .copy("Resources/grantiva-runner-arm64.tar.gz"),
                .copy("Resources/grantiva-runner-amd64.tar.gz"),
            ]
        ),
        .target(name: "GrantivaAPI", dependencies: ["GrantivaCore"]),
        .testTarget(name: "GrantivaCoreTests", dependencies: [
            "GrantivaCore",
            .product(name: "Yams", package: "Yams"),
        ]),
        .testTarget(name: "GrantivaAPITests", dependencies: ["GrantivaAPI"]),
    ]
)

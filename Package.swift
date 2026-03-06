// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "lasso",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "lasso", targets: ["lasso"]),
        .library(name: "LassoCore", targets: ["LassoCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.3.0"),
    ],
    targets: [
        .executableTarget(name: "lasso", dependencies: ["LassoCLI"]),
        .target(
            name: "LassoCLI",
            dependencies: [
                "LassoCore", "LassoRange",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "LassoCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .target(name: "LassoRange", dependencies: ["LassoCore"]),
        .testTarget(name: "LassoCoreTests", dependencies: [
            "LassoCore",
            .product(name: "Yams", package: "Yams"),
        ]),
        .testTarget(name: "LassoRangeTests", dependencies: ["LassoRange"]),
    ]
)

// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BuieCore",
    products: [
        .library(
            name: "BuieCore",
            targets: ["BuieCore"]
        ),
    ],
    targets: [
        .target(name: "BuieCore"),
        .testTarget(name: "BuieCoreTests", dependencies: ["BuieCore"]),
    ]
)

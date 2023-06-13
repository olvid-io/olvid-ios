// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "GMP",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "GMP",
            targets: ["GMP"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "GMP",
            path: "GMP.xcframework"
        )
    ]
)

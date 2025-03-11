// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "GMP",
    platforms: [
        .iOS(.v15),
        .macOS(.v12), // No clear, we compile gmp with macabi 15.5
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

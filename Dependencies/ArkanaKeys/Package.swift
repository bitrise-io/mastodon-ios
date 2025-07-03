// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "ArkanaKeys",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "ArkanaKeys",
            targets: ["ArkanaKeys"]
        ),
    ],
    targets: [
        .target(
            name: "ArkanaKeys",
            path: "Sources"
        ),
    ]
)
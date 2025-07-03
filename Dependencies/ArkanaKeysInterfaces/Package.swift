// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "ArkanaKeysInterfaces",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "ArkanaKeysInterfaces",
            targets: ["ArkanaKeysInterfaces"]
        ),
    ],
    targets: [
        .target(
            name: "ArkanaKeysInterfaces",
            path: "Sources"
        ),
    ]
)
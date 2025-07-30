// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Mastodon-iOS",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
    ],
    dependencies: [
        .package(name: "MastodonSDK", path: "MastodonSDK"),
        .package(
            url: "https://github.com/Bearologics/LightChart.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/jdg/MBProgressHUD.git",
            from: "1.2.0"
        ),
        .package(
            url: "https://github.com/tid-kijyun/Kanna.git",
            from: "5.2.7"
        ),
        .package(
            url: "https://github.com/mastodon/MastoParse.git",
            branch: "main"
        ),
        .package(url: "https://github.com/mergesort/Bodega.git", .upToNextMajor(from: "2.0.0")),
    ]
)

// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PlayKit",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
        .tvOS(.v14),
        .watchOS(.v6)
    ],
    products: [
        .library(name: "PlayKit", targets: ["PlayKit"]),
    ],
    targets: [
        .target(
            name: "PlayKit"
        ),
        .testTarget(
            name: "PlayKitTests",
            dependencies: ["PlayKit"]
        ),
    ]
)

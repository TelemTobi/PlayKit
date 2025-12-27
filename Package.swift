// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PlayKit",
    platforms: [
        .iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v9)
    ],
    products: [
        .library(name: "PlayKit", targets: ["PlayKit"])
    ],
    targets: [
        .target(
            name: "PlayKit"
        ),
        .testTarget(
            name: "PlayKitTests",
            dependencies: ["PlayKit"]
        )
    ]
)

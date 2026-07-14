// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AURORAKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AURORAKit", targets: ["AURORAKit"])
    ],
    targets: [
        .target(name: "AURORAKit"),
        .testTarget(name: "AURORAKitTests", dependencies: ["AURORAKit"])
    ]
)

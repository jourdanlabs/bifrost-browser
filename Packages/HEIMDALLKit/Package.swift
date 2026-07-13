// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HEIMDALLKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(name: "HEIMDALLKit", targets: ["HEIMDALLKit"])
    ],
    dependencies: [
        .package(path: "../AURORAKit")
    ],
    targets: [
        .target(name: "HEIMDALLKit", dependencies: ["AURORAKit"]),
        .testTarget(name: "HEIMDALLKitTests", dependencies: ["HEIMDALLKit"])
    ]
)

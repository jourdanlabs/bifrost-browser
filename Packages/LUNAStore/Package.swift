// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LUNAStore",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LUNAStore", targets: ["LUNAStore"])
    ],
    dependencies: [
        .package(path: "../HEIMDALLKit")
    ],
    targets: [
        .target(name: "LUNAStore", dependencies: ["HEIMDALLKit"]),
        .testTarget(name: "LUNAStoreTests", dependencies: ["LUNAStore"])
    ]
)

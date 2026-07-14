// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BIFROSTKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(name: "BIFROSTKit", targets: ["BIFROSTKit"])
    ],
    dependencies: [
        .package(path: "../HEIMDALLKit"),
        .package(path: "../LUNAStore")
    ],
    targets: [
        .target(name: "BIFROSTKit", dependencies: ["HEIMDALLKit", "LUNAStore"]),
        .testTarget(name: "BIFROSTKitTests", dependencies: ["BIFROSTKit"])
    ]
)

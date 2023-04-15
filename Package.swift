// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "NetDiag",
    platforms: [
        .macOS(.v12),
        .iOS(.v10)
    ],
    products: [
        .library(name: "NetDiag", targets: ["NetDiag"])
    ],
    targets: [
        .target(name: "NetDiag")
    ]
)

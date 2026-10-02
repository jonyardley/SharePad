// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SharePadWire",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SharePadWire", targets: ["SharePadWire"]),
    ],
    targets: [
        .target(name: "SharePadWire"),
        .testTarget(name: "SharePadWireTests", dependencies: ["SharePadWire"]),
    ]
)

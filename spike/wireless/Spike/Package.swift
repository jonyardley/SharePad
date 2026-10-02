// swift-tools-version:5.9
import PackageDescription

// Throwaway spike (specs/wireless.md), now built on the shipping wire package so
// it re-measures the product settings (specs/wireless-product.md §8). Swift 5
// language mode on purpose: this is measurement code, not a shipping target.
let package = Package(
    name: "Spike",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "spike-receiver", targets: ["SpikeReceiver"]),
        .executable(name: "spike-fakesender", targets: ["SpikeFakeSender"]),
    ],
    dependencies: [
        .package(path: "../../../Packages/SharePadWire"),
    ],
    targets: [
        .executableTarget(name: "SpikeReceiver", dependencies: ["SharePadWire"]),
        .executableTarget(name: "SpikeFakeSender", dependencies: ["SharePadWire"]),
    ]
)

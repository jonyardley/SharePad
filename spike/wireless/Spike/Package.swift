// swift-tools-version:5.9
import PackageDescription

// Throwaway spike (specs/wireless.md). Swift 5 language mode on purpose: this is
// measurement code with a two-day life, not a shipping target.
let package = Package(
    name: "Spike",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SpikeWire", targets: ["SpikeWire"]),
        .executable(name: "spike-receiver", targets: ["SpikeReceiver"]),
        .executable(name: "spike-fakesender", targets: ["SpikeFakeSender"]),
    ],
    targets: [
        .target(name: "SpikeWire"),
        .executableTarget(name: "SpikeReceiver", dependencies: ["SpikeWire"]),
        .executableTarget(name: "SpikeFakeSender", dependencies: ["SpikeWire"]),
    ]
)

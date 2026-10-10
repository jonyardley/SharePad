// swift-tools-version:5.9
import PackageDescription

// Mac side of the stroke spike (#217): renders an iPad session's drawings with
// PencilKit on macOS and diffs them against the iPad's own snapshots.
let package = Package(
    name: "Render",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "stroke-render", targets: ["StrokeRender"]),
    ],
    targets: [
        // PencilKit on macOS traps in CFEqual on a background queue when the
        // process has no bundle identifier, so the tool carries an Info.plist.
        .executableTarget(
            name: "StrokeRender",
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist", "-Xlinker", "Info.plist",
            ])]
        ),
    ]
)

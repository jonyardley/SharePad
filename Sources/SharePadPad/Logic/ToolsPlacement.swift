import CoreGraphics

struct ToolsPlacement: Equatable {
    let obstructions: [CGRect]
    let isUnknown: Bool

    static func resolve(
        pickerVisible: Bool,
        reported: CGRect,
        measured: [CGRect],
        window: CGRect
    ) -> ToolsPlacement {
        if !reported.isNull, !reported.isEmpty {
            return ToolsPlacement(obstructions: [reported], isUnknown: false)
        }
        guard pickerVisible else { return ToolsPlacement(obstructions: [], isUnknown: false) }
        let onScreen = measured.filter { !$0.isEmpty && $0.intersects(window) }
        return ToolsPlacement(obstructions: onScreen, isUnknown: onScreen.isEmpty)
    }
}

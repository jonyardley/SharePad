import UIKit

// PKToolPicker.frameObscured(in:) is CGRectNull whenever the picker is movable
// (PKToolPicker.h), and the iPadOS 26 palette always is. The palette is drawn in
// process, as PKDrawingPaletteView inside UITextEffectsWindow (logged on iPadOS 27,
// 2026-10-02), so its frame is read from there. If the class is ever renamed, nothing
// is found and ToolsPlacement holds frames instead of leaking the palette.
@MainActor
enum PaletteLocator {
    static let paletteClassPrefix = "PKDrawingPaletteView"

    static func paletteFrames(over window: UIWindow) -> [CGRect] {
        guard let scene = window.windowScene else { return [] }
        return scene.windows
            .filter { $0 !== window && !$0.isHidden }
            .flatMap { frames(in: $0, relativeTo: window) }
    }

    private static func frames(in view: UIView, relativeTo window: UIWindow) -> [CGRect] {
        guard !view.isHidden, view.alpha > 0.01 else { return [] }
        if String(describing: type(of: view)).hasPrefix(paletteClassPrefix) {
            return [view.convert(view.bounds, to: window)]
        }
        return view.subviews.flatMap { frames(in: $0, relativeTo: window) }
    }
}

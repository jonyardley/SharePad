import UIKit

// frameObscured(in:) is null for a movable picker (PKToolPicker.h); see wireless-product.md.
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

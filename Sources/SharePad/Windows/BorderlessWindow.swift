import AppKit

/// Override canBecomeKey: borderless refuses it, so can't move or type (specs/clean-window.md).
final class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

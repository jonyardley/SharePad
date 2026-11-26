import AppKit

/// A borderless window returns false for canBecomeKey by default, which would make
/// it unmovable and non-interactive, so override so it behaves like a normal window.
final class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

import Carbon.HIToolbox

/// A system-wide hotkey via Carbon's `RegisterEventHotKey`: fires even when another
/// app is frontmost (the in-call case). Unlike an `NSEvent` global monitor it needs
/// no Accessibility (TCC) grant and no entitlement, and works for an `LSUIElement`
/// accessory app. Keep the instance alive — `deinit` unregisters.
/// @unchecked Sendable: the Carbon refs are written only in init/deinit and the
/// hotkey is recovered across the C trampoline by pointer, not Sendable checking.
final class GlobalHotkey: @unchecked Sendable {
    /// The fixed window-toggle binding (⌃⌥⌘H). Key code, modifier mask, and display
    /// string live together so the popover hint can't drift from what's registered.
    enum WindowToggle {
        static let keyCode = UInt32(kVK_ANSI_H)
        static let modifiers = UInt32(controlKey | optionKey | cmdKey)
        static let display = "⌃⌥⌘H"
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor @Sendable () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // C trampoline can't capture context — recover the instance from userData.
        // Carbon dispatches on the main thread, so the MainActor hop is safe.
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotkey.action() }
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &handlerRef
        ) == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5348_5044) /* 'SHPD' */, id: 1)
        guard RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        ) == noErr else {
            RemoveEventHandler(handlerRef)
            handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

import Carbon.HIToolbox

/// A system-wide hotkey via Carbon's `RegisterEventHotKey`: fires even when another
/// app is frontmost (the in-call case). Unlike an `NSEvent` global monitor it needs
/// no Accessibility (TCC) grant and no entitlement, and works for an `LSUIElement`
/// accessory app. Keep the instance alive — `deinit` unregisters.
/// @unchecked Sendable: the Carbon refs are written only in init/deinit and the
/// hotkey is recovered across the C trampoline by pointer, not Sendable checking.
final class GlobalHotkey: @unchecked Sendable {
    /// The fixed window-toggle binding (⌃⌥⌘H). id, key code, modifier mask, and
    /// display string live together so the popover hint can't drift from what's
    /// registered. Each binding needs a distinct `id` (see `matches`).
    enum WindowToggle {
        static let id: UInt32 = 1
        static let keyCode = UInt32(kVK_ANSI_H)
        static let modifiers = UInt32(controlKey | optionKey | cmdKey)
        static let display = "⌃⌥⌘H"
    }

    private static let signature = OSType(0x5348_5044) // 'SHPD'

    private let hotKeyID: EventHotKeyID
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor @Sendable () -> Void

    init?(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.action = action
        hotKeyID = EventHotKeyID(signature: Self.signature, id: id)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // C trampoline can't capture context — recover the instance from userData.
        // Carbon dispatches on the main thread, so the MainActor hop is safe.
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            // The handler fires for every hot-key press app-wide; let presses for
            // other ids fall through to their own handler instead of swallowing them.
            guard hotkey.matches(event) else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { hotkey.action() }
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &handlerRef
        ) == noErr else { return nil }

        guard RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        ) == noErr else {
            RemoveEventHandler(handlerRef)
            handlerRef = nil
            return nil
        }
    }

    private func matches(_ event: EventRef?) -> Bool {
        guard let event else { return false }
        var eventID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventID
        )
        return status == noErr
            && eventID.signature == hotKeyID.signature
            && eventID.id == hotKeyID.id
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

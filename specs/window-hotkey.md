# Window toggle hotkey

> Status: implemented. Tier 3 (net-new capability touching the window/share model).

## Problem

The only way to show/hide the share window is the popover's *Show/Hide window*
button — which means clicking the menu-bar icon mid-call. During a call your
focus is on the meeting app, not SharePad, so a button is the wrong affordance:
you want to hide (or re-show) the window without leaving the call.

## Approach

Two bindings, both driving the existing `AppModel.toggleWindow()` — no new window
logic, just new entry points.

1. **Global hotkey — `⌃⌥⌘H`.** Fires system-wide, even while the meeting app is
   frontmost. This is the one that matters in-call.
2. **App-focused — `⌘H`.** A SwiftUI `.keyboardShortcut("h")` on the popover's
   Show/Hide button. Works only when the popover is key, as a convenience when
   you're already in SharePad.

Both **toggle** (show ↔ hide), mirroring the button. `toggleWindow()` already
no-ops the "show" path when no iPad is connected, so the hotkey is safe to fire
anytime.

## Key decisions

- **Carbon `RegisterEventHotKey`, not an `NSEvent` global monitor.** A global
  monitor for key events requires Accessibility (TCC) permission and would add a
  second permission prompt — exactly what DESIGN.md §6.5 works to avoid for the
  mic. `RegisterEventHotKey` needs **no** entitlement and **no** Accessibility
  grant, and works fine for an `LSUIElement` accessory app. Carbon is first-party
  (no new dependency, per the no-third-party rule).
- **Fixed combo, not user-configurable (v1).** A rebind UI + a `MASShortcut`-style
  recorder is scope we don't need yet. `⌃⌥⌘H`: `H` = hide, and the three modifiers
  make a system/app collision unlikely (plain `⌘H` is "hide app", so it's kept for
  the app-focused binding only).
- **One source of truth for the combo.** `GlobalHotkey.WindowToggle` holds the
  key code, modifier mask, *and* the `⌃⌥⌘H` display string, so the popover hint
  can't drift from what's actually registered.
- **Registration failure is non-fatal.** If another app already owns `⌃⌥⌘H`,
  `RegisterEventHotKey` fails and the initializer returns `nil`; the app runs
  without the global hotkey (the popover button and `⌘H` still work). Unlike a
  capture error (DESIGN.md non-negotiable 6) this isn't a dead state, so it gets
  no error UI — but the popover hint is gated on `AppModel.isWindowHotkeyActive`
  so we never advertise a shortcut that didn't register.

## Testing

Carbon registration can't be meaningfully unit-tested without a run loop, same
bucket as the AVFoundation capture path — **manual verify**:

- With an iPad connected and the window shown, press `⌃⌥⌘H` while a meeting app is
  frontmost → window hides. Press again → it re-shows. (in-call case)
- Open the popover, press `⌘H` → window toggles.
- Fire `⌃⌥⌘H` with no iPad connected → nothing happens (no crash, no stray window).

## Open questions

- User-configurable rebinding — out of scope for v1.

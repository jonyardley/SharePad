# Window toggle hotkey

> Status: implemented. Tier 3 (net-new capability touching the window/share model).

## Problem

The only way to show/hide the share window is the popover's *Show/Hide window*
button — which means clicking the menu-bar icon mid-call. During a call your
focus is on the meeting app, not SharePad, so a button is the wrong affordance:
you want to hide (or re-show) the window without leaving the call.

## Approach

A single **global hotkey — `⌃⌥⌘H`** — driving the existing
`AppModel.toggleWindow()`; no new window logic, just a new entry point. It fires
system-wide, even while the meeting app is frontmost — the case that matters
in-call. It **toggles** (show ↔ hide), mirroring the popover button.
`toggleWindow()` already no-ops the "show" path when no iPad is connected, so the
hotkey is safe to fire anytime.

> **Dropped — app-focused `⌘H`.** An earlier cut added a SwiftUI
> `.keyboardShortcut("h")` on the popover button as a second, app-focused binding.
> Removed: `⌘H` is macOS's reserved *Hide application* shortcut, so the view-level
> binding loses to the system command (and an `LSUIElement` app has no app menu to
> own it) — it didn't reliably fire. It was also redundant: it only worked with the
> popover already open, where clicking the button is just as easy. The global
> hotkey covers the real need.

## Key decisions

- **Carbon `RegisterEventHotKey`, not an `NSEvent` global monitor.** A global
  monitor for key events requires Accessibility (TCC) permission and would add a
  second permission prompt — exactly what DESIGN.md §6.5 works to avoid for the
  mic. `RegisterEventHotKey` needs **no** entitlement and **no** Accessibility
  grant, and works fine for an `LSUIElement` accessory app. Carbon is first-party
  (no new dependency, per the no-third-party rule).
- **Fixed combo, not user-configurable (v1).** A rebind UI + a `MASShortcut`-style
  recorder is scope we don't need yet. `⌃⌥⌘H`: `H` = hide, and the three modifiers
  make a system/app collision unlikely (plain `⌘H` is macOS's reserved "hide app").
- **One source of truth for the combo.** `GlobalHotkey.WindowToggle` holds the
  key code, modifier mask, *and* the `⌃⌥⌘H` display string, so the popover hint
  can't drift from what's actually registered.
- **Per-id callback filtering.** A Carbon event handler fires for *every*
  hot-key press app-wide, not just its own combo. So `GlobalHotkey` tags each
  binding with a distinct `EventHotKeyID` and the callback matches the event's id
  to its own — otherwise a second binding would cross-fire (every instance's
  action running on any combo). Non-matching presses return `eventNotHandledErr`
  so the owning handler still receives them.
- **Registration failure is non-fatal.** If another app already owns `⌃⌥⌘H`,
  `RegisterEventHotKey` fails and the initializer returns `nil`; the app runs
  without the global hotkey (the popover button still works). Unlike a
  capture error (DESIGN.md non-negotiable 6) this isn't a dead state, so it gets
  no error UI — but the popover hint is gated on `AppModel.isWindowHotkeyActive`
  so we never advertise a shortcut that didn't register.

## Testing

Carbon registration can't be meaningfully unit-tested without a run loop, same
bucket as the AVFoundation capture path — **manual verify**:

- With an iPad connected and the window shown, press `⌃⌥⌘H` while a meeting app is
  frontmost → window hides. Press again → it re-shows. (in-call case)
- Fire `⌃⌥⌘H` with no iPad connected → nothing happens (no crash, no stray window).

## Open questions

- User-configurable rebinding — out of scope for v1.

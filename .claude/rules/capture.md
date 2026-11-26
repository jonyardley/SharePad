---
paths:
  - "Sources/SharePad/Capture/**"
  - "Sources/SharePad/Windows/**"
  - "Sources/SharePad/UI/**"
  - "Sources/SharePad/State/AppState.swift"
  - "Sources/SharePad/AppModel.swift"
  - "Sources/SharePad/App.swift"
  - "Sources/SharePad/Updater/**"
  - "Sources/SharePad/Support/Permissions.swift"
  - "Sources/SharePad/Support/GlobalHotkey.swift"
  - "Tests/SharePadTests/AppModelConnectTests.swift"
  - "Tests/SharePadTests/WindowSharingTests.swift"
  - "Tests/SharePadTests/ShareWindowLayerSwapTests.swift"
---

# Capture and the share window

These are the traps in capture and the share window, mostly verified against
Apple docs and forums (`DESIGN.md` §6). The three that must never be missed
(the CMIO opt-in, video-only input, no sandbox) are in `CLAUDE.md`.

- **The iPad is a `.muxed` device, not `.video`.** Discover with `mediaType: .muxed`
  (and `deviceType: .external`, macOS 14+; was `.externalUnknown`). A `.video`
  discovery won't find it.
- **Devices appear asynchronously** after the opt-in. KVO the DiscoverySession's
  `devices`: reading it once at launch races and finds nothing. This same KVO
  drives the automatic connect/disconnect.
- **First launch settles late.** Camera permission + the iPad "Trust" handshake
  finish *after* the iPad shows up to discovery, so the very first start can stall,
  and the device readying up afterward is a *property* change, not a `devices`-array
  change, so KVO won't re-fire. `AppModel` runs a bounded auto-retry over a few
  seconds so it self-heals (no unplug/replug). Don't "fix" this by latching `failed`
  on the first stalled start. (`specs/first-connect-retry.md`)
- **Normal window + browser meeting apps.** The chosen "normal window" (not pinned)
  shares fine in Zoom desktop even when occluded, but browser Meet/Teams only
  transmit a *visible* window: a buried window shares blank. The popover's
  *Keep window on top* toggle (gear menu) is the escape hatch. Remember this when "the share is
  black" gets reported.
- **The popover thumbnail renders off the data output, not a second preview layer**
  (#10). The window owns the one `AVCaptureVideoPreviewLayer`; the popover gets a
  fan-out of the existing `AVCaptureVideoDataOutput` into an
  `AVSampleBufferDisplayLayer`, gated to popover-open and throttled to ~15 fps. The
  "two preview layers on one session" question was sidestepped, not tested.
- **Locked iPad shows black**; sleep/wake can interrupt the session: restart on
  `runtimeErrorNotification` / interruption end. `CaptureController.resume()` only
  stops and starts the run loop: a full teardown re-adds the preview-layer
  connection, which leaves the layer frozen on its last frame.
- **Rotation resizes the share window but never persists its frame.** Saving the
  origin there would discard the user's placement on every rotation; only their
  own move or resize persists. `updateSize` refreshes `appliedFrame` so the move
  observer doesn't read the resize as a user move.
- **Licence entry is a real window, not a popover sheet.** A `MenuBarExtra`
  (`.window`) popover dismisses when focus leaves it, so a `.sheet` from it can't
  hold keyboard focus and the form vanishes. `LicenseWindow` is a focusable window,
  like the About panel.
- **Hosted unit tests skip startup.** `applicationDidFinishLaunching` returns early
  when `XCTestConfigurationFilePath` is set, so `just test` never triggers the CMIO
  opt-in or a camera prompt. Checking the env var keeps test-awareness out of the
  shipping binary's class lookups.
- **Only the feed window may be shared.** `WindowSharing` sets `sharingType = .none`
  on every window except the feed (tagged via `shareWindowID`), so the About panel /
  popover / Sparkle dialogs can't be picked in a call instead of the iPad. A window
  is shareable before it becomes key, so the guard sweeps on two triggers:
  `NSWindow.didBecomeKeyNotification`, and a change in `NSApp.windows.count` on the
  app update tick (silent while idle, so idle CPU holds). Both observers use the
  synchronous `addObserver(forName:queue:.main, using:)` form, not an `AsyncStream`
  Task hop, so the sweep runs in the same runloop tick the notification posts,
  before a share picker re-snapshots the window list; the AsyncStream form let
  Sparkle's in-process "Update Available" dialog race in. Known gaps: a close and
  open within one tick leaves the count unchanged and is missed, and Sparkle's
  Downloader and Installer XPC services and `Updater.app` run in other processes,
  out of reach. A new window type shown without focus that dodges both triggers
  must be swept explicitly.
- **The window toggle hotkey uses Carbon's `RegisterEventHotKey`**
  (`GlobalHotkey`). It fires while another app is frontmost (the in-call case),
  and unlike an `NSEvent` global monitor it needs no Accessibility grant or
  entitlement and works for the `LSUIElement` accessory app. Keep the instance
  alive: `deinit` unregisters.
- **The trial overlay is part of the share window's SwiftUI root**: a `ZStack`
  over `PreviewView`, toggled by an `@Observable ShareOverlayModel` flag
  (`ShareWindowController`). It is deliberately *not* a foreign `NSHostingView`
  subview added on top of the hosting view: that does not reliably composite
  above the layer-backed preview (the overlay silently never renders). Keep new
  share-window chrome inside this root, not as added subviews.

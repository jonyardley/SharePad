# SharePad — Design Spec

> Status: **Design (pre-implementation).** This document informs the plan; it is
> not the plan. Last reviewed: 2026-06-03.
>
> Working title **"SharePad"**, bundle id `com.jonyardley.sharepad` — both
> placeholders, confirm before Phase 0 (see [Open questions](#open-questions)).

---

## 1. Problem & goal

Sharing a connected iPad's screen on a video call today means a manual ritual:
open QuickTime → New Movie Recording → click the source dropdown → pick the iPad
→ find the resulting window → share *that specific window* → remember to hide the
QuickTime chrome. Every call. The friction lives entirely on the **Mac** side —
the iPad already mirrors fine — so the fix is a small **macOS menu-bar app**, not
an iPad app.

**Goal:** plug in the iPad and have a clean, shareable window of its screen
appear automatically, controllable from the menu bar, ready to pick in any
meeting app's "Share window" picker — with zero per-call setup.

**Primary use case:** live drawing / whiteboarding on the iPad during a call,
displayed as full shared content (not a webcam tile).

### Non-goals (v1)

- **Not** a virtual camera (see [§2](#2-approach--rejected-alternatives)).
- **No** iPad audio routing into the call.
- **No** annotation, recording, cropping, or multi-device mosaic.
- **No** distribution / App Store / notarization — personal local build.

---

## 2. Approach & rejected alternatives

Two viable architectures were considered. **Decision: window-share.**

| | **Window-share (CHOSEN)** | Virtual camera (rejected) |
|---|---|---|
| What it is | Capture iPad → render into a clean `NSWindow` you pick in the meeting's share picker | A CoreMediaIO system extension exposing "SharePad" as a selectable camera |
| Selection | Pick the window each call | One persistent click, every app |
| **Display** | **Full shared content — big, central** | Webcam *tile* unless pinned/spotlighted |
| Build cost | A weekend (AVFoundation + AppKit) | System extension + notarization + hardened-runtime entitlements + IOSurface piping; some apps (Zoom) reject 3rd-party cameras |

For **live drawing, display matters more than selection** — a whiteboard wants to
be full-size by default, which the virtual camera does *not* deliver. The
window-share is both the smaller build and the better fit. The virtual camera is
a genuine rabbit hole that solves the wrong half of the problem. Reconsider only
if "selection convenience" ever outranks "display size" (it won't for drawing).

---

## 3. Confirmed product decisions

From the design Q&A (2026-06-03):

| Decision | Choice | Notes |
|---|---|---|
| **Control surface** | Menu-bar icon → **popover with live preview** + controls | The shareable window is separate from the popover |
| **Framing** | **None — full iPad screen, clean** | No crop UI; window aspect-locks to the iPad's native ratio. Simplest pipeline (preview layer, no frame processing) |
| **Window behavior** | **Normal window** (movable, resizable, not pinned) | ⚠️ see [keep-on-top gotcha](#6-edge-cases--failure-modes) |
| **On connect** | **Fully automatic** — window appears ready to share | Optional auto-show guard deferred (see open questions) |

### Defaulted gaps (confirm or flip)

- **Window chrome:** borderless *content* (so the share is pure feed) but behaves
  like a normal window — movable by background, resizable with **locked aspect**.
  Close/show via popover. (Alternative: a standard title bar — but it gets
  captured into the share. Flagged.)
- **Keep-on-top toggle:** ships **off** by default; available in the popover as an
  escape hatch for browser-based Meet/Teams.
- **Launch at login:** **on** by default (it's a background utility).
- **Remembered window frame**, mirroring **off**, audio **out of scope**.

---

## 4. User experience & flows

### Surfaces

1. **Status item** — menu-bar icon. Two states: **idle** (dim, no iPad) and
   **live** (tinted, capturing).
2. **Popover** (click the status item) — live thumbnail of the feed, device name,
   device picker (only shown if >1 source), and toggles: *Keep window on top*,
   *Launch at login*, *Quit*. Plus a *Show/Hide window* affordance and, on error,
   an inline message with a **Open System Settings** button.
3. **Share window** — borderless, aspect-locked view of the iPad. This is the
   object you pick in the meeting app. No app chrome → pure feed.

```
 ┌─ Popover ────────────────────┐
 │  ┌────────────────────────┐  │
 │  │   live iPad thumbnail   │  │
 │  └────────────────────────┘  │
 │  iPad Pro (11-inch)          │
 │  [ Show window ]             │
 │  ☐ Keep window on top        │
 │  ☑ Launch at login           │
 │  ─────────────────────────   │
 │  Quit                        │
 └──────────────────────────────┘
```

### Flows

- **Launch:** app starts headless (no Dock icon), sets the CMIO opt-in, begins
  watching for devices. If an iPad is **already connected**, go straight to *live*.
- **iPad connects:** detect → start session → show the clean window at its last
  size/position → status item goes *live*.
- **Share:** in the meeting app's window picker, choose the SharePad window.
- **iPad disconnects / sleeps:** hide window, tear down session, status item *idle*.
  Reconnect resumes automatically.
- **Permission not yet granted:** first launch prompts for Camera; popover shows a
  "grant access" state until resolved.
- **Quit:** from the popover.

---

## 5. Architecture

### 5.1 Component model

```
        ┌──────────────┐   intents    ┌─────────────────┐
        │   SwiftUI    │ ───────────▶ │     AppModel     │  @Observable @MainActor
        │  popover +   │ ◀─────────── │  (state machine) │  — single source of truth
        │ status item  │   state      └────────┬─────────┘
        └──────────────┘                       │ commands
                                               ▼
   ┌────────────────┐   device events  ┌─────────────────┐
   │  DeviceMonitor │ ───────────────▶ │ CaptureController│  owns the one
   │ (CMIO + KVO)   │                  │ (AVCaptureSession)│  AVCaptureSession
   └────────────────┘                  └────────┬─────────┘
                                                 │ preview layers (GPU)
                              ┌──────────────────┴──────────────┐
                              ▼                                  ▼
                    ShareWindow (NSWindow)            Popover thumbnail view
```

- **`AppModel`** — the only place app state lives. An `@Observable @MainActor`
  type holding the state machine (§5.3), the selected device, permission status,
  and user toggles. Views render it and send intents; it issues commands to the
  controllers. **No domain/AV logic in views.**
- **`CaptureController`** — sole owner of the single `AVCaptureSession`. Builds
  inputs, owns the preview connection, starts/stops. Fronted by a protocol so
  `AppModel` logic is testable with a fake.
- **`DeviceMonitor`** — performs the CMIO opt-in once, runs the
  `AVCaptureDevice.DiscoverySession`, KVO-observes its `devices`, and emits
  connect/disconnect into `AppModel`.
- **`ShareWindowController`** — manages the borderless `NSWindow`, aspect lock,
  frame persistence, keep-on-top level.
- **`PreviewView`** — `NSViewRepresentable` wrapping an
  `AVCaptureVideoPreviewLayer` (used by both the window and the popover thumbnail).

### 5.2 Capture pipeline (one session, two views)

One `AVCaptureSession`; both the window and the popover display it. The pipeline
has **no frame processing** (no crop) — a preview layer renders directly on the
GPU, so it's cheap.

> **Technical risk to verify in Phase 3:** whether two
> `AVCaptureVideoPreviewLayer`s can attach to one session simultaneously (window +
> popover both visible). **Fallback** if not: a single `AVCaptureVideoDataOutput`
> fanning `CMSampleBuffer`s to both views, or downgrade the popover to a periodic
> snapshot. This does not change the component model above.

### 5.3 State machine (`AppModel`)

```
        ┌─────────────────────── permission denied ──────────────┐
        ▼                                                          │
  permissionDenied                                                 │
        ▲ grant                                                    │
        │                                                          │
   ┌─────────┐  granted   ┌──────────┐  device +  ┌──────────┐    │
   │ checking │ ────────▶ │ noDevice │ ─────────▶ │ starting │ ───┘
   │  perm.   │           └──────────┘  connect   └────┬─────┘
   └─────────┘                ▲                         │ session running
                              │ disconnect              ▼
                              └──────────────────────  live
                                       ▲                 │ runtime error
                                       │                 ▼
                                       └───────────── failed ──(retry)
```

States: `checkingPermission`, `permissionDenied`, `noDevice`, `starting`,
`live`, `failed`. Transitions are pure functions of (permission, device list,
session status) — kept in a testable reducer.

---

## 6. Technical foundation (verified)

Verified against Apple docs + developer forums (see [References](#references)).
This is the part the earlier research under-specified.

1. **CoreMediaIO opt-in is required.** A connected iPad is **not** visible to your
   app until you set `kCMIOHardwarePropertyAllowScreenCaptureDevices = 1` on the
   CMIO system object. Set it **once, at startup, before discovery**. (This is
   what QuickTime/OBS do internally.)

   ```swift
   var prop = CMIOObjectPropertyAddress(
       mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
       mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
       mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
   var allow: UInt32 = 1
   CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil,
                             UInt32(MemoryLayout.size(ofValue: allow)), &allow)
   ```

2. **The iPad is a `.muxed` device**, not `.video`. Discover with
   `AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)`
   (`.external` is macOS 14+; was `.externalUnknown`). Quick path:
   `AVCaptureDevice.default(for: .muxed)`. If a typed discovery returns empty,
   fall back to `AVCaptureDevice.devices(for: .muxed)` — **verify which surfaces
   the iPad** in Phase 1.

3. **Devices appear asynchronously** after the opt-in. **KVO the discovery
   session's `devices` property** — don't read it once at launch. This same
   observation drives auto-connect/disconnect (the "fully automatic" behaviour).

4. **Display via `AVCaptureVideoPreviewLayer`** with `videoGravity = .resizeAspect`
   — low-latency, GPU, aspect-correct, no manual frame handling.

5. **Stay video-only to dodge the mic prompt.** A muxed input carries audio, so
   naively adding it can trigger a **Microphone** TCC prompt. Add the input with
   **no connections** (`session.addInputWithNoConnections`) and wire only the
   **video** `AVCaptureConnection` to the preview. Keeps scope tight and avoids an
   unexplained mic permission.

6. **Permissions:** `NSCameraUsageDescription` + `AVCaptureDevice.requestAccess(for: .video)`.
   (Mic avoided per §6.5.)

### Caveats

- **No App Sandbox in v1.** The CMIO opt-in / screen-capture-device access is
  restricted under the sandbox. Personal build ships un-sandboxed — another reason
  distribution is deferred.
- **iPad must be unlocked** and "Trust This Computer" tapped once; a locked iPad
  shows black.
- **Wake from sleep** may interrupt the session — observe
  `AVCaptureSession.runtimeErrorNotification` / interruption notifications and
  restart.

---

## 7. Tech stack

| Concern | Choice |
|---|---|
| Language | Swift 5.9+ (Swift 6 mode if clean) |
| Menu bar + popover | SwiftUI `MenuBarExtra` (style `.window`) |
| Share window | AppKit `NSWindow` (borderless, aspect-locked) |
| Capture | AVFoundation (`AVCaptureSession`, `AVCaptureVideoPreviewLayer`) |
| Device visibility | CoreMediaIO (`kCMIOHardwarePropertyAllowScreenCaptureDevices`) |
| Launch at login | `SMAppService.mainApp` (macOS 13+) |
| Deployment target | **macOS 14.0** (clean `.external` API; user is on current macOS) |
| Project gen | **xcodegen** (`project.yml`, generated — not hand-committed) |
| Task runner | **just** (`justfile`) |
| Format / lint | **swiftformat** + **swiftlint** |
| Third-party deps | **None** — first-party frameworks only |

App is an **agent** (`LSUIElement = true`): no Dock icon, lives in the menu bar.
Accessory apps can still own windows (the share window works fine).

---

## 8. Module / file layout (target)

```
ipad-share/
  project.yml                 # xcodegen
  justfile                    # gen / build / run / fmt / lint
  DESIGN.md  CLAUDE.md
  specs/                      # per-feature specs if/when needed (Tier 3)
  Sources/SharePad/
    App.swift                 # @main, MenuBarExtra, LSUIElement wiring
    AppModel.swift            # @Observable @MainActor state machine
    State/
      AppState.swift          # enum + pure reducer (unit-tested)
    Capture/
      CaptureController.swift  # owns AVCaptureSession (protocol-fronted)
      DeviceMonitor.swift      # CMIO opt-in + DiscoverySession KVO
      CMIO.swift               # the opt-in helper (§6.1)
    Windows/
      ShareWindowController.swift
      PreviewView.swift        # NSViewRepresentable over preview layer
    UI/
      PopoverView.swift
      StatusItem.swift
    Support/
      Preferences.swift        # UserDefaults: frame, toggles
      Permissions.swift        # camera authorization
  Tests/SharePadTests/
    AppStateReducerTests.swift
    PreferencesTests.swift
```

---

## 9. Milestones (informs the plan)

Each phase is independently verifiable. Maps to PRs / plan steps.

| Phase | Deliverable | Verify by |
|---|---|---|
| **0 — Skeleton** | xcodegen + justfile + swiftformat/swiftlint; `LSUIElement` menu-bar app; empty popover; status item | App launches headless; icon in menu bar; `just run` works |
| **1 — Capture core** | CMIO opt-in; `.muxed` discovery; session; render to a *plain* window via preview layer | Plug iPad → see the live feed in a window |
| **2 — Clean window** | Borderless, aspect-locked, movable, frame persistence; video-only connection (no mic prompt) | Window is chrome-free; picks cleanly in a meeting app; no mic permission dialog |
| **3 — Popover** | Live thumbnail, device picker, toggles (keep-on-top, launch-at-login, quit); resolve two-preview-layer risk | Popover shows live feed; toggles work |
| **4 — Automatic lifecycle** | KVO connect/disconnect → auto show/hide; permission flow UI; error surfaces; sleep/wake restart | Unplug/replug and sleep cycles behave; denied permission shows a fix path |
| **5 — Polish** | App icon; status-item idle/live states; CPU check; optional auto-show guard | Looks finished; idle CPU acceptable |

---

## 10. Edge cases & failure modes

- **iPad already connected at launch** — must handle, not only connect-while-running.
- **Permission denied** — popover surfaces it with an *Open System Settings* button;
  never a silent dead state.
- **Multiple muxed sources** (two iPads, or iPhone + iPad) — device picker; remember
  last-used by `uniqueID`.
- **Device vanishes mid-call** — auto-hide + status dim. ⚠️ You may be mid-share —
  consider a brief notification rather than a silent disappearance (decide in Phase 4).
- **Mac/display sleep → wake** — restart session on runtime error / interruption end.
- **Locked iPad** — black feed until unlocked; surface a hint if detectable.
- **Normal-window share visibility** — Zoom desktop shares an occluded window fine;
  **browser Meet/Teams only transmit visible window content**. The *keep-on-top*
  toggle is the escape hatch. ⚠️ The one behavioural gotcha to remember.
- **HiDPI / aspect** — lock window aspect to the device's active-format dimensions;
  `resizeAspect` letterboxes safely if it ever mismatches.
- **CMIO is process-global** — set once; don't toggle per-session.

---

## 11. Testing strategy

Honest split — AVFoundation capture can't be meaningfully unit-tested without
hardware, so we **isolate the pure logic** and **manually verify the pipeline**.

- **Unit-tested (pure):** the `AppState` reducer (permission × device-list ×
  session-status → state), preference persistence, aspect math, device-selection
  (last-used by `uniqueID`). `CaptureController` is protocol-fronted so `AppModel`
  is driven by a fake in tests.
- **Manual (hardware) — documented checklist:** live feed appears; clean window
  shares in Zoom *and* a browser meeting app; no mic prompt; connect/disconnect/
  sleep cycles; permission-denied path. Each phase's "verify by" (§9) is the
  checklist.
- A claim of "done" for a capture phase means **the manual checklist was run**, not
  "tests pass" — tests don't exercise the camera.

---

## 12. Open questions

1. **Name + bundle id** — "SharePad" / `com.jonyardley.sharepad` are
   placeholders. Confirm before Phase 0.
2. **Window chrome** — borderless-but-movable (proposed) vs a standard title bar?
3. **Auto-show guard** — fully automatic (chosen) means the window also appears when
   you plug in *just to charge*. Add an opt-out toggle, or accept it?
4. **Mid-call disconnect** — silent hide vs a notification?
5. **Distribution later** — if this ever leaves your Mac, it needs signing +
   notarization + (likely) the sandbox question revisited. Out of scope now —
   confirm it stays out.

---

## References

- [AVCaptureDevice.DiscoverySession — Apple](https://developer.apple.com/documentation/avfoundation/avcapturedevice/discoverysession)
- [AVCaptureDevice.DeviceType.external — Apple](https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/external)
- [Programmatic capture of a connected iOS device — Apple Developer Forums #759245](https://developer.apple.com/forums/thread/759245)
- [Choosing a capture device — Apple](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/choosing_a_capture_device)
- [Support external cameras in your iPadOS app — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10106/)

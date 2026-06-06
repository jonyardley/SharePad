# SharePad — Design Spec

> Status: **Living spec — implementation in progress.** This document informs the
> plan; it is not the plan. Last reviewed: 2026-06-04.
>
> Name **SharePad**, bundle id `com.jonyardley.sharepad` — confirmed at Phase 0.

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
- ~~**No** distribution / App Store / notarization — personal local build.~~
  **Superseded (2026-06-05):** 1.0 ships as a notarized **direct download**
  (Developer ID, not App Store — the sandbox breaks the CMIO opt-in). The app is
  **open source (GPLv3)**; the notarized build is sold as a paid convenience, not
  enforced by a licence key. See `specs/distribution.md` and `specs/licensing.md`.

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

1. **Status item** — menu-bar icon. Two states: **idle** (`ipad.landscape`, no iPad)
   and **live** (`ipad.landscape.badge.play`, capturing) — a badged-symbol swap, not
   a tint, since the menu bar renders items monochrome.
2. **Popover** (click the status item) — live thumbnail of the feed, device name,
   device picker (only shown if >1 source), and toggles: *Keep window on top*,
   *Launch at login*, *Quit*. Plus a *Show/Hide window* affordance and, on error,
   an inline message with a **Open System Settings** button. The window also
   toggles via a system-wide hotkey **⌃⌥⌘H** (works mid-call, while the meeting app
   is frontmost). See `specs/window-hotkey.md`.
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
  frame persistence, keep-on-top level. Tags the feed window with a stable
  identifier and a `"SharePad"` title so it's the named pick in a call's picker.
- **`WindowSharing`** — guarantees the feed is the *only* shareable window: a
  launch-time guard that sets `sharingType = .none` on every other window
  (About panel, popover, Sparkle dialogs) whenever any window becomes key.
- **`PreviewView`** — `NSViewRepresentable` wrapping an
  `AVCaptureVideoPreviewLayer` (used by both the window and the popover thumbnail).

### 5.2 Capture pipeline (one session, two views)

One `AVCaptureSession`; both the window and the popover display it. The pipeline
has **no frame processing** (no crop) — a preview layer renders directly on the
GPU, so it's cheap.

> **Resolved (#10):** rather than test the two-preview-layer question, the popover
> thumbnail renders off the existing `AVCaptureVideoDataOutput` — frames fan into an
> `AVSampleBufferDisplayLayer` (via `AVSampleBufferVideoRenderer`), gated to
> "popover open" and throttled to ~15 fps. The window keeps the sole
> `AVCaptureVideoPreviewLayer` on the preview connection; no second preview layer
> exists. The component model above is unchanged.

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
| Auto-update | **Sparkle 2** (EdDSA-signed appcast) — the one third-party dependency |
| Third-party deps | **Sparkle only** (see flagged decision below); otherwise first-party |

App is an **agent** (`LSUIElement = true`): no Dock icon, lives in the menu bar.
Accessory apps can still own windows (the share window works fine).

**Flagged dependency — Sparkle 2 (first and only third-party dep).** Adopted for
auto-update, which a notarized direct-download app needs and Apple's frameworks don't
provide (no App Store update channel — App Store is out, DESIGN.md §6). Added via SPM
in `project.yml`; isolated behind `protocol SoftwareUpdating` (`Updater/`) so the view
layer and tests never import it. Under Hardened Runtime, Sparkle's nested XPC services
+ helpers are re-signed inside-out by the `sign` recipe (no `--deep`); a non-sandboxed
app needs **no** extra `com.apple.security.cs.*` entitlements, so `SharePad.entitlements`
stays camera-only. The EdDSA **public** key is embedded in the build (`SUPublicEDKey`);
the private key is a CI secret. See `specs/distribution.md` §7.

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
      WindowSharing.swift      # excludes non-feed windows from screen sharing
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
| **0 — Skeleton** ✅ | xcodegen + justfile + swiftformat/swiftlint; `LSUIElement` menu-bar app; empty popover; status item | App launches headless; icon in menu bar; `just run` works |
| **1 — Capture core** ✅ | CMIO opt-in; `.muxed` discovery; session; render to a *plain* window via preview layer | Plug iPad → see the live feed in a window |
| **2 — Clean window** ✅ | Borderless, aspect-locked (follows iPad rotation), movable; video-only connection (no mic prompt). Frame persistence deferred → [#7](https://github.com/jonyardley/SharePad/issues/7) | Window is chrome-free; picks cleanly in a meeting app; no mic permission dialog |
| **3 — Popover** ✅ | Toggles (auto-show, keep-on-top, launch-at-login) + Show/Hide button + armed status-item badge; first unit tests. Live thumbnail + device picker deferred → [#10](https://github.com/jonyardley/SharePad/issues/10) | Toggles persist; window shows/hides; icon shows armed state |
| **4 — Automatic lifecycle** ✅ | Auto show/hide (KVO); sleep/wake + runtime-error auto-restart (`resume` keeps the preview connection live); permission "Open System Settings" button; surfaced `failed`/Retry; pure tested `AppState` reducer | Sleep/wake recovers the feed; denied permission shows a fix path |
| **5 — Polish** ✅ | App icon ✅ (gradient squircle + iPad glyph); idle-CPU check ✅ — **idle ~0%** (the criterion); live is content-driven (~0.5% static → ~12–15% active), of which the rotation/thumbnail data output is ~4–6% (optimization tracked in [#23](https://github.com/jonyardley/SharePad/issues/23)). Status-item idle/live is a badged-symbol swap (not dim/tint); auto-show guard shipped (#6); a full `start()` now confirms a frame before going `.live`, routing a stalled device into `failed`/Retry ([#24](https://github.com/jonyardley/SharePad/issues/24)) | Idle ~0% — acceptable |

---

## 10. Edge cases & failure modes

- **iPad already connected at launch** — must handle, not only connect-while-running.
  On *first* launch the camera-permission grant + iPad "Trust" handshake settle
  *after* the device appears to discovery, so the first start can stall. `AppModel`
  runs a **bounded auto-retry** (a few attempts over a few seconds) instead of
  latching `failed`, so it self-heals without an unplug/replug
  (`specs/first-connect-retry.md`).
- **Permission denied** — popover surfaces it with an *Open System Settings* button;
  never a silent dead state.
- **Multiple muxed sources** (two iPads, or iPhone + iPad) — device picker; remember
  last-used by `uniqueID`.
- **Device vanishes mid-call** — auto-hide + status dim, **plus** a transient
  lost-share signal (popover banner + alert status symbol) when the share window was
  up at teardown, so a mid-call user isn't left guessing. (`specs/mid-call-disconnect.md`)
- **Mac/display sleep → wake** — restart session on runtime error / interruption end.
- **Locked iPad** — black feed until unlocked. **Confirmed not reliably detectable
  on macOS**: the session stays running and delivers valid-but-black frames (no
  interruption — those APIs are iOS-only — and no CMIO/`AVCaptureDevice` lock
  property). A hint would require a fuzzy pixel heuristic; deferred. Don't
  re-investigate expecting a clean API.
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

1. ~~**Name + bundle id**~~ — **Resolved (Phase 0):** `SharePad` /
   `com.jonyardley.sharepad`.
2. ~~**Window chrome**~~ — **Resolved:** borderless-but-movable feed, kept
   chrome-free. A `"SharePad"` title (drawn as no title bar on a borderless
   window) names it in the picker; `WindowSharing` excludes every *other* window
   from screen sharing so a titled aux window can't be shared in its place.
3. ~~**Auto-show guard**~~ — **Resolved (#6):** shipped an "Auto-show on connect"
   toggle (persisted via `Preferences.autoShowOnConnect`); off → the window stays
   hidden on connect and is opened manually.
4. ~~**Mid-call disconnect**~~ — **Resolved (2026-06-06):** no longer a silent hide.
   A teardown while the share window was up raises a transient lost-share signal
   (popover banner + alert status symbol), auto-expiring and cleared on reconnect.
   (`specs/mid-call-disconnect.md`)
5. ~~**Distribution later**~~ — **Resolved (2026-06-05):** 1.0 is a notarized
   **direct download** (Developer ID + Hardened Runtime + the
   `com.apple.security.device.camera` entitlement; **no** sandbox, since it breaks
   the CMIO opt-in — so App Store is out), auto-updating via Sparkle. The app is
   **open source under GPLv3**: anyone may build it; the prebuilt signed build is
   **sold as a paid convenience** (no trial, no licence keys — open source makes
   enforcement moot). Full plan in `specs/distribution.md` (release pipeline) and
   `specs/licensing.md` (the sell-the-build model).

---

## References

- [AVCaptureDevice.DiscoverySession — Apple](https://developer.apple.com/documentation/avfoundation/avcapturedevice/discoverysession)
- [AVCaptureDevice.DeviceType.external — Apple](https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/external)
- [Programmatic capture of a connected iOS device — Apple Developer Forums #759245](https://developer.apple.com/forums/thread/759245)
- [Choosing a capture device — Apple](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/choosing_a_capture_device)
- [Support external cameras in your iPadOS app — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10106/)

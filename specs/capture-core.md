# Phase 1 — Capture core (spec)

> Tier 3 spec — touches the capture pipeline, the CMIO opt-in, and camera
> permission, so it's domain-sensitive. Builds on the **verified foundation in
> [DESIGN.md §5–§6](../DESIGN.md)** — read those first; this spec does not restate
> them.

## Problem

Phase 0 shipped a headless menu-bar shell that does nothing. Phase 1 makes
SharePad actually capture: detect a USB-connected iPad and render its live screen
into a window on the Mac. This is the load-bearing, silently-breakable part (the
CMIO opt-in, the `.muxed` device, the surprise-mic-prompt trap), hence a dedicated
spec.

## Scope

**In (DESIGN.md §9, Phase 1):** CMIO opt-in → `.muxed` discovery (KVO) → one
`AVCaptureSession` → live feed in a **plain** window via
`AVCaptureVideoPreviewLayer`. Camera permission.

**Verify by:** plug in iPad → live feed shows in a window; **no Microphone prompt**.

**Out (later phases):** borderless / aspect-locked / persisted window (P2);
popover thumbnail, device picker, toggles (P3); pure `AppState` reducer, automatic
show/hide, error-surface UI, sleep/wake restart (P4); status-item idle/live polish
(P5).

## Approach

New modules (DESIGN.md §8):

- **`Capture/CMIO.swift`** — set `kCMIOHardwarePropertyAllowScreenCaptureDevices = 1`
  **once at startup, before discovery** (exact calls in DESIGN.md §6.1).
  Process-global; never toggled per session.
- **`Capture/DeviceMonitor.swift`** — `AVCaptureDevice.DiscoverySession([.external],
  mediaType: .muxed)`, **KVO on `.devices`** (devices appear async — never read
  once) → connect/disconnect events.
- **`Capture/CaptureController.swift`** — **sole owner** of the single
  `AVCaptureSession`, behind a `CaptureControlling` protocol (so `AppModel` is
  testable with a fake). Muxed input via **`addInputWithNoConnections`**, wiring
  **only** the video connection to the preview (the mic-prompt dodge —
  non-negotiable #5). start/stop off the main thread.
- **`Windows/PreviewView.swift`** — `NSViewRepresentable` over
  `AVCaptureVideoPreviewLayer` (`videoGravity = .resizeAspect`).
- **`Windows/ShareWindowController.swift`** — minimal **plain titled `NSWindow`**
  hosting the preview (borderless/aspect-lock is P2).
- **`Support/Permissions.swift`** — `authorizationStatus` / `requestAccess(for:
  .video)`. Add `NSCameraUsageDescription` via
  `INFOPLIST_KEY_NSCameraUsageDescription` (issue #3 — keeps the no-committed-plist
  setup).
- **`AppModel`** — thin this phase: holds permission status + current device +
  session-running flag; owns the controllers; opens the window when live. No AV
  logic in views.

Flow: launch → CMIO opt-in → check/request camera → if authorized, start
DeviceMonitor → device appears → CaptureController builds the session + video
connection → ShareWindow shows the preview. Capture/KVO callbacks run off-main,
then hop to `@MainActor` to mutate `AppModel`.

## Key decisions

1. Build the real, protocol-fronted CaptureController/DeviceMonitor/CMIO now — the
   non-negotiables demand a single-owner session + testable seams, and it's cheap
   to do right from the start.
2. `AppModel` stays thin; the pure, tested `AppState` reducer + rich lifecycle /
   error states are **Phase 4** (DESIGN.md §9 mapping).
3. Plain titled window now; borderless / aspect-lock / persistence is **Phase 2**.
4. Video-only from day one — not deferrable (non-negotiable #5).
5. Even minimal, surface permission-denied (a basic popover line) — never a silent
   dead state (non-negotiable #6); the polished "Open System Settings" path is P4.

## Open questions

1. **Which API surfaces the iPad** (DESIGN.md §6.2) — typed `DiscoverySession` vs
   `AVCaptureDevice.default(for: .muxed)` vs `devices(for: .muxed)`. Resolve on the
   first hardware run; code the DiscoverySession + KVO path regardless (needed for
   auto-connect).
2. **macOS 26 / Xcode 26 SDK** — confirm `.external` and the CMIO selectors compile
   cleanly on the current SDK; verify against live docs while coding.
3. **Permission-denied depth in P1** — minimal text surface (proposed) vs a fuller
   UI (defer the rich version to P4).

## Testing (DESIGN.md §11)

Pure unit tests are thin this phase (the testable reducer is P4). The real gate is
the **manual hardware checklist**: live feed appears; **no Microphone prompt**;
unplug stops cleanly; first-launch permission prompt fires; denied shows the basic
surface. "Done" means the checklist was run with the iPad (CLAUDE.md) — not a green
build.

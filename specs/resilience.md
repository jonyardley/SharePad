# Phase 4 — Resilience & lifecycle (spec)

> Tier 3 + domain-sensitivity (capture-session restart + permission flow → highest
> ceremony). See DESIGN.md §5.3 (state machine), §6 (sleep/wake caveat), §9
> (Phase 4), §10 (edge cases).

## Problem

The happy path works (Phases 0–3), but the app isn't yet dependable:
- A Mac **sleep/wake** or an `AVCaptureSession` **runtime error** kills the session,
  and it **doesn't recover** — the feed goes black until you unplug/replug. This
  bites mid-call (DESIGN §6).
- **Permission denied** shows only text — no way to fix it from the app.
- A failed capture-start is **silent** (black window, no explanation).

## Scope

**In:**
- **Auto-restart** the session on `AVCaptureSession.runtimeErrorNotification`,
  `interruptionEnded`, and Mac wake (`NSWorkspace.didWakeNotification`).
- **Permission fix path:** popover **"Open System Settings"** button → Camera privacy
  pane.
- **Error surface:** a **`failed`** state shown in the popover (not a silent black
  window), with a **Retry**.
- **Pure `AppState` reducer** (checkingPermission / permissionDenied / noDevice /
  starting / live / failed) derived from (permission, device, session-running,
  error) — finally delivers non-negotiable #3, cleans the popover status, and is
  unit-tested (uses the Phase 3 test target).

**Out / deferred:**
- Mid-call disconnect *notification* (DESIGN §10 open question) — the icon + popover
  already reflect a disconnect; keep silent for now.
- Frame persistence (#7), live thumbnail / device picker (#10), right-click idea.

## Approach

- **`State/AppState.swift`** — `enum AppState` + a **pure** reducer
  `AppState.reduce(permission:hasDevice:isRunning:failed:)`. No AVFoundation
  imports → unit-testable (DESIGN §5.3 / §11).
- **`CaptureController`** — observe `runtimeErrorNotification` /
  `wasInterrupted` / `interruptionEnded` on its session; emit restart events
  (`AsyncStream<Void>`, Sendable). Don't self-restart silently — let `AppModel`
  coordinate (it owns the current device + state).
- **`AppModel`** —
  - Observe `NSWorkspace.shared.notificationCenter` `didWakeNotification`; on wake,
    if a device is connected, re-`start(deviceID:)`.
  - Consume `CaptureController`'s restart events → re-`start(deviceID:
    currentDeviceID)` (start() already reconfigures + runs). Guard against
    tight-loops (ignore while a restart is in flight; if it re-fails, settle on
    `failed`).
  - Track `failed`; expose `state: AppState` via the reducer.
  - `openCameraSettings()` → `NSWorkspace.shared.open(Privacy_Camera URL)`;
    `retry()` → re-start for the current device.
- **`PopoverView`** — render by `state`: denied → "Open System Settings" button;
  failed → message + Retry; live → device name; etc.

## Open questions

1. **Does macOS wake actually need a manual restart**, or does the session
   auto-recover? DESIGN §6 says restart — confirm on hardware (sleep → wake → feed).
2. **Restart/retry policy** on repeated runtime errors — propose: one restart per
   event; if it immediately re-fails, show `failed` + manual Retry (no auto-loop).
3. Reducer scope — propose the full 6-state enum (small, testable).

## Testing

- **Unit (new):** `AppState.reduce` transition table (permission × device × running
  × error → state) — pure, no hardware.
- **Manual (hardware — the real gate):** sleep the Mac → wake → feed resumes;
  rapid unplug/replug recovers; deny camera → "Open System Settings" opens the
  Camera pane; a failed start shows the failed message + Retry, not silent black.

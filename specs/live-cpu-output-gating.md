# #23 — Gate the data output when the popover is closed (spec)

> Tier 3 + domain-sensitivity (capture-session wiring → highest ceremony). Closes
> [#23](https://github.com/jonyardley/SharePad/issues/23). Depends on the #24
> `awaitFrame` watchdog contract. See DESIGN.md §5.2 (data-output fan-out), §6
> (rotation KVO trap), §9 (CPU criterion).
>
> **⚠️ NOT mergeable on a green unit suite.** The mechanism's CPU win and several
> behaviours are AVFoundation/hardware facts — a spike on the iPad is the real gate
> (see "Hardware spike"). Unit tests can't cover this.

## Problem

The `AVCaptureVideoDataOutput` runs at full frame rate continuously, costing ~4–6%
CPU on an active screen even when the popover is closed (the common in-call case). It
serves two needs with very different rate requirements: the popover **thumbnail**
(~15 fps, popover-open only) and **rotation/dimension detection** (~1–2 fps, always).
So ~4–6% is wasted whenever the popover is closed.

## Scope

**In:** stop the data-output cost while the popover is closed; keep rotation detection
and the #13/#24 frame-confirmation watchdog working in that state.

**Out:** the share-window preview path (untouched); device-level frame-rate caps
(would throttle the shared window too); any audio.

## Approach

Three coupled changes in `Sources/SharePad/Capture/CaptureController.swift`:

1. **Gate via `connection.isEnabled`, not detachment.** The approved plan said
   "remove the output connection"; this refines to toggling the data-output
   **connection's `isEnabled`** instead. Rationale: `isEnabled` takes effect
   immediately with **no `beginConfiguration`/`commitConfiguration`**, never touches
   the preview connection (so it can't trip the `resume()` "frozen preview" hazard),
   and re-enabling is instant. The connection stays attached; only its data flow is
   gated. Desired state: `enabled = thumbnailActive || confirmingFrame`, default
   **disabled**. All of `thumbnailActive`, `confirmingFrame`, and the `isEnabled`
   write live on `sessionQueue`.

2. **Decouple rotation from the data output.** With the connection disabled, no frames
   flow → the existing frame-based size detection can't see a rotation while the
   popover is closed. Add an observer for the video port's
   `AVCaptureInputPort.formatDescriptionDidChangeNotification` (a *notification* —
   **not** the `formatDescription` **KVO** that aborts the app, per the existing
   `wireDimensionOutput` comment), read `port.formatDescription` directly in the
   handler, derive `CGSize`, and `sizeContinuation.yield(...)`. Keep the existing
   frame-based detection too (belt-and-suspenders: it still covers the initial size
   and popover-open rotations exactly as today; the notification adds the
   popover-closed case). Register in `configureAndRun`, remove in `teardown`.

3. **Preserve the watchdog frame source.** `awaitFrame` (used by #24's
   `startAndConfirm` on every connect and by `restart()` after `resume()`, mostly
   popover-closed) needs frames. Wrap it: set `confirmingFrame = true` (→ enable the
   connection) on `sessionQueue`, await a frame on `sampleQueue` (existing logic),
   then clear `confirmingFrame` (→ restore: disabled unless the popover is open). No
   reconfiguration — just an `isEnabled` flip. Without this, **every** popover-closed
   auto-connect would fail under #24 — so this is load-bearing, not optional.

`FrameOutput` keeps the thumbnail render gate and the `awaitFrame` waiter; it no
longer needs to be the only size source.

## Hardware spike (USER — the real "done" gate; I cannot run it)

1. Does `isEnabled = false` on the data-output connection actually **drop the ~4–6%**
   on an active screen (popover closed, idle stays ~0%)? If the buffer pipeline keeps
   running while disabled → no win; fall back to `removeConnection`
   (begin/commitConfiguration) per the original plan.
2. Does `formatDescriptionDidChangeNotification` fire on iPad rotation and yield the
   correct **flipped** dimensions while the popover is **closed** (window follows)?
3. Does enabling the connection only during `awaitFrame` reliably confirm a frame on a
   popover-closed connect/restart (no spurious `failed`)?
4. Initial connect: does the window open at the correct **aspect** (size arrives) with
   the popover closed?
5. Preview untouched: toggling the popover open/close shows no glitch in the share
   window.

If (1)/(3) fail, the documented fallbacks apply (detach mechanism, or close #23).

## Testing

- **Unit:** none meaningful — the gating, the notification, and `isEnabled` semantics
  are AVFoundation/hardware. Existing `FrameThrottleTests` (the `shouldRenderFrame`
  thumbnail throttle) stay green and unchanged. The #24 `AppModel` tests already
  exercise the `awaitFrame` contract this relies on.
- **Manual (hardware):** the spike above is the gate.

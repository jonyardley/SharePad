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

1. **Attach/detach the data output.** *(Revised after the hardware spike.)* The first
   attempt gated `connection.isEnabled` — but the spike measured **~15.7%** on an
   active screen with the output disabled (popover never opened), i.e. **no saving**:
   merely disabling the connection does **not** stop the buffer pipeline. So the gate
   now **removes the output + its connection** (`removeOutput`/`removeConnection`) when
   `!(thumbnailActive || confirmingFrame)`, and re-adds them on demand — each inside its
   own `beginConfiguration`/`commitConfiguration` on `sessionQueue`. Default
   **detached**. The preview connection is never touched, so the `resume()`
   "frozen preview" hazard is still avoided. `videoPort` is stored so the connection can
   be rebuilt on re-attach. All of `videoPort`, `dataConnection`, `thumbnailActive`,
   `confirmingFrame`, and the wiring live on `sessionQueue`.

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
   reconfiguration churn matched to the brief confirm — re-attaches the output, then
   detaches it. Without this, **every** popover-closed auto-connect would fail under
   #24 — so this is load-bearing, not optional.

`FrameOutput` keeps the thumbnail render gate and the `awaitFrame` waiter; it no
longer needs to be the only size source.

## Hardware spike (USER — the real "done" gate; I cannot run it)

1. ~~Does `isEnabled = false` drop the cost?~~ **Answered: no** — measured ~15.7%
   active with the connection disabled (no saving). Switched to **detaching** the
   output; re-test that `removeOutput` on an active screen (popover closed) drops to
   ~8–9% (idle stays ~0%).
2. Does `formatDescriptionDidChangeNotification` fire on iPad rotation and yield the
   correct **flipped** dimensions while the popover is **closed** (window follows)?
3. Does re-attaching the output only during `awaitFrame` reliably confirm a frame on a
   popover-closed connect/restart (no spurious `failed`)?
4. Initial connect: does the window open at the correct **aspect** (size arrives) with
   the popover closed?
5. Preview untouched: toggling the popover open/close — and the attach/detach
   reconfiguration — shows no glitch in the share window.

If (1) still shows no saving or (3) fails, fall back to removing the whole output path
or close #23 as not worth the risk.

## Testing

- **Unit:** none meaningful — the gating, the notification, and `isEnabled` semantics
  are AVFoundation/hardware. Existing `FrameThrottleTests` (the `shouldRenderFrame`
  thumbnail throttle) stay green and unchanged. The #24 `AppModel` tests already
  exercise the `awaitFrame` contract this relies on.
- **Manual (hardware):** the spike above is the gate.

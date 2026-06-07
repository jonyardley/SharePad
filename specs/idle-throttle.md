# Idle data-output throttle (issue #23) — WON'T FIX (measured)

> **Decision (2026-06-06): not worth implementing.** The gate was a measurement;
> the measurement killed it. On-iPad, with the iPad connected, the share window
> **hidden**, and the popover **closed** — the exact state this would optimise —
> SharePad sat at **~0.7–0.8% CPU, 0.0% GPU** (Activity Monitor, sustained). The
> ~4–6% figure in DESIGN §9 was the *live-active* cost (window compositing +
> thumbnail rendering), not this hidden-armed state: a hidden window isn't
> composited and decoding a mostly-static iPad screen is nearly free. So the win
> here is <1%, against ~60 min of `AVCaptureSession` reconfiguration touching the
> `awaitFrame` watchdog (the highest-severity risk below). Bad trade — closed.
>
> The design below is retained only so a future reader sees it was considered and
> why it was dropped. **Do not implement without a new measurement that contradicts
> the above.**
>
> ---
>
> *Original design (Tier 3; was: needs Plan mode + on-iPad measurement before coding):*

## Problem

While an iPad is connected, the `AVCaptureVideoDataOutput` delegate
(`FrameOutput.captureOutput`) runs for every frame even when the share window is
hidden **and** the popover is closed — the common "armed but not presenting" state.
Its output is only needed by: live video-size detection (window visible), the
popover thumbnail (popover open, already gated), and the `awaitFrame` watchdog
(connect/restart only).

## Key insight

The ~4–6% cost (DESIGN.md §9) is the data output's **connection** forcing the
session to deliver CPU-side `CMSampleBuffer`s — *not* the delegate body. An
early-return in the callback saves almost nothing. The real win is **dropping the
data-output connection when idle** (never the preview connection — that freezes the
layer, see `CaptureController.resume()`).

## Design

- Pure helper in `FrameThrottle.swift` (unit-testable, mirrors `shouldRenderFrame`):
  `frameDemand(windowVisible:popoverOpen:connecting:) -> .off / .sizeOnly / .full`.
  - `popoverOpen` → `.full` (render thumbnail)
  - `windowVisible || connecting` → `.sizeOnly` (dimensions / a watchdog frame)
  - else → `.off` (drop the data-output connection)
- Two levels: (1) delegate gate (cheap early-return by demand, folds in the existing
  `active` flag); (2) `setDataOutputEnabled(_:) async` on `sessionQueue` adds/removes
  **only** the data-output connection.
- `AppModel` recomputes demand on each driving signal (window-visible, popover-open,
  connecting) and pushes it to the controller.

## Highest-severity risk — watchdog re-enable

`awaitFrame` needs a frame; if the connection was dropped while `.off`, it would
time out falsely → `failed`. Fix: `connecting = true` (set before `awaitFrame` in
`startAndConfirm`/`restart`) forces demand ≥ `.sizeOnly`, and `setDataOutputEnabled`
is **awaited** before arming the watchdog. Unit-test this ordering specifically.

## Other risks

Stale aspect on show after a rotation-while-hidden (one resize tick once re-enabled —
verify on device); connection thrash on rapid popover toggles (debounce the
*disable* direction only; enable immediately). Preview connection always stays live →
instant window-show preserved.

## Measurement protocol (before claiming a win)

Activity Monitor %CPU over 60s per scenario, iPad showing a static drawing:
(1) armed + hidden + popover closed [target], (2) window visible, (3) popover open,
(4) connect-cold + sleep/wake restart (latency + no false `failed`). Instruments
Time Profiler to attribute `captureOutput` / decode / CA render. Pass: scenario 1
drops materially toward the §9 idle ~0% criterion; 2–4 unchanged within noise.

## Tests

Exhaustive `frameDemand(...)` truth-table in `FrameThrottleTests`; fake-driven
`AppModel` test asserting `setDataOutputEnabled(true)` is awaited **before**
`awaitFrame` on the connect/restart path (the regression guard).

# #24 — Confirm frames after a full `start()` (spec)

> Tier 3 + domain-sensitivity (touches the capture restart / state machine → highest
> ceremony). Closes [#24](https://github.com/jonyardley/SharePad/issues/24). Builds on
> the #13 `resume()` watchdog. See DESIGN.md §5.3 (state machine), §6 (sleep/wake),
> §9 (Phase 4/5), §11 (testing).

## Problem

`CaptureController.start()` returns `session.isRunning`. A *present-but-stalled*
device can report `isRunning == true` with **no frames** — leaving the app in `.live`
over a frozen preview. The #13 watchdog already confirms a frame after `resume()`
(`awaitFrame`), but a full `start()` does not. Three start sites are unguarded:
`AppModel.restart()`'s fallback, `switchTo(deviceID:)`, and `reconcile(...).switchTo`.

## Scope

**In:** confirm a frame after every full `start()`; route a no-frame start into the
**existing** `failed` state (popover message + Retry). Unit tests.

**Out:** any new `AppState`; CMIO/permission/window changes; #23 (output gating).

## Approach

The issue notes a fix "needs a Retry-able terminal state, not a hard failure." That
state already exists: `AppState.failed` → `PopoverView` "Retry" → `AppModel.retry()`
→ `restart()`. So no new state — a stalled start simply sets `failed`, exactly like a
`start()` that returns `false` does today.

- **`AppModel`** — add `startFrameTimeout` (≈3.0 s; cold start can be slower than the
  warm `resume` path's `frameTimeout = 1.5`). Add a `startAndConfirm(deviceID:)`
  helper = `start()` then `awaitFrame(timeout: startFrameTimeout)`. Replace the three
  `await capture.start(deviceID:)` calls with it; the existing `running` →
  `isLive`/`failed` wiring is unchanged.

**Why it's safe for a locked iPad:** a black/locked iPad still emits valid buffers, so
`awaitFrame` succeeds — only a true stall (zero buffers) trips `failed`.

## Open questions

1. **`startFrameTimeout` value** — 3.0 s proposed; the real first-frame latency of a
   cold muxed-device start is a hardware datum. Too tight → spurious `failed` on a
   slow-but-fine device; the Retry button is the escape hatch either way. Confirm on
   the iPad.

## Testing

- **Unit:** `FakeCaptureController.awaitFrame` becomes a FIFO sequence
  (`awaitFrameResults`, falling back to `awaitFrameResult`) so "resume stalls → start
  confirms" is expressible. `testRestartFallsBackWhenResumeDeliversNoFrame` uses
  `[false, true]`. New `testStartConfirmStallSurfacesFailed`: start runs but no frame
  → `failed`.
- **Manual (hardware — the real gate):** plug iPad → `.live` within ~3 s with no
  spurious `failed`; connect/disconnect/sleep-wake cycles still recover.

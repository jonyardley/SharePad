# First-connect retry through the permission/trust settling window (spec)

> Tier 3 + domain-sensitivity (state machine + permission flow + capture lifecycle →
> highest ceremony). Builds on the #13 `resume()` watchdog and #24 start-confirm.
> See DESIGN.md §5.3 (state machine), §6 (CMIO opt-in / trust caveats), §9 (Phase
> 4/5), §11 (testing). **File a tracking issue before the PR** — referenced below as
> the bug.

## Problem

On the **first ever use** with the iPad already plugged in, the app does **not**
auto-connect after the user grants camera permission and completes the iPad "Trust
This Computer?" handshake. Unplug + replug and it connects; every launch after that
is fine.

First launch has an async **settling window**: camera-permission grant and the iPad
trust handshake complete *after* the iPad first appears to
`AVCaptureDevice.DiscoverySession`. The state machine makes exactly **one start
attempt per device-*list* change** and has no recovery when a present device isn't
yet streaming-ready:

- Discovery delivers the iPad while it's still settling → [`reconcile`] resolves
  `.switchTo` → `startAndConfirm` stalls (no frame inside `startFrameTimeout`) →
  latches `failed`, with `currentDeviceID` now **set**.
- The iPad becoming streaming-ready afterward is a device **property** change, not a
  change to the discovery `devices` **array**, so KVO `.devices` doesn't re-fire →
  `reconcile` never re-runs.
- Even if it did re-fire, `resolveDevice` now returns `.keep` (id matches
  `currentDeviceID`), and the `.keep` branch only renames — it **never retries the
  start**.

A physical re-plug *is* an array change → fresh `.switchTo` → and by then the iPad is
ready → works. Subsequent launches: permission already granted + iPad already
trusted, so the first `.initial` snapshot delivers a ready device and it connects
first try. That matches "fine after that."

## Scope

**In:** a **bounded automatic retry** so a present-but-not-yet-live device self-heals
across the settling window, instead of latching `failed` until a physical re-plug.
After the window expires, settle on the **existing** `failed` state (popover message
+ Retry). Unit tests for the retry policy.

**Out:** any new `AppState`; CMIO/permission/window/discovery changes; recreating the
`DiscoverySession`; changing the manual `retry()` / `restart()` paths; the locked-iPad
black-frame behaviour (a locked iPad still emits buffers → `awaitFrame` succeeds, so
it isn't a stall — see #24).

## Approach

Keep the single-owner / pure-reducer boundaries intact. The retry lives in `AppModel`
(it owns lifecycle + current device), mirrors the existing one-shot `restart()`
discipline, and is driven off the **frame-confirm** result — not a new KVO or a busy
poll.

- **`AppModel`** — when a `startAndConfirm` for the **current** device fails on the
  *automatic* connect paths (`reconcile`'s `.switchTo`, and a new self-heal in
  `.keep`), schedule a **bounded** retry instead of latching `failed` immediately:
  - Up to **N** attempts (propose `firstConnectRetries = 4`), each after a short
    delay (propose `retryDelay ≈ 1.5 s`) → ~6 s of coverage for the trust/lock-screen
    settle.
  - Each retry **re-checks preconditions**: still the current device, still present
    in `devices`, still not live, not `isReconfiguring`. Bail the moment any fails
    (device unplugged, user switched source, a frame arrived).
  - Only after the attempts are exhausted does `failed = true` stick. Manual **Retry**
    (`restart()`) remains the escape hatch, unchanged.
  - **No tight loop / no overlap:** reuse the `isReconfiguring` guard so a retry can't
    interleave with a switch/restart; cancel any in-flight retry sequence when a new
    connect/teardown supersedes it (store a `connectGeneration` token + the `retryTask`
    and re-check the token after each delay and each `await`).
  - **`.keep` self-heal — deferred.** The timed retry loop fixes the bug on its own
    (it doesn't depend on a KVO re-fire), and manual **Retry** covers the rare "device
    readies *after* the window exhausts" case. Keeping load-bearing capture code
    minimal won; revisit only if hardware shows the window is too short.

- **Delay injection for tests:** the bounded retry must be unit-testable without real
  time. Inject the sleep (e.g. a `sleep: (Duration) async -> Void` defaulting to
  `Task.sleep`, or a clock) so a test can drive "attempt 1 fails, attempt 2
  succeeds" deterministically against `FakeCaptureController`. The fake already
  supports a FIFO `awaitFrameResults` / `startResult` sequence to stage this.

## Open questions

1. **`firstConnectRetries` / `retryDelay` values** — 4 × 1.5 s (~6 s) proposed. The
   real trust→streaming-ready latency is a hardware datum; too short → still spuriously
   `failed` on first launch, too long → a genuinely-dead device shows "Connecting…" for
   ages. Confirm on the iPad and tune. Retry button is the escape hatch either way.
2. **Should the manual switch path (`switchTo(deviceID:)`) also get the bounded
   retry?** Propose **no** — a user-initiated switch failing fast into Retry is fine;
   the bug is specifically the *automatic* first connect. Keep scope tight.
3. **State during retries** — present + not-live currently reduces to `.starting`
   ("Connecting…"). Propose keeping that for the retry window (honest: it *is* still
   trying), flipping to `.failed` only when attempts exhaust. No new state.

## Testing

- **Unit (new, pure layer via the fake):**
  - First connect: `startResult`/`awaitFrame` staged to fail then succeed → model
    ends `isLive == true`, `failed == false`, started the device more than once, and
    auto-shows once (with `autoShowOnConnect`).
  - Exhaustion: every attempt fails → after N attempts `failed == true`, `isLive ==
    false`, window hidden; attempt count == N (no infinite loop).
  - Supersede: device disappears (`reconcile([])`) mid-retry → retry stops, teardown
    wins, no late `failed`/start after teardown.
  - Regression: `testSecondDeviceDoesNotYankActive`, `testFirstDeviceStartsAndAutoShows`,
    `testStartFailureSurfacesFailed`, `testStartConfirmStallSurfacesFailed` still pass
    (the last two now assert failure *after exhaustion*, or use a single-attempt
    config — adjust deliberately, not by weakening).
- **Manual (hardware — the real gate):** the actual repro. **Reset TCC**
  (`tccutil reset Camera <bundle-id>`) and **forget the iPad's trust** (or use an iPad
  that's never trusted this Mac) → launch with the iPad plugged in → grant camera →
  trust the iPad → the window appears automatically within the retry window, **no
  unplug/replug needed**. Then: subsequent launches still connect first try;
  connect/disconnect/sleep-wake still recover; a genuinely-absent feed still settles
  into `failed` + Retry (not "Connecting…" forever).

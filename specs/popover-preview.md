# Phase 3 follow-up — Live popover preview + device picker (spec)

> Tier 3 — touches the **capture pipeline** (a second render path off the one
> session), so the domain-sensitivity override applies. Closes
> [#10](https://github.com/jonyardley/SharePad/issues/10). Builds on Phase 3
> (popover controls). See DESIGN.md §3–§4 (popover = live preview + controls),
> §5.2 (two-preview-layer question + fan-out fallback), §10 (multiple muxed
> sources), §11 (device-selection is unit-testable).

## Problem

The popover ships its controls but not the two items DESIGN §4 puts at the top of
the surface: a **live thumbnail** of the feed and a **device picker** when there's
more than one source. Today `PopoverView` shows only the device *name* — you can't
see the feed without opening the share window, and a second iPad/iPhone can't be
chosen.

The two halves differ in risk and are independently shippable:

- **Thumbnail** = the one unresolved technical risk in the design (§5.2). Tier 3.
- **Picker** = pure device-selection logic + a `Picker`. Lower risk.

## The crux (thumbnail)

The share window already owns the single `AVCaptureVideoPreviewLayer`
(`ShareWindowController(previewLayer: controller.previewLayer)`). A `CALayer` lives
in exactly one view hierarchy, so the popover **cannot** reuse that layer — it
needs its own render path off the same session. Two candidates:

**A — Second preview layer.** Create a second `AVCaptureVideoPreviewLayer` and add a
second `AVCaptureConnection(inputPort: videoPort, videoPreviewLayer:)` to the
session. The codebase already wires connections by hand (`addInputWithNoConnections`
+ `addConnection`), so this slots in. Near-zero cost *if allowed* — but whether one
session accepts **two** preview-layer connections off a single port is exactly the
unproven §5.2 question (historically AVCaptureSession permitted one). `canAddConnection`
answers it at runtime; rendering must be confirmed on the iPad.

**B — Data-output fan-out.** CaptureController **already runs an
`AVCaptureVideoDataOutput`** (`dataOutput`, wired in `wireDimensionOutput` for
rotation sizing): frames flow on `sampleQueue`, and the delegate currently just
reads dimensions and drops the buffer. Extend that delegate to also forward
`CMSampleBuffer`s to an optional sink, and render them in the popover via an
`AVSampleBufferDisplayLayer`. Sidesteps the §5.2 question entirely; the open/close
lifecycle is a sink toggle (no session reconfiguration); the plumbing is half-built.
Cost: enqueue + a small display-layer view, throttled since it's a thumbnail.

*(Floor, if both disappoint: a periodic still snapshot from the data output every
~500 ms while the popover is open — "live-ish", lowest cost. DESIGN §5.2.)*

### Recommended path

1. **Time-boxed spike of A** (~30 min): add the second connection, check
   `canAddConnection`, confirm it renders on the iPad. If it works → ship A
   (zero conversion cost) and skip B.
2. **Otherwise B** — the robust path to size the work against: fan the existing
   `dataOutput` into an `AVSampleBufferDisplayLayer`. A is upside, B is the plan.

Either way **CaptureController owns the change** (Non-Negotiable #1: one session,
one owner). The popover is handed a layer/handle and only *observes* — it never
creates, mutates, or starts the session. Both paths stay video-only (the second
connection is off the video port; the data output is already audio-free), so no
Microphone prompt (NN #5).

### Lifecycle

The thumbnail should render **only while the popover is open** (idle CPU — this
feeds the Phase 5 CPU check). Drive it from `PopoverView` `.onAppear` /
`.onDisappear` → `model.popoverDidAppear()` / `popoverDidDisappear()`, which either
add/remove the second connection (A) or set/clear the frame sink (B). Verify that
`MenuBarExtra(.window)` fires these reliably.

## Device picker

- **`AppModel`** exposes the full `devices: [CaptureDevice]` and a `selectedDeviceID`
  (today it keeps only `currentDeviceName` / `currentDeviceID` and blindly takes
  `devices.first`). New intent: `selectDevice(id:)`.
- **Selection is a pure function** — `pickDevice(from:current:lastUsed:)`: keep the
  current device if still present; else the last-used `uniqueID` if present in the
  list; else the first. Unit-tested (DESIGN §11), lives beside the reducer.
- **`reconcile(devices:)`** uses it: switch capture only when the resolved selection
  changes; if the selected device vanishes but others remain, re-pick — don't drop
  to `noDevice`.
- **Persist** the last-used `uniqueID` in `Preferences` (new key).
- **`PopoverView`** shows a `Picker` only when `devices.count > 1` (DESIGN §4).
- **Reducer untouched:** `AppState` keys off `hasDevice`, not device *count*, so the
  state machine stays put — the picker is purely an AppModel/Preferences concern.

## Scope

**In:** live popover thumbnail (path chosen by the spike); popover open/close
lifecycle; multi-source device picker; pure device-selection + last-used
persistence; unit tests for selection; manual hardware verification.

**Out:** the share-window render path (untouched — it keeps its preview layer);
window-frame persistence ([#7](https://github.com/jonyardley/SharePad/issues/7));
any audio.

## Key decisions

1. **Thumbnail needs its own render path, not the shared layer** — the window owns
   the one preview layer and a `CALayer` can't be in two hierarchies.
2. **Spike A, plan for B.** Second preview layer if the session allows it; otherwise
   data-output fan-out via `AVSampleBufferDisplayLayer` (plumbing already exists).
3. **Render only while the popover is open** — protects idle CPU.
4. **CaptureController owns it; the popover observes** (NN #1); both paths stay
   video-only (NN #5).
5. **Device selection is a pure, tested function**; the `AppState` reducer is
   untouched.
6. The **picker is independently shippable** and lower-risk than the thumbnail —
   can be its own PR.

## Open questions

1. **A or B** — settled by the spike (does one session take two preview-layer
   connections *and* render on hardware?). The plan assumes B; A is a bonus.
2. **Thumbnail throttle** (path B) — full frame rate vs. a cap (~15 fps) for a
   ~240 px thumbnail. Propose a cap; confirm against the CPU check.
3. **`MenuBarExtra(.window)` appear/disappear** reliably driving the lifecycle hooks
   — verify; fall back to observing the status-item/popover if not.
4. **One PR or two?** Picker (low-risk) first, thumbnail second — or together.
   Propose **two PRs**.

## Testing

- **Unit:** `pickDevice(from:current:lastUsed:)` — current-present, fall back to
  last-used, fall back to first, selected-vanishes-with-others-present, empty list.
  `Preferences` round-trip for the last-used `uniqueID`.
- **Manual (hardware — DESIGN §9/§11):** thumbnail shows the live feed *with the
  share window also open* (the §5.2 two-render case); opening/closing the popover
  starts/stops the thumbnail (watch CPU); two sources → the picker switches the feed
  and the window follows; last-used source remembered across relaunch; **no mic
  prompt**; unplug the selected source with another still present → re-picks rather
  than blanking.

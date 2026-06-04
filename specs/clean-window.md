# Phase 2 — Clean window (spec)

> Tier 3 — touches the window/share model. Builds on Phase 1. See DESIGN.md §3
> (window behaviour/chrome), §9 (Phase 2), §10 (share-visibility gotcha).

## Problem

Phase 1 renders the iPad feed into a **plain titled `NSWindow`**. Two problems
(observed on hardware): the title bar + traffic lights are captured into the share,
and the fixed-size portrait window **letterboxes** the feed (white bands) when the
iPad is in landscape. We want a **borderless** window whose aspect **matches the
iPad's current orientation** and updates live when it rotates.

## Scope

**In:**
- **Borderless** — no title bar / chrome; the share is pure feed (DESIGN.md §3).
- **Aspect-locked to the live video** — window aspect = current iPad video
  dimensions; user-resize keeps that aspect (no letterbox).
- **Follows rotation** — iPad portrait↔landscape → window resizes to the new aspect.
- **Still a normal window** — movable (by background) + resizable; show/close via
  the popover.

**Out (later / optional):** frame persistence (remember position+size) — optional
follow-up; keep-on-top toggle + popover thumbnail (Phase 3).

## Approach

- **Live dimensions (the crux).** A video-only `AVCaptureVideoDataOutput`
  (sample-buffer delegate, off-main, deduped) reads `CMVideoDimensions` from each
  frame and emits a Sendable `CGSize` on change. `CaptureController` owns it (single
  session owner) and reports sizes to `AppModel` → `ShareWindowController`. Still
  video-only (no audio port) → no mic prompt.
  **Why not KVO:** observing `AVCaptureInput.Port.formatDescription` was tried first
  and **crashes** — `AVCaptureInputPort` raises `valueForUndefinedKey:` inside its
  KVO notification when the format is set → `SIGABRT`. So the data output is the
  approach, not a fallback.
- **Borderless window.** `NSWindow` subclass: `styleMask = [.borderless,
  .resizable]`, override `canBecomeKey`/`canBecomeMain` = `true`,
  `isMovableByWindowBackground = true`, `backgroundColor = .black`,
  `contentAspectRatio` = current video size. Update aspect + resize on size change.
- **Sizing.** Initial content size = video aspect scaled to a sensible max (long
  side ≈ 900 pt). On rotation, recompute to the new aspect, preserving the long-side
  length so the window doesn't jump in area.
- **Wiring.** `CaptureController` emits dimension changes; `AppModel` holds
  `videoSize`; `ShareWindowController` shows/updates at that aspect.

## Key decisions

1. Borderless + movable-by-background + resizable + aspect-locked — DESIGN.md §3
   ("borderless content, behaves like a normal window").
2. Dimensions via `port.formatDescription` KVO (light; fits the no-frame-processing
   design); data-output fallback only if rotation isn't caught.
3. Black window background → clean letterbox if aspect ever momentarily mismatches
   (`videoGravity = .resizeAspect` already prevents distortion).
4. Frame persistence deferred (optional follow-up).

## Open questions (resolve on hardware)

1. ~~Does `AVCaptureInput.Port.formatDescription` KVO fire on rotation?~~
   **Resolved:** it *crashes* (`valueForUndefinedKey:` → `SIGABRT`); using a
   video-only `AVCaptureVideoDataOutput` instead.
2. Does a borderless window still appear/behave correctly for an `LSUIElement` app
   (become key, move, resize without a title bar)?
3. Does removing chrome change how the window is picked in meeting-app share
   pickers? (It still appears in the window list — verify; ties to §10.)

## Verification (hardware)

- Window has **no title bar / chrome** — pure feed.
- Portrait iPad → portrait window; **rotate to landscape → window resizes** to
  landscape with no white bands.
- Window is **movable** (drag the feed) and **resizable** (stays aspect-locked).
- Still shares cleanly in a meeting app's window picker.

# Screen recording stopped by iPadOS (spec)

> Tracks the second bullet of
> [#162](https://github.com/jonyardley/SharePad/issues/162). Hardware check in
> [#265](https://github.com/jonyardley/SharePad/issues/265).

## Problem

iPadOS can end the app's ReplayKit capture on its own: a Control Centre screen
recording, a phone or FaceTime call, or another app taking the recorder. The app
was not told. `StreamingRules` stayed at `running`, no frames reached the Mac,
and the pill still said "Live on <Mac>". That is a silent dead state, against
Non-Negotiable 6.

## Approach

- `ScreenRecorder` observes `RPScreenRecorder.isRecording` while a capture runs.
  When it turns false after the capture reported started, and the app did not
  ask to stop, it calls a new `onEnded` callback on the main actor. `stop`
  drops the observation before it calls `stopCapture`, so an app-requested stop
  never reports as ended. A stop that arrives before the start completion is
  kept and reported straight after a successful start.
- `StreamingRules` gets `Event.captureEnded`. From `running` or `starting` it
  sets `captureInterrupted` and stops the capture (`stopping`, then `idle` once
  ReplayKit confirms), so the observation and frame handler are torn down; in
  `idle` or `stopping` it is ignored. While the flag is set, capture does not start again on its own.
  Try Again (`retryCapture`) and going to the background clear it.
- The pill reads "Screen recording stopped", attention tone, with Try Again,
  while the link is up. Pairing, Wi-Fi sharing off and local network off still
  outrank it.

## Key decisions

1. **No automatic restart.** Every new capture shows the record prompt again
   (`specs/wireless-product.md` §11, item 2). Restarting by itself would put a
   prompt on screen the person did not ask for, and if iPadOS keeps taking the
   recorder (a call in progress) it would nag in a loop. The person taps Try
   Again when they are ready.
2. **Not in scope:** what the Mac window shows when frames stop (unchanged), and
   pop-ups over the canvas (the first bullet of #162).

## Open questions

1. Does the `isRecording` change fire for every way iPadOS stops the capture?
   Checked on hardware as a step in #265: while sharing to the Mac, start a
   screen recording from Control Centre. The pill should change to "Screen
   recording stopped", and Try Again should bring the Mac picture back.
2. The `isRecording` signal is unconfirmed for a phone or FaceTime call and for
   another app taking the recorder. Both are checked in #265. If it stays
   silent for either, the fallback is a frame-stall timer in `StreamingRules`,
   or `RPScreenRecorderDelegate`.
3. If Try Again is tapped while a call still holds the recorder, the start
   fails and the pill reads "Screen recording not allowed". Acceptable for now.

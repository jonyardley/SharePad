# Canvas render spike (decision 1a)

> Status: **NO-GO, abandoned (Jon, 2026-10-03).** The Debug code stays in place, unused. Owner: Jon. Opened 2026-10-03.

## 1. Problem

The W3b hardware check (`specs/wireless-product.md` §10) found that ReplayKit
in-app capture asks to record on **every open** (§11, item 2). That breaks the
product promise "open the app and it streams": every call starts with a system
dialog on the iPad.

The iPad app only ever needs to share its own canvas. It already owns every
pixel of it, so it can draw the canvas into pixel buffers itself and skip
ReplayKit.

## 2. Question

Can the app render its canvas (paper plus `PKCanvasView`, including the stroke
being drawn) into `CVPixelBuffer`s for the existing encoder, at a cost no worse
than ReplayKit, on an iPad Pro?

## 3. Approach

### What cannot work

Rendering from `PKDrawing` (`image(from:scale:)`) alone. A stroke joins the
drawing only when the pencil lifts (`canvasViewDrawingDidChange`), so the Mac
would see ink appear in whole strokes, after the fact. The Xcode 27 PencilKit
headers have no live-stroke or snapshot API (searched 2026-10-03: only
`PKDrawing.imageFromRect:scale:` and the iPadOS 27 `PKStrokeRenderState`, which
describes finished strokes).

### What the spike tries

Snapshot the live view each display frame into an IOSurface-backed BGRA pixel
buffer from a pool:

1. Paper first, from the same SwiftUI `PaperBackground` the screen shows,
   rendered once per paper and size with `ImageRenderer` and cached.
2. The canvas view on top, by one of two methods, picked at launch:
   - `hierarchy`: `UIView.drawHierarchy(in:afterScreenUpdates: false)`, which
     reads the composited result and so should include the Metal-backed ink.
   - `layer`: `CALayer.render(in:)`, cheaper, but documented to skip content
     the render server draws, which may include PencilKit's ink.

The buffer is the canvas only, so the toolbar, tool palette, sheets and
popovers are never in it. Frames go out with a whole-buffer crop.

It runs from the canvas's existing `CADisplayLink` (30 to 60 fps), on the
main thread, because `drawHierarchy` must.

### A fair comparison

`CanvasRenderer` sits behind the existing `ScreenRecording` protocol, so the
start and stop rules, `StreamSender`, the encoder and the paired link are the
same code for both paths. A Debug launch argument picks the source; Release
builds always use ReplayKit.

## 4. Measurement

A Debug-only probe writes two CSVs to the app's Documents folder:

- `*-frames.csv`, one row per captured frame: how long from the frame's capture
  time to its arrival in the app (`delivery_ms`), and for the renderer, the
  main-thread draw cost (`render_ms`: paper and canvas only, not the buffer,
  sink or hand-off around it).
- `*-seconds.csv`, one row a second: captured frame rate, process CPU, battery
  level and thermal state; plus the sender's own last report (encoded frame
  rate, mean sink-to-encoded time `encode_ms`, bit rate, skipped frames), left
  empty when no fresh report arrived that second. Captured frames are counted
  before the overlay gate, so ReplayKit's include frames the gate holds.

`encode_ms` comes from a small addition to `StreamSender.Stats` in
`SharePadWire`. Pipeline latency on the iPad is `delivery_ms + encode_ms`.

### Caveats, known before the runs

1. **ReplayKit's CPU is not all ours.** Part of ReplayKit's work runs in system
   daemons, outside the process CPU the probe reads. Process CPU therefore
   flatters ReplayKit; battery is the fair comparator.
2. **Battery reads in 5% steps** on iPadOS. An hour per path, same start
   charge, same brightness, is the minimum that says anything.
3. **The renderer draws every display frame, changed or not**, while ReplayKit
   delivers only when the screen changes. The minute's rest in each loop of the
   drawing script therefore costs the renderer CPU and battery that a shipping
   version would skip, so a GO on CPU and battery is conservative.
4. **`drawHierarchy(afterScreenUpdates: false)` reads the last committed
   frame**, so its content can be up to one display frame older than its
   timestamp: renderer latency reads 8 to 17 ms better than it is.
5. **`delivery_ms` assumes ReplayKit timestamps on the host clock.**
   `analyse.swift` warns if the median says otherwise.
6. Glass-to-glass latency on the Mac is not measured; the Mac app does not log
   it, and W5's office-network check covers it for the shipping path.

## 5. Pass bar

| Measure | GO if |
|---|---|
| Ink mid-stroke | The stroke being drawn appears on the Mac before the pencil lifts |
| Frame rate | Encoded fps holds at the display rate while drawing (no worse than ReplayKit) |
| Main thread | `render_ms` p95 under 8 ms, so drawing on the iPad stays at 120 Hz on ProMotion |
| Latency | `delivery_ms + encode_ms` median no worse than ReplayKit's |
| CPU | Process CPU within 15 points of ReplayKit (see caveat 1) |
| Battery | An hour's drop no worse than ReplayKit's by more than one 5% step |
| Content | Paper, ink, lasso selection and ruler as they look on the iPad; nothing else |

## 6. What it removes on GO

- `ScreenRecorder` and the per-open prompt (§11, item 2).
- `PaletteLocator` and the palette half of `ToolsPlacement` (#169): no private
  view class lookup before App Review.
- The `Overlay` cases and `FrameGate.settle`: sheets and popovers are not in
  the canvas view, so nothing needs holding.
- Both halves of #162: the colour panel and lasso menu draw outside the canvas
  view, and a system-stopped capture no longer exists.
- The canvas crop on the Mac becomes the whole frame (`CanvasCrop` shrinks to
  nothing).

Kept: the `recrop` hold matters only while crops exist; rotation still rebuilds
the encoder session at the new size. ReplayKit stays relevant to W6 (whole
screen), which needs a Broadcast Upload Extension regardless.

To check in the probe: whether the lasso selection marquee and the ruler are
drawn inside `PKCanvasView` (then they stream, as they should) or in another
window (then they do not).

## 7. Running it

Build and install the Debug app, then launch with a source:

```bash
just pad-run "<iPad name>"
just pad-probe "<iPad name>" hierarchy   # or: layer, replayKit
just pad-probe-pull "<iPad name>"        # copies the CSVs to spike/canvas-render/runs/
swift spike/canvas-render/analyse.swift spike/canvas-render/runs/<file>-frames.csv
```

A third argument sets the render scale: `just pad-probe "<iPad name>" hierarchy 0.5`
halves the render size, to see the trade-off if native size misses the
main-thread bar.

### Device steps (Jon)

1. **Probe, about 15 minutes.** Launch with `hierarchy`, pair with the Debug
   Mac app, draw a long slow stroke and watch the Mac: ink should grow under
   the pencil, not appear on lift. Draw with the lasso and the ruler visible.
   Repeat with `layer`. If neither shows ink mid-stroke: NO-GO, stop here.
2. **Hour on ReplayKit.** Charge to 100%, brightness at half, launch with
   `replayKit`, unplug, draw with `spike/canvas-render/drawing-script.md` for an
   hour. Pull the CSVs.
3. **Hour on the renderer.** Same again with the method that passed step 1.
4. Run `analyse.swift` on both and fill §8.

## 8. Results

**2026-10-03, NO-GO.** Probed on the 2020 iPad Pro (A12Z) against the Debug Mac app.
The hour runs were not done.

- `hierarchy` at full size: the Mac share window stuttered at a visibly lower
  frame rate than ReplayKit; the iPad felt normal.
- `hierarchy` at half size: stuttered on both the Mac and the iPad, so image
  size is not the cost. The likely cause is `drawHierarchy` itself taking a
  synchronous snapshot every display frame on the main thread; the probe CSVs
  could not be copied off the iPad over Wi-Fi, so this is unmeasured.
- `layer` was not tried, and whether ink showed mid-stroke was not recorded.

Abandoned rather than tuned: the cost of tuning an unproven method per iPad
model outweighed the gain. §11 item 2 of `specs/wireless-product.md` stays open.

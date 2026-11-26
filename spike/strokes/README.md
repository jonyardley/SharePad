# Stroke spike (throwaway)

Answers [#217](https://github.com/jonyardley/SharePad/issues/217): **can the Mac draw
the iPad's ink faithfully enough to share, and can we capture a stroke live while the
pen is still down?** Measurement code only. It has its own Xcode project and must
never be merged into either shipping app.

```text
spike/strokes/
  Pad/          iPad app: PKCanvasView, a passive recogniser that logs live Pencil points, Snapshot button
  Render/       Mac CLI stroke-render: renders saved drawings with PencilKit on macOS and diffs them
  project.yml   xcodegen spec for the iPad app only
  test-page.md  what to draw, in order
  justfile      every command below
```

## What gets recorded

Each session is a folder `session-<time>/` in the app's Documents:

- `strokes.jsonl`: one JSON object a line. `begin`/`pts`/`end` per pen-down with the
  live coalesced points (x, y, time, force, max force, azimuth, altitude), a full
  `PKDrawing` on every drawing change, and a `snap` entry per Snapshot.
- `snap-N-ipad.png`: the iPad's own render of the visible area at Snapshot time.

## What the Mac does

`stroke-render <session>` writes `mac/report.md` and PNGs:

1. **iPad vs Mac**: renders the snapshot's `PKDrawing` on macOS, same rect and
   scale, and pixel-diffs it against the iPad's PNG. Answers "does PencilKit draw
   the same on both".
2. **PencilKit vs rebuilt**: pairs each pen-down with the stroke PencilKit added,
   fits a width-against-force model per ink, rebuilds every stroke from the live
   points alone and diffs that against PencilKit's. Answers "are the live points
   enough". Only meaningful before the first eraser, lasso or undo.
3. Live timing (pen lift to drawing change) and wire cost (points a second).

Pencil, watercolour and crayon texture comes from each stroke's random seed, so the
rebuild borrows PencilKit's seed. On the wire the seed would ride with the stroke
end. Without it, those inks differ by grain alone (about 14% of ink pixels in the
self-test); with it, about 1%, all on pencil edges.

## Running it

From `spike/strokes`. Mac only, no iPad:

```bash
just selftest           # every ink draws, then a fake session end to end
```

On the iPad (needs `SHAREPAD_TEAM_ID`, the iPad unlocked and trusted):

```bash
xcrun devicectl list devices     # note the iPad's name
just pad-run "<iPad name>"       # build, install, launch
```

Draw [test-page.md](test-page.md). Then:

```bash
just pull "<iPad name>"          # every session lands under runs/
ls -R runs | grep session-       # find the newest session folder
just render runs/<path to session-...>
```

Open `runs/<session>/mac/report.md` and the PNGs beside it.

## Known quirks

- PencilKit on macOS traps in `CFEqual` on a background queue when the process has
  no bundle identifier. `Render/Info.plist` is linked into the binary
  (`-sectcreate __TEXT __info_plist`) to give it one.
- **New session** on the iPad clears the canvas and starts a fresh folder.

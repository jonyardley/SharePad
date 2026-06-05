# SharePad landing page

A single, dependency-free `index.html` served via **GitHub Pages**. Design is
derived from the app icon (indigo→periwinkle gradient, sky-blue iPad glyph, the
flat 45° long-shadow motif).

## GitHub Pages

Live at **https://jonyardley.github.io/SharePad/**, served from `main` / `/docs`
(Settings → Pages). No build step — edits publish on push to `main` within a
minute or two. (Add a custom domain on that settings page if you ever want one.)

## The demo

The `#demo` section shows a **still** (`docs/assets/demo.jpg`) of SharePad live in
a Google Meet call. The still is the placeholder for a **motion demo** — record
the plug-in → window → share flow, export a GIF or MP4 to `docs/assets/demo.gif`,
and swap the `<img src="assets/demo.jpg">` in the `#demo` section (there's a marker
comment beside it). Motion is the stronger pitch; the still holds the spot until
then.

## The download button

Both "Download" buttons point at
`https://github.com/jonyardley/SharePad/releases`, which always renders (even with
zero releases — unlike `/releases/latest`, which 404s until the first release
exists). They become real downloads only once you publish a **signed + notarized**
release with a `.dmg` asset attached (Developer ID signing → Hardened Runtime →
`notarytool` → staple). Once releases exist, the newest is the top item there.

## Local preview

```bash
python3 -m http.server 4599 --directory docs
# open http://localhost:4599
```

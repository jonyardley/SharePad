# SharePad landing page

A single, dependency-free `index.html` served via **GitHub Pages**. Design is
derived from the app icon (indigo→periwinkle gradient, sky-blue iPad glyph, the
flat 45° long-shadow motif).

## Enable GitHub Pages (one-time)

1. Repo → **Settings → Pages**.
2. **Source:** "Deploy from a branch".
3. **Branch:** `main`, **folder:** `/docs`. Save.
4. Site goes live at `https://jonyardley.github.io/SharePad/` within a minute or
   two. (Add a custom domain on the same page later if you want one.)

No build step — edits to `docs/index.html` publish on push to `main`.

## Add the demo (highest-impact next step)

The strongest asset is a screen recording of the **plug-in → window → share**
flow. Record it, export a GIF or MP4 to `docs/assets/demo.gif`, then replace the
hero `.stage` mockup (or add a section) — see the `▸▸ ADD YOUR DEMO HERE` comment
in `index.html`. The demo *is* the pitch.

## The download button

Both "Download" buttons point at
`https://github.com/jonyardley/SharePad/releases/latest`. They resolve to a real
download only once you publish a **signed + notarized** release with a `.dmg`
asset attached (Developer ID signing → Hardened Runtime → `notarytool` → staple).
Until then the link simply lands on the releases page.

## Local preview

```bash
python3 -m http.server 4599 --directory docs
# open http://localhost:4599
```

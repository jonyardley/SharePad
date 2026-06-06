# SharePad landing page

A single, dependency-free `index.html` served via **GitHub Pages**. Design is
derived from the app icon (indigo→periwinkle gradient, sky-blue iPad glyph, the
flat 45° long-shadow motif).

## GitHub Pages

Live at **https://sharepad.co/**, served from the **`gh-pages`
branch** (root) — Settings → Pages. No build step. The `.github/workflows/pages.yml`
workflow rsyncs `docs/` → `gh-pages` on every push to `main` that touches `docs/**`,
so edits publish within a minute or two. To redeploy without a content change, run
the **Deploy Pages** workflow manually (Actions → Run workflow). The release
workflow publishes `SharePad.dmg` + `appcast.xml` to the same branch separately, so
the deploy leaves those two files untouched.

The custom domain is set by **`docs/CNAME`** (not via the Settings UI). Because the
deploy rsync runs with `--delete`, a CNAME set through Settings → Pages would be
wiped on the next deploy; keeping it in `docs/` makes it part of the synced source,
so GitHub auto-detects `sharepad.co` on every publish.

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

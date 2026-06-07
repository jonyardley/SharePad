# Download-URL Hardening — Spec

> Status: **accepted** (2026-06-07). Sibling: `specs/distribution.md` (release
> pipeline this modifies) and `specs/licensing.md` (the sell-the-build model this
> supports). Decisions in §5/§6 resolved; implemented in the same PR.

## 1. Problem & goal

The prebuilt DMG **must** stay publicly downloadable — Sparkle's appcast
(`SUFeedURL`) names the current DMG URL and auto-updates break if it's gated.
But today that URL is the **stable, guessable** `https://sharepad.co/SharePad.dmg`,
so a casual visitor can type it in and any shared link keeps working forever.

We can't make the file private (and per `specs/licensing.md` §2, *Enforcement:
None* — we don't try). The goal is a **funnel**, not a gate:

- Stop **casual discovery** — guessing `…/SharePad.dmg` should fail.
- Make **shared/leaked links rot** — a direct link should stop working at the
  next release.
- Keep **auto-updates working** for every existing install.

Accepted ceiling: anyone who reads the public `appcast.xml` can still find the
current URL. That's unavoidable with Sparkle and fine — it's a tiny, technical
minority; everyone else is funnelled to checkout.

## 2. Approach

**Version the DMG filename per release** so the published file is e.g.
`SharePad-1.0.6.dmg`, and **stop publishing the stable `SharePad.dmg`** (so it
404s). The appcast enclosure points at the versioned name; humans never see it.

- Casual `…/SharePad.dmg` guess → **404**.
- A link shared today (`SharePad-1.0.6.dmg`) → **404 after 1.0.7 ships**, because
  the old file is removed from `gh-pages` on each release.
- Sparkle is unaffected: it reads the appcast fresh at update time and follows
  whatever enclosure URL it finds.

This is also *more* aligned with how `generate_appcast` is designed (it expects
versioned filenames); the single stable `SharePad.dmg` was the non-standard part.

## 3. Mechanism today (what changes)

`release.yml` → `just release` builds `.build/SharePad.dmg`; `just sparkle-appcast`
copies it into `.build/appcast/`, and `generate_appcast`:

- matches the release-notes file to the DMG **by basename** (`SharePad.md` ↔
  `SharePad.dmg`) for `--embed-release-notes`;
- writes `appcast.xml` with enclosure URL = `DOWNLOAD_URL_PREFIX` + the DMG's
  filename.

The publish step copies the DMG + appcast to `gh-pages` as the stable
`SharePad.dmg`. The GitHub Release **also** attaches `appcast.xml` so old v1.0.x
installs (whose `SUFeedURL` is `releases/latest/download/appcast.xml`) keep
updating.

**Changes required (all in `release.yml` / `justfile`, no app code):**

1. Derive `DMG_NAME="SharePad-${RELEASE_VERSION}.dmg"`.
2. Name the built/copied DMG `$DMG_NAME` **and** the notes file
   `SharePad-${RELEASE_VERSION}.md` so `generate_appcast`'s basename match still
   works. (Otherwise release notes silently drop out of the appcast.)
3. Publish step: copy `$DMG_NAME` to `gh-pages`, `git rm` any previous
   `SharePad*.dmg` **and** the legacy `SharePad.dmg`, commit appcast + new DMG in
   one atomic gh-pages commit. (Keeping only the current DMG is what makes old
   links rot; it also stops `gh-pages` growing unbounded.)
4. Leave both appcast locations regenerated as today — both inherit the versioned
   enclosure automatically.
5. **`pages.yml`** docs-sync uses `rsync --delete` and excludes only `SharePad.dmg`
   + `appcast.xml` from deletion. Widen to `SharePad*.dmg` or the next docs push
   **deletes the versioned DMG** (breaking downloads *and* auto-update). This is
   the easiest-to-miss trap in the change.

## 4. Compatibility analysis (the load-bearing part)

- **Existing installs (current + old v1.0.x):** on next check they fetch the
  *fresh* appcast (gh-pages or the Release-attached copy — both regenerated with
  the versioned enclosure) and download the versioned DMG. **No break.**
- **No mid-flight gap:** the new appcast and the new versioned DMG land in the
  **same** gh-pages commit, and the old `SharePad.dmg` is removed in that same
  commit. At no instant does a live appcast point at a missing file.
- **EdDSA signature:** signs DMG *content*, not its URL/filename — renaming is
  signature-safe.
- **First rollout:** the release that introduces this removes `SharePad.dmg`.
  Any link shared before then dies — intended.

## 5. Decisions (resolved 2026-06-07)

1. **History:** **latest-only.** Maximises link rot and keeps gh-pages small. No
   Sparkle deltas are configured, so version history isn't needed.
2. **Name:** **version + short content hash** — `SharePad-1.0.6-9f3a.dmg`. The
   hash makes even the *next* version's URL unguessable (a plain version is
   predictable).
3. **Thanks-page link:** resolved by §6 — the page reads the appcast, so the
   pipeline does **not** rewrite it.

## 6. The thanks-page coupling — RESOLVED via appcast lookup

Hardening the DMG name breaks any hardcoded `https://sharepad.co/SharePad.dmg`
link (the merged #84 has one). Two pipeline-side options were considered and
**rejected**:

- **(a) pipeline rewrites the thanks-page `href` each release** — *fragile*:
  `pages.yml` re-syncs `docs/` to gh-pages on any later docs push and would
  clobber the rewrite back to whatever is in `docs/` on `main`.
- **(b) stable `/download` redirect** — reintroduces a guessable, shareable URL,
  defeating the point.

**Chosen:** the thanks page **resolves the download URL from `/appcast.xml` at
load** (same-origin `fetch`, parse `<enclosure url>`), falling back to the GitHub
releases page. No hardcoded filename, nothing for the pipeline to rewrite, no
`pages.yml` clobber. Works before *and* after this change (resolves to the stable
name today, the versioned name after). Shipped in **PR #86** — must merge before
this PR so the live thanks page never points at the retired stable URL.

## 7. Verification

- **Local:** run `just sparkle-appcast` with a versioned DMG; confirm the appcast
  enclosure uses the versioned URL and the embedded release notes are present
  (basename match held).
- **Cannot fully dry-run in CI:** the appcast + publish steps are gated on a tag
  push (`workflow_dispatch` skips them). So the first real proof is the **next
  tagged release** — verify: (1) `…/SharePad.dmg` 404s; (2) the versioned URL
  200s; (3) an existing install auto-updates; (4) the thanks page download works.
  Treat the first release after this lands as a **monitored** one.

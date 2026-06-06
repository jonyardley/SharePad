# SharePad — Working Backlog

> Created 2026-06-06 from the post-production review; updated as items land. The
> single "what's left to get the app in the best place" list. Each item:
> **problem · why · approach · status · source**. Tick the box when done; move
> resolved items to the bottom log.
>
> Companion docs: `DESIGN.md` (§10 edge cases, §12 open questions) is the source of
> truth for *what/why*; `specs/<feature>.md` holds per-feature detail.

---

## P0 — Verification debt (blocks the next release)

Shipped as code but touch capture/permission/window, so per `CLAUDE.md` → Testing
they are **not "done" until run on a real iPad in a real meeting app**. No hardware
was available at implementation time.

- [ ] **Rotation keeps window placement** (#69). Show the window, move it, rotate the
  iPad → keeps your position; survives relaunch. *`ShareWindowController.updateSize`.*
- [ ] **Normal connect still works end-to-end** (#69). Plug in → live → shares cleanly
  in Zoom **and** browser Meet/Teams; no mic prompt. *`CaptureController.configureAndRun`.*
- [ ] **Restricted-camera copy** (#69). MDM/Screen-Time device shows "blocked by a
  device policy" + no Open-Settings button; confirm plain `.denied` unchanged.
- [ ] **WindowSharing exclusion** (#70). Open the About panel / a Sparkle dialog
  mid-"call" → neither is pickable in a screen-share picker, only the feed.
- [ ] **Mid-call disconnect signal** (mid-call PR). Live + window shown in a real
  call → unplug: popover banner + alert status symbol appear; replug clears both.
  Window hidden → unplug: silent. *`specs/mid-call-disconnect.md`.*

---

## P1 — Real product gaps

*(empty — mid-call disconnect resolved; see Done log. Locked-iPad hint deferred, see
Deferred.)*

---

## P2 — Quality / performance

- [ ] **Idle-but-connected CPU: throttle the data output (issue #23).** Design
  complete (`specs/idle-throttle.md`) — the real win is dropping the data-output
  *connection* when window-hidden + popover-closed, not an early-return; the
  `awaitFrame` watchdog re-enable is the landmine. **Tier 3 → needs on-iPad
  measurement before coding.** *Source: review + spike 2026-06-06.*

---

## Deferred (decided, not doing now)

- **Locked-iPad "unlock" hint.** Spike (2026-06-06) confirmed lock is **not reliably
  detectable on macOS** — session stays running and delivers valid-but-black frames;
  interruption APIs are iOS-only; no CMIO/`AVCaptureDevice` lock property. Only a
  fuzzy pixel heuristic could infer it (false-positives on dark drawings). Recorded
  in `DESIGN.md` §10 so it isn't re-investigated expecting a clean API.

---

## Notes / non-items

- **Sparkle key rotation (review #1): resolved.** Rotated in v1.0.3; the one external
  user on ≤v1.0.2 has been told to reinstall. No further action.

---

## Done log

- 2026-06-06 — Review findings #2–#9 (simplicity / capture / permissions) shipped (#69).
- 2026-06-06 — WindowSharing hardened against windows that never become key (#70).
- 2026-06-06 — Mid-call disconnect signal: transient banner + alert status symbol
  (#71). Resolves DESIGN.md §12.4. *`specs/mid-call-disconnect.md`.*
- 2026-06-06 — Split `AppModelTests` into `AppModelTestCase` (shared fixtures) +
  Connect/Lifecycle/ShareLost suites; clears the `type_body_length` warning (lint now
  0 violations), 61 tests unchanged.

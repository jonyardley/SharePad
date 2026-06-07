# SharePad — Working Backlog

> Created 2026-06-06 from the post-production review; updated as items land. The
> single "what's left to get the app in the best place" list. Each item:
> **problem · why · approach · status · source**. Tick the box when done; move
> resolved items to the bottom log.
>
> Companion docs: `DESIGN.md` (§10 edge cases, §12 open questions) is the source of
> truth for *what/why*; `specs/<feature>.md` holds per-feature detail.

---

## P0 — Verification debt — ✅ CLEARED (2026-06-06)

All on-iPad checks below ran green, **and** the runbook Step 6 smoke test of the
released, notarized v1.0.5 DMG passed (no Gatekeeper warning, camera-only prompt,
feed appears). v1.0.5 is verified shipped — nothing here blocks a release.

- [x] **Rotation keeps window placement** (#69). ✅ verified 2026-06-06. Minor: window
  drifts away from corners on rotation because `centeredResizeOrigin` keeps the
  content centre fixed — by design (matches Xcode / Preview); switch to nearest-corner
  anchoring if it bites in real use.
- [x] **Normal connect still works end-to-end** (#69). ✅ verified 2026-06-06 (no mic prompt).
- [x] **Restricted-camera copy** (#69). Accepted as shipped — verification needs a
  managed (MDM/Screen-Time) device we don't have; the plain `.denied` path is
  verified and the `.restricted` branch is a pure reducer case with unit coverage.
- [x] **WindowSharing exclusion** (#70). ✅ verified 2026-06-06 — feed picks correctly.
  Found Sparkle's "Check for Updates" dialog was share-pickable (observer race);
  **fixed in #74** (synchronous `addObserver`). Re-verify the picker on the next
  iPad pass.
- [x] **Mid-call disconnect signal** (#71). ✅ verified 2026-06-06 (banner + alert
  appear on unplug-with-window; silent when window hidden).

---

## P1 — Real product gaps

*(empty — mid-call disconnect resolved; see Done log. Locked-iPad hint deferred, see
Deferred.)*

---

## P2 — Quality / performance

*(empty — all known items resolved or deferred; see Done log / Deferred.)*

---

## Deferred (decided, not doing now)

- **Data-output idle throttle (issue #23): WON'T FIX (measured).** On-iPad, in the
  exact state it would optimise (iPad connected, window hidden, popover closed),
  SharePad measured **~0.7–0.8% CPU / 0.0% GPU** sustained (Activity Monitor). The
  ~4–6% in DESIGN §9 is the *live-active* cost, not this hidden-armed state. <1% win
  vs ~60 min of `AVCaptureSession` reconfiguration touching the watchdog → not worth
  it. Full rationale + retained design in `specs/idle-throttle.md`.
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
- 2026-06-06 — Fixed the WindowSharing observer race vs the share picker (#74);
  synchronous `addObserver` so the sweep runs in the same runloop tick.
- 2026-06-06 — **Shipped + verified v1.0.5** (#75 changelog → tag → notarized DMG +
  signed appcast; auto-update self-consistent). Runbook Step 6 smoke test of the
  released bundle passed on-iPad — release proven. Review fully closed.

# SharePad — Working Backlog

> Created 2026-06-06 from the post-production review. This is the single "what's
> left to get the app in the best place" list. Each item: **problem · why · approach
> · status · source**. Tick the box when done; move resolved items to the bottom log.
>
> Companion docs: `DESIGN.md` (§10 edge cases, §12 open questions) is the source of
> truth for *what/why*; `specs/<feature>.md` holds per-feature detail. Findings 2–9
> from the review shipped in [#69](https://github.com/jonyardley/SharePad/pull/69).

---

## P0 — Verification debt (blocks the next release)

These shipped as code in #69 but touch capture/permission/window, so per
`CLAUDE.md` → Testing they are **not "done" until run on a real iPad in a real
meeting app**. No hardware was available at implementation time.

- [ ] **Rotation keeps window placement (#6).** Show the share window, move it,
  rotate the iPad. The window must keep your chosen position (re-centred on the
  same point, not reset) and the placement must survive an app relaunch.
  *Source: review #6 / `ShareWindowController.updateSize`.*
- [ ] **Normal connect still works end-to-end (#2).** Plug in → live feed → shares
  cleanly in Zoom **and** a browser Meet/Teams. The #2 change only alters the
  branch where the data output can't be added; confirm the happy path is unchanged
  and no mic prompt appears. *Source: review #2 / `CaptureController.configureAndRun`.*
- [ ] **Restricted-camera copy (#3).** On a device where camera is blocked by
  MDM/Screen Time, the popover shows "Camera access is blocked by a device policy."
  and **no** Open-Settings button. Hard to reproduce without a managed device; at
  minimum confirm the plain `.denied` path is unchanged. *Source: review #3.*

---

## P1 — Real product gaps (open design questions)

- [ ] **Mid-call disconnect is a silent hide.** When the iPad vanishes mid-share,
  `reconcile` → `window.hide()` + status dims, with no signal to the user — who may
  be presenting. *Why:* a silent black/disappeared share mid-call is confusing.
  *Approach:* a brief user notification (or a transient popover state) on
  unexpected teardown while `isWindowVisible`. Decide notification vs in-window
  banner. *Source: `DESIGN.md` §12.4 / §10.*
- [ ] **Locked-iPad feed is an unexplained black frame.** A locked iPad transmits
  black; the user sees a dead share with no reason. *Why:* looks like a bug.
  *Approach:* if lock state is detectable (or inferable from a sustained
  all-black/no-frame while the session reports running), surface a "Unlock your
  iPad" hint in the popover. Needs investigation into what's actually detectable.
  *Source: `DESIGN.md` §10.*

---

## P2 — Quality / performance (review observations, not yet ticketed)

- [ ] **Idle-but-connected CPU: throttle the data output when nothing needs it.**
  While an iPad is connected the `AVCaptureVideoDataOutput` delegate runs for every
  frame even when the share window is hidden **and** the popover is closed. Its
  output is only consumed by: live video-size detection (needs window visible),
  the popover thumbnail (popover open), and the `awaitFrame` watchdog (during
  connect/restart). *Why:* wasted CPU/battery in the common "armed but not
  presenting" state. *Approach:* gate or downsample the delegate work when neither
  the window is visible nor the popover open — without breaking instant show or the
  watchdog. Measure first; relates to the earlier idle-CPU work (DESIGN.md §9 notes
  the rotation/thumbnail output at ~4–6%). *Source: review Performance section.*
- [ ] **Harden `WindowSharing` against the becomes-shareable-without-key gap.**
  Non-feed windows are excluded (`sharingType = .none`) at launch and on
  `didBecomeKeyNotification`. A window that becomes shareable *without ever becoming
  key* would slip through and be pickable in a call. *Why:* a stray window (About
  panel, a future dialog) shared in place of the iPad is a privacy/UX failure.
  *Approach:* set `.none` at window-creation for all non-feed windows, and/or also
  sweep on `NSWindow.didUpdateNotification` / app `didBecomeActive`. *Source: review
  Security + `CLAUDE.md` gotchas (documented known gap).*
- [ ] **Split `AppModelTests` to clear the lint warning.** The test file trips
  `type_body_length` (259 lines; warning, not error — CI stays green). *Approach:*
  split along behaviour, e.g. `AppModelConnectTests` (auto-connect/retry) vs
  `AppModelLifecycleTests` (restart/reconcile/popover). Low priority. *Source:
  review #7 follow-on.*

---

## Notes / non-items

- **Sparkle key rotation (review #1): resolved.** Key rotated in v1.0.3; the one
  external user on ≤v1.0.2 (who trusts the leaked key) has been told to reinstall.
  No further action. *Source: review #1 / Sparkle incident.*
- All eight code findings (#2–#9) are merged-pending in
  [#69](https://github.com/jonyardley/SharePad/pull/69) (Superpowers review: approved).

---

## Done log

<!-- Move items here with date + PR when complete, e.g.:
- 2026-06-06 — Review findings #2–#9 shipped (#69). -->

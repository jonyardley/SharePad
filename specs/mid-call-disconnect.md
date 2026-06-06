# Mid-call disconnect signal

## Problem

When the iPad disconnects while its share window is up, `reconcile()`'s `.teardown`
branch silently hides the window and the status item drops to idle. A user who's
mid-call gets no signal that their share just died (DESIGN.md §10 / §12.4).

## Approach

Surface a **transient, self-expiring signal** — not a new steady `AppState` case,
because "the share just dropped" is an event, not a state the app rests in.

- **Decision stays in the state machine, not the view.** `reconcile()` reads
  `isWindowVisible` *before* `window.hide()` clears it; a teardown while the window
  was up is a lost share, an idle unplug (window hidden) is silent.
- **Two surfaces** (DESIGN.md design-system: menu bar strips colour → symbol swap):
  - **Popover banner** — `shareLostBanner` in `PopoverView`, the primary surface.
  - **Status-item alert symbol** — `exclamationmark.triangle.fill` takes precedence
    over idle/live, so a user with the popover closed (the common mid-call case)
    still sees it. This is a deliberate *third, transient* status-item state on top
    of the documented idle/live pair.
- **One-shot + auto-expire.** `shareLostSignal` is raised by `raiseShareLost()` and
  cleared after `shareLostDuration` (10s) via `shareLostDismissTask`, so a stale
  banner/badge doesn't linger. Cleared early by a **reconnect** (`connectOnce`'s
  `.live` calls `dismissShareLost()`) or the banner's **Dismiss** button.

## Why not the alternatives

- **`UNUserNotificationCenter`** — adds a second system authorization prompt, which
  breaks the app's deliberate "camera and nothing else" permission posture, and is
  easily missed under Focus/Do-Not-Disturb (which presenters run). No entitlement is
  needed for the chosen approach.
- **`NSAlert` / floating panel** — steals focus from the meeting window mid-call,
  and a new top-level window is another surface the `WindowSharing` guard must
  exclude. The banner + status swap stay inside existing surfaces.

## Key decisions

- Tier 2 (a new control following existing patterns; **no** permission/entitlement
  change, so no domain-sensitivity tier bump).
- The false-positive guard is structural: only a teardown that interrupts a *visible*
  share signals; intentional unplug while idle is silent.

## Tests (pure-logic / fake-driven, no hardware)

`AppModelTests`: teardown-while-sharing raises; teardown-while-hidden is silent;
reconnect clears; dismiss clears; auto-expire clears (drives the injected `sleep`).

## Manual verification (owed, per CLAUDE.md Testing)

- [ ] iPad live + window shown in a real call → unplug. Banner appears in the
      popover and the menu-bar symbol flips to the alert; replug clears both.
- [ ] iPad live + window hidden → unplug. No banner, no alert (silent).

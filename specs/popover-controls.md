# Phase 3 — Popover controls (spec)

> Tier 3 — touches the popover, the window/share model, and the login item. Builds
> on Phase 2. See DESIGN.md §3 (window behaviour/toggles), §4 (popover surfaces),
> §9 (Phase 3), §10 (keep-on-top gotcha), §11 (preference-persistence tests).

## Problem

The popover is a placeholder (app name + Quit). Phase 3 turns it into the control
surface: manually show/hide the share window, control auto-show-on-connect,
keep-on-top, and launch-at-login. (Directly delivers [#6](https://github.com/jonyardley/SharePad/issues/6).)

## Scope

**In:**
- **Show / Hide window button** (#6) — enabled when an iPad is connected.
- **Auto-show-on-connect toggle** (#6) — when off, connecting does *not* auto-open
  the window (you open it with the button). Default on.
- **Keep window on top toggle** — window floats above others (browser-Meet escape
  hatch, DESIGN §10). Default off.
- **Launch at login toggle** — `SMAppService.mainApp`, reflecting real system state.
- **`Preferences`** (UserDefaults) for the toggles, plus the **test target** + unit
  tests (Preferences persistence + the deferred `contentSize` aspect math) — closes
  [#9](https://github.com/jonyardley/SharePad/issues/9).

**Out (deferred → follow-up):**
- **Live thumbnail** in the popover — needs the two-preview-layer resolution
  (DESIGN §5.2) + popover open/close lifecycle handling; higher risk. Deferred to
  keep Phase 3 focused on the requested controls.
- **Device picker** (multiple muxed sources) — single iPad is the norm; DESIGN §10
  edge case. Deferred.

## Approach

- **`Support/Preferences.swift`** — `UserDefaults`-backed `autoShowOnConnect`
  (default `true`), `keepOnTop` (default `false`). Small and testable.
- **`Support/LaunchAtLogin.swift`** — wraps `SMAppService.mainApp`
  register/unregister + `status` (the toggle reflects/sets the system login-item
  state, not a UserDefault).
- **`AppModel`** (`@Observable @MainActor`): holds Preferences + window-visibility
  state. `reconcile`: on connect, present the window only if `autoShowOnConnect`
  (else just track the device → button enabled). Intents: `toggleWindow()`,
  `setAutoShow(_:)`, `setKeepOnTop(_:)`, `setLaunchAtLogin(_:)`.
- **`ShareWindowController`** — `keepOnTop` sets `window.level = .floating` /
  `.normal`; expose `isVisible`.
- **`UI/PopoverView`** — the controls bound to `AppModel` (`Toggle` + `Button`),
  enabled/disabled by connection state; a small `Theme` for spacing now that the
  popover has real content.
- **Test target** `SharePadTests` (project.yml + `scheme.testTargets` + a `just
  test` recipe); re-add `Tests` to `.swiftlint.yml`. Tests: Preferences
  persistence + `contentSize` aspect math.

## Key decisions

1. **Controls first; live thumbnail + device picker deferred** (the thumbnail's
   two-preview-layer risk + popover lifecycle is its own chunk).
2. Launch-at-login via `SMAppService.mainApp` (macOS 13+), reflecting real state.
3. Stand up the **test target now** — Preferences is "preference persistence," a
   DESIGN §11 test target — and close #9.
4. Keep-on-top = window level float (DESIGN §3/§10 escape hatch).

## Open questions

1. **Launch-at-login default.** DESIGN §3 says "on by default," but auto-registering
   a login item on first launch can surprise. **Proposed: default off**, user opts
   in (toggle reflects real `SMAppService` status). Confirm.
2. `SMAppService` status/permission nuances on the current macOS — verify at
   implementation.

## Testing

- **Unit (new target):** Preferences persistence (set/get/defaults); `contentSize`
  aspect math (portrait/landscape/clamp/zero).
- **Manual:** toggles persist across relaunch; auto-show off → window doesn't
  auto-open but the button does; keep-on-top floats over other apps; launch-at-login
  appears in System Settings → General → Login Items.

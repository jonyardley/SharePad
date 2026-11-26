# SharePad development guidelines

> The current public release is the one `gh release list --limit 3` marks
> Latest, or the newest `v*` tag (`git tag -l 'v*' --sort=-v:refname | head -1`).
> The top section of `CHANGELOG.md` may not be released yet, and `review-*` tags
> are App Review pre-releases. The folders on disk are the layout; `DESIGN.md`
> §8 is headed as the target.

## Project overview

SharePad is a macOS menu-bar app that turns a USB-connected iPad into a clean,
aspect-locked, always-ready window you share in any video call's "Share window"
picker. Plug in the iPad, the window appears automatically, and the per-call
QuickTime ritual is gone. Primary use: live drawing and whiteboarding shown as
full shared content, not a webcam tile.

The approach is window-share, not virtual camera: for drawing, display size
beats selection convenience, and a virtual camera renders as a small webcam
tile ([`DESIGN.md` §2](DESIGN.md#2-approach--rejected-alternatives)). Don't
start a CoreMediaIO camera extension without reopening that decision.

## Commands

```bash
just gen           # xcodegen generate, run after editing project.yml
just build         # xcodebuild, debug
just run           # build + launch the app
just test          # Mac unit tests
just wire-test     # SharePadWire package tests
just pad-test      # iPad unit tests on the iOS Simulator
just fmt           # swiftformat .   (must pass before commit)
just lint          # swiftlint + swiftformat --lint (must pass before push)
just pre-review    # lint, Mac and wire tests, iPad tests if touched (must pass before review)
```

The `justfile` holds the rest (`just --list`). The Xcode project is generated
by xcodegen and git-ignored: edit `project.yml`, never the `.xcodeproj`. A diff
that hand-edits the project file is a blocker.

First-time setup:

```bash
brew install xcodegen just swiftformat swiftlint gitleaks
just install-hooks   # pre-commit and pre-push secret scans, once per clone or worktree
just gen && just run
```

Set `SHAREPAD_TEAM_ID` locally or every rebuild shows a keychain prompt (#177,
detail in `.claude/rules/licensing-distribution.md`).

## Architecture (Non-Negotiables)

1. **One session, one owner.** Exactly one `AVCaptureSession`, owned by
   `CaptureController`. Views and the popover observe it (attach preview
   layers, read published state); they never create, mutate or start it.
2. **State lives in `AppModel`; views are dumb.** App state (lifecycle, device,
   permission, toggles) lives in one `@Observable @MainActor` `AppModel`. Views
   render it and send intents. No capture or AV logic and no decisions in
   views: an `if` about device or permission state in a SwiftUI body belongs in
   the state reducer.
3. **The state machine is a pure, tested reducer.** `(permission, device list,
   session status) → AppState` is a pure function with no AVFoundation imports,
   so it is unit-testable without hardware. `CaptureController` is
   protocol-fronted so `AppModel` runs against a fake in tests.
4. **CMIO opt-in once, early.** Set
   `kCMIOHardwarePropertyAllowScreenCaptureDevices = 1` exactly once at
   startup, before discovery. It is process-global, so never toggle it per
   session. Without it discovery returns nothing, silently: check it first when
   the device list is empty.
5. **Video-only by construction.** Add the muxed input with
   `addInputWithNoConnections` and wire only the video connection. This keeps
   scope tight and avoids the Microphone TCC dialog that adding the muxed input
   naively triggers.
6. **Surface, don't swallow.** Every error state (`permissionDenied`, `failed`,
   device-vanished) has a UI surface in the popover, never a silent dead
   state. Optimistic UI (such as "window shown") must reconcile with the actual
   session status, not assume success.

### State boundary

| State kind | Where it lives |
|---|---|
| `AVCaptureSession` + active device | `CaptureController` (single owner) |
| Lifecycle / device / permission state | `AppModel` (`@Observable`) reducer |
| Window frame, keep-on-top, launch-at-login | `UserDefaults` (`Preferences`) |
| Live video frames | `AVCaptureVideoPreviewLayer` (GPU), never app state |

## Permissions and entitlements

- Camera only: `NSCameraUsageDescription` +
  `AVCaptureDevice.requestAccess(for: .video)`. Microphone is deliberately
  avoided (Non-Negotiable 5).
- No App Sandbox: it blocks the CMIO screen-capture opt-in, so enabling it gives
  an empty device list with no obvious cause. Ship un-sandboxed, which is why
  the Mac app is a Developer ID notarised direct download, not an App Store app
  (`specs/distribution.md`). Don't enable the sandbox without revisiting the
  `DESIGN.md` §6 caveats.

## Code style

- Run `just fmt` and `just lint` locally, not through CI round trips.
- No force-unwrap (`!`), `try!` or `as!` without a one-line written
  justification, the same bar as a Rust `unwrap()`. AVFoundation and CMIO calls
  return real errors; handle and surface them.
- Prefer first-party frameworks. Sparkle is the one third-party dependency
  (`DESIGN.md` §7, pulled in by `project.yml`); adding another is a flagged
  decision.
- `@MainActor` for UI and state; capture callbacks run off-main, then hop back
  to mutate `AppModel`.
- Comments follow the comment rule in `~/.claude/CLAUDE.md` (Writing, everywhere).

## Testing

Ship tests with new pure logic ([`DESIGN.md` §11](DESIGN.md#11-testing-strategy)):

- Unit-test the pure layer: the `AppState` reducer, preference persistence,
  aspect math, device selection.
- Capture is manual: AVFoundation can't be meaningfully unit-tested without an
  iPad. Each `DESIGN.md` §9 phase has a "verify by" line, the manual checklist.
- Done for a capture phase means the manual checklist was run, with the iPad,
  in a real meeting app; a green unit suite never proves it. If you can't
  reach hardware, say so and list what needs user verification.

## Specs

A change to the capture pipeline (CMIO opt-in and session setup included), the
state machine, permissions, entitlements, the window and share model, or a new
top-level capability gets a spec in `specs/<feature>.md` (problem, approach,
key decisions, open questions) and waits for go, whatever its size.
Everything else follows the plan rule in `~/.claude/CLAUDE.md` (Work).

## Code review

The `requesting-code-review` skill is SharePad's reviewer. It is user-level
(`~/.claude/skills/`), not in this repo; where it is missing, the global
fallback is `/code-review` at medium. The rest of review is in
`~/.claude/CLAUDE.md` ("Subagents, review and lane size").

- The gate is `just pre-review`: it must pass locally before the reviewer
  runs. Tell the reviewer "comment-policy violations are Blockers, not Nits"
  (the comment rule in `~/.claude/CLAUDE.md`).
- Open a tracked issue for anything deferred and link it in the pull request.
- Self-hosted runner: `testflight.yml` runs on the `sharepad-m4` Mac.
- **Sensitive surfaces**, which always get the second reviewer: wireless
  pairing and network trust
  (`Packages/SharePadWire/Sources/SharePadWire/Pairing/`, including the
  Keychain install ids in `PairingStore.swift` and `LinkGate`, plus
  `Rules/PairedDialCycle.swift` and `Rules/ListenerPlan.swift`), licence key
  validation (`Sources/SharePad/Licensing/`), the entitlements files
  (`Sources/*/*.entitlements`) and the permission flow
  (`Sources/SharePad/Support/Permissions.swift`).
- Small and docs-only pull requests get the review too, before leaving draft.
- **Agent files pin no model or effort.** Agents in `.claude/agents/` (today
  only `test-runner.md`, a mechanical row agent) leave both out of their
  frontmatter; the dispatcher names them on the call, from the global table.

## Always

1. Read [`DESIGN.md`](DESIGN.md) first: it is the source of truth for what we
   build and why, and the verified technical foundation. If a request
   contradicts it, flag the conflict before coding.
2. Work on a feature branch and open a pull request, never on `main` (it is
   seeded).
3. For any capture, permission or window change, verify on the actual iPad in
   a real meeting app before calling it done.

## After completing work

1. Update `DESIGN.md` if the design or decisions changed (especially the open
   questions and milestones sections).
2. Update this file if architecture or commands changed, and the matching file
   in `.claude/rules/` if a trap changed.
3. Resolve or re-flag any open question the work touched.

## Where the rest lives

Traps and the design system live in `.claude/rules/`:

- `capture.md`: capture and the share window (Mac `Capture/`, `Windows/`, `UI/`).
- `wireless-pairing.md`: Wi-Fi feed, pairing, network trust (`SharePadWire`,
  both apps' wireless code).
- `licensing-distribution.md`: licence keys, appcast feed, Debug signing
  (licensing, updater, workers, CI).
- `telemetry-whats-new.md`: opt-in diagnostics and What's new (`Diagnostics`,
  `WhatsNew`).
- `design-system.md`: spacing, colour and status item (both apps' `UI/`).

They load when a session whose folder is the worktree opens a matching file
with the Read tool, and usually for its helpers. A session in main reading a
worktree's files gets none, no helper can count on them, and a shell read
loads none: then read them by hand. Every rule binds either way.

Release signing and notarisation are env-driven: `specs/distribution.md`.

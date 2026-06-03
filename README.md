# SharePad

A macOS **menu-bar app** that turns a USB-connected iPad into a clean,
aspect-locked, always-ready **window** you share in any video call's "Share
window" picker. Plug in the iPad → the window appears automatically → pick it in
the call. No more per-call QuickTime ritual.

Primary use case: live drawing / whiteboarding shown as full shared content, not
a webcam tile.

> **Status: pre-implementation.** Design is complete; code starts at Phase 0.

## Docs

- **[DESIGN.md](DESIGN.md)** — comprehensive design spec: problem, architecture,
  state machine, the verified AVFoundation/CoreMediaIO capture foundation,
  milestones, edge cases, open questions. Source of truth.
- **[CLAUDE.md](CLAUDE.md)** — development guidelines: conventions,
  non-negotiables, gotchas, tier workflow.

## Approach

Window-share, **not** a virtual camera — for live drawing, full shared content
beats a small webcam tile. See
[DESIGN.md §2](DESIGN.md#2-approach--rejected-alternatives) for the trade-off.

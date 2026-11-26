---
paths:
  - "Sources/SharePad/UI/**"
  - "Sources/SharePadPad/UI/**"
  - "Sources/SharePad/App.swift"
---

# Design system

SharePad is a tiny utility, so the system is light, but it is still tokenised
and not littered with literals.

- **Spacing and radius are tokens, not literals.** Put padding, inset and corner
  values in a `Theme` enum (for example `Theme.Spacing.row`, `Theme.Radius.card`).
  Don't sprinkle `.padding(16)` or `cornerRadius: 12`. Genuine one-offs (a fixed
  control height) stay literal; don't force those into the scale.
- **Colours via semantic names**, not raw values. Prefer system materials
  (`.regularMaterial`, `NSVisualEffectView`) so the popover and window match macOS.
- **The status item has two states**: idle (`ipad.landscape`) and live
  (`ipad.landscape.badge.play`). A share lost mid-call shows only in the popover
  banner (`specs/mid-call-disconnect.md`; the alert symbol went in #115). It is a
  symbol swap, not a tint: the menu bar renders items monochrome and strips colour.

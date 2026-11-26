---
paths:
  - "Sources/SharePad/Support/Diagnostics.swift"
  - "Sources/SharePad/Support/Preferences.swift"
  - "Packages/SharePadWire/Sources/SharePadWire/Diagnostics/**"
  - "workers/telemetry/**"
  - "Sources/SharePad/State/WhatsNew.swift"
  - "Sources/SharePad/UI/WhatsNewWindow.swift"
  - "Sources/SharePad/UI/PopoverView.swift"
  - "Sources/SharePad/AppModel.swift"
  - "Sources/SharePad/App.swift"
  - "Tests/SharePadTests/AppModelDiagnosticsTests.swift"
  - "Tests/SharePadTests/WhatsNewTests.swift"
  - "Tests/SharePadTests/AppModelWhatsNewTests.swift"
---

# Telemetry and What's new

These are the traps in opt-in diagnostics and the What's new window, both of
which rest on promises the app makes to its users.

- **Telemetry is opt-in and off by default** (`specs/telemetry.md`). The privacy
  page promises nothing leaves the machine bar the update check, so
  `Preferences.diagnosticsEnabled` defaults false and `DiagnosticsReporter` sends
  only when the user turns it on. It is first-party MetricKit (crashes/hangs) plus
  five named non-fatals, never any content, licence, or device id. Never flip the
  default to on without a privacy-page change and a deliberate decision.
- **What's new shows only for versions in `WhatsNew.featureReleases`**
  (`specs/wireless-product.md` §9). A fresh install is `firstLaunchDate == nil`,
  not a missing `lastSeenVersion` (no install before W5a has one). It waits while
  the share window is up, then shows on a hide or once a lost-share notice clears.
  To see it in a Debug build: `open --env SHAREPAD_FEATURE_RELEASE=1.0.0` plus an
  older `lastSeenVersion` in the defaults. 1.3.0 is listed as the wireless release
  in every build.

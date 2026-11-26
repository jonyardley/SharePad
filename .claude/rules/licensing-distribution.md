---
paths:
  - "Sources/SharePad/Licensing/**"
  - "Sources/SharePad/Updater/**"
  - "Sources/SharePad/UI/LicenseWindow.swift"
  - "Packages/SharePadWire/Sources/SharePadWire/Pairing/PairingStore.swift"
  - "workers/licenses/**"
  - "workers/purchase-email/**"
  - "workers/appcast/**"
  - "scripts/check-key-pairing.mjs"
  - "Tests/SharePadTests/License*.swift"
  - "Tests/SharePadTests/SparkleUpdaterTests.swift"
  - ".github/workflows/**"
  - "project.yml"
  - "justfile"
---

# Licensing, updates and signing

These are the traps in licence keys, the update feed and build signing.
Release signing and notarisation are env-driven (`specs/distribution.md`), and
licence key validation is a sensitive surface that gets a second reviewer.

- **The appcast feed is the `appcast.sharepad.co` Worker, not gh-pages directly.**
  `SUFeedURL` points at the logging-proxy Worker (`specs/appcast-analytics.md`); it
  serves the gh-pages appcast unchanged and records install/version stats. The
  Worker must be deployed and serving before any build carrying that feed URL ships:
  otherwise new installs check a dead feed and can't auto-update. Changing
  `SUFeedURL` again strands existing installs on the old URL until they update, so
  treat it as permanent.
- **Licence keys are Ed25519 signatures** of the normalized buyer email (base64url);
  the app validates fully offline against the public key embedded in
  `Licensing/License.swift`: `LicenseValidatorTests.testProductionKeyIsConfigured`
  guards against shipping a *malformed/empty* embedded key (it can't catch a
  well-formed key that doesn't pair with the worker's private key: only the
  deploy-time E2E proves the pairing). The signing private key lives only in the
  Cloudflare Worker (and Jon's password manager), never in the repo.
- **Set `SHAREPAD_TEAM_ID` for Mac Debug builds too** (#177). The pairing store uses
  the file-based keychain, whose access list is tied to the app's signature. Ad hoc
  builds are a new app each time, so every rebuild shows the "wants to use your
  confidential information" prompt. With the team id set, `just build`, `run` and
  `test` sign with the Apple Development certificate and the prompt stops (after one
  Always Allow). Unset, as in CI, they stay ad hoc. Builds from inside Xcode stay
  ad hoc. Release signing is untouched: its requirement pins the bundle id and team,
  so Sparkle updates keep matching.

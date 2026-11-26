---
paths:
  - "Packages/SharePadWire/**"
  - "Sources/SharePadPad/**"
  - "Tests/SharePadPadTests/**"
  - "spike/wireless/**"
  - "Sources/SharePad/Capture/Wireless*.swift"
  - "Sources/SharePad/State/Pairing*.swift"
  - "Sources/SharePad/State/WirelessStatus.swift"
  - "Sources/SharePad/State/AppState.swift"
  - "Sources/SharePad/UI/Pairing*.swift"
  - "Sources/SharePad/UI/WirelessSectionView.swift"
  - "Sources/SharePad/UI/ForgetConfirmation.swift"
  - "Sources/SharePad/Windows/WindowSharing.swift"
  - "Sources/SharePad/AppModel.swift"
  - "Tests/SharePadTests/Wireless*.swift"
  - "Tests/SharePadTests/AppModelWireless*.swift"
  - "Tests/SharePadTests/LocalNetworkProbeTests.swift"
  - "project.yml"
  - "justfile"
---

# Wireless and pairing

These are the traps in the Wi-Fi feed, pairing and network trust. Pairing and
network trust are a sensitive surface: the paths are in `CLAUDE.md`, Code
review, and a change to them gets a second reviewer.

- **The iPad app streams only to paired Macs** (`specs/wireless-pairing-ui.md`).
  `PairedLink` runs `StreamSender` in paired mode: it dials only Bonjour services
  whose TXT `id` matches a pairing, with that pairing's key, and authenticates
  before its hello. Install ids on both ends come from `localDeviceID()` in the
  Keychain, never `identifierForVendor` or a per-launch UUID; `LinkGate` closes a
  link whose hello id differs from the paired one. An unreadable id fails closed:
  the iPad neither pairs nor dials, and says Wi-Fi sharing is off (#228).
- **The Bonjour TXT id is public, so a rogue can claim a paired Mac's id** (#229).
  `PairedDialCycle` skips a service that failed to connect (TLS, refused, timed
  out) until the link goes live, the link stops, that Mac's pairing changes, or
  every service with that id has been tried. Only then does a TLS failure count,
  once per cycle, after a settle interval of browsing (a stopped browser drops a
  pending settle; the next browse starts a full one). Don't feed `PairingHealth`
  from a single dial, and keep StreamSender passing every link phase change to
  the cycle. Remaining gaps: `specs/wireless-pairing-ui.md` key decision 8.
- **iPad frames leave only with a known canvas rectangle.** `CaptureContext` drops
  any frame without a layout or while a sheet or popover covers the canvas. New
  chrome that draws over the canvas must register an `Overlay` with the model.
- **Wireless ships in every Mac build from 1.3.0** (#192; the Debug-only gate of
  `specs/wireless-pairing-ui.md` decision 1 lifted with the iPad app's release).
  `NSLocalNetworkUsageDescription` and `NSBonjourServices` are in the target's
  `info:` in `project.yml`, and `just verify-app` fails any product missing either:
  without them the listener can't ask for local network access and no iPad finds
  the Mac. Any v* tag cut from main ships wireless to every user.
- **The Mac listener's keys are fixed when it is made.** `ListenerPlan` decides
  whether to listen (a code on offer, or something paired with Allow wireless
  iPads on) and with which keys; any change replaces the `NWListener`.
  Connections it already accepted carry on, so Forget must close them explicitly
  (`PairingBook`'s `dropConnections`).
- **The pairing window must never be shareable.** `PairingPanel` sets
  `sharingType = .none` before the window is first ordered on screen, then sweeps
  `WindowSharing`; its QR is a live pairing code.
- **Local network denial has no API on macOS** (TN3179). The only signal is the
  listener's Bonjour registration waiting with `kDNSServiceErr_PolicyDenied`
  (`LocalNetworkProbe`); the receiver takes the latest listener state as the
  truth (that wait means denied, `.ready` clears it). Unconfirmed on macOS 15
  hardware until the W1 manual check. macOS can't reset an app's Local Network
  choice, so never trigger the prompt on a machine whose answer you don't own.
- **A starting cable never takes the window from a receiving Wi-Fi feed**
  (`AppState.activeFeed`, `specs/wireless-product.md` §10, W4). That includes a USB
  restart on wake. W4b's `pause` now stops that flap: while the cable holds the
  window the Wi-Fi feed is paused and stops counting as receiving
  (`AppState.wirelessPause`, which also says why: cable or trial), and its picture
  is cleared, so unplugging shows a moment of black before a fresh keyframe, never
  an old drawing. If the cable's restart fails, the window goes to the paused Wi-Fi
  feed, which resumes; a later successful cable restart takes it back (#227).
- **Wireless TLS-PSK is TLS 1.2 only, and the suite must be pinned**
  (`specs/wireless-product.md` §6, open question 3). Network.framework's default
  PSK suite has no forward secrecy, so `LinkSecurity` pins ECDHE-PSK and a loopback
  test asserts it. The listener also cannot see which PSK a client used: trust a
  peer's id only after `LinkAuthentication.verify` and `LinkGate`, never from the
  hello alone.

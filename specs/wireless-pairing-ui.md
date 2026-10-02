# Wireless pairing UI and the TLS switch-over (W2b)

Status: built in W2b, hardware check pending. Parent spec:
[`wireless-product.md`](wireless-product.md) §6 (pairing), §9 (screens and
signposting), §10 (build plan).

## Problem

W2a put the pairing core in `SharePadWire` with no UI: codes, the TLS-PSK link,
the `authenticate` proof, `LinkGate` and pure reducers. W1's Mac receiver and
W3a's iPad app both still use the unauthenticated link, so any SharePad iPad on
the Wi-Fi can reach the Mac's share window. W2b puts pairing in front of both
users and moves both ends onto the paired link, so only an iPad the user paired
can stream.

## Approach

### Mac

- **`WirelessReceiver` owns the pairing reducers**, the way it already owns
  `ReceiverLink`: `PairingWindow`, `PairingBook` and `PairingHealth` run on its
  queue, beside the connections they act on. It publishes a sanitised view
  (`WirelessStatus.pairing`, `WirelessStatus.paired`) that never carries a secret.
  `AppModel` sends intents (`openPairing`, `closePairing`, `forget`,
  `setAllowWireless`) and renders what comes back.
- **Every connection goes through a `LinkGate`.** The first message must be
  `authenticate`; it is verified against the session's exported keying material,
  then the hello must match the pairing. Only an admitted paired peer reaches
  `ReceiverLink`, and only `ReceiverLink`'s live peer reaches the decoder. An
  admitted pairing peer reaches only `PairingWindow`.
- **The listener follows a pure plan** (`WirelessListenerPlan`): it runs only
  while the pairing window offers a code, or while something is paired and
  **Allow wireless iPads** is on. The plan names the keys it carries: the code
  only while offering, the paired secrets only while allowed. Network.framework
  fixes a listener's pre-shared keys when it is made, so a changed plan replaces
  the listener; accepted connections live on.
- **Bonjour carries the Mac's install id** in the TXT record (`id=<uuid>`), so an
  iPad can tell which of its paired Macs a service is without a handshake per
  guess. The id is the random Keychain-held `localDeviceID()`, not a hardware id.
- **Pairing window** (`PairingPanel`): its own `NSWindow`, not the popover, made
  unshareable (`sharingType = .none`) before it is first ordered on screen and
  swept again by `WindowSharing`. It shows the QR (CoreImage
  `CIQRCodeGenerator`) of `https://sharepad.co/pair#v1.<code>`, the typed code,
  a countdown, **Show a new code** once expired, and closes itself 2 seconds
  after **Paired with {iPad}**. What it shows comes from a pure presenter.
- **Popover "Wireless" section**: the empty state, the paired list (name, last
  connected, Forget, **Needs pairing again** with **Pair again…**), **Pair an
  iPad…** and **Allow wireless iPads**. Rows come from a pure presenter.

### iPad

- **`PairedLink`** replaces the W3a development link: a `StreamSender` in paired
  mode. It browses, keeps only services whose TXT id matches a paired Mac, orders
  them most recently used first, dials with that Mac's key, and sends
  `authenticate` before its hello. Unpaired Macs are never dialled.
- **Pairing screen**: Scan code (AVFoundation QR) or type the code; tries each
  advertising Mac in turn through `PadPairing`; shows **Paired with {Mac}**. It
  opens on first run (nothing paired), from **Pair again…** on the pill, from
  Settings, and from the universal link.
- **Settings** lists paired Macs with **Forget this Mac**.
- **Health**: a TLS failure while dialling a paired Mac counts against that Mac
  (`PairingHealth`); after three in a row the pill reads **Not paired with
  {Mac}** with **Pair again…**.

## Key decisions

1. **Wireless stays Debug-only on the Mac.** §5 says the Info.plist keys are
   Debug-only until pairing ships, and pairing now exists, but there is no iPad
   app to pair with until W5 (App Store). A Mac release with **Pair an iPad…**
   and nothing to pair would be a dead end. The flip lands with W5, after the
   W2b hardware check.
2. **The Mac learns of a broken pairing in two ways, both attributable.** A
   failed TLS handshake carries no identity on the listener (§6 known gaps), so
   the Mac cannot count those. It counts what it can attribute: an
   `authenticate` naming a known pairing whose proof fails. And when the user
   forgets a Mac on the iPad while connected, the iPad sends a new
   `forgotten(pairingID)` pairing message before closing; the Mac marks that row
   **Needs pairing again** at once (`PairingHealth.peerForgot`). Both are held in
   memory: a Mac restart clears the flag, and the next re-pair replaces the row.
3. **The Mac keeps the file-based keychain.** The data-protection keychain needs
   a `keychain-access-groups` entitlement, which needs a provisioning profile the
   Developer ID build does not carry. Accepted for v1 (§6 known gaps); ad-hoc
   Debug builds may show a Keychain prompt after a rebuild.
4. **Install ids come from the Keychain on both ends** (`localDeviceID()`, open
   question 10), replacing W1's per-launch Mac id and W3a's
   `identifierForVendor`. The hello's id must equal the id the other side stored
   at pairing, or `LinkGate` closes the link.
5. **The Mac still says hello first.** It sends its hello once TLS is up, before
   the iPad authenticates. TLS with a pre-shared key already proves the iPad
   holds one of the Mac's keys, and the hello carries only the name and id the
   Bonjour record already shows. `PadPairing` needs it to name the Mac.
6. **A universal link fills the code in; pairing waits for a Pair tap.** §6 says
   the link "opens straight into pairing". It does open the pairing screen, but
   without the tap anyone who can get a link onto the iPad could pair it with
   their own Mac, and the newest pairing is dialled first. One tap costs nothing
   on the happy path.
7. **The unauthenticated link is gone from both apps.** `spike/wireless` keeps
   it for measurement; a spike sender can no longer reach the real app.

## Open questions

1. Does a Zoom or Meet *whole-screen* share honour `sharingType = .none` on the
   pairing window (§11, item 5)? Hardware check.
2. Universal link from the Camera app opens pairing: needs the site's
   association file (separate PR) and a team-signed build; confirm in W5.
3. Listener replacement re-registers the Bonjour name. If macOS renames it
   ("Mac (2)") under churn, the iPad still matches on the TXT id, but the Mac's
   name in the iPad pill would read oddly. Watch for it in the hardware check.

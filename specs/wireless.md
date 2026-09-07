# Wireless sharing (research spec)

> Status: research spec. Tier 3 (touches the capture/window model). Not yet
> decided; spike pending hardware. 2026-09-07.

## Problem

SharePad's entire pitch is zero-ritual: plug the iPad into the Mac and the
share window appears, ready to pick in the call. That works because the app
rides the same USB path QuickTime uses — see [Why the current pipeline cannot
simply go wireless](#why-the-current-pipeline-cannot-simply-go-wireless). The
cable is also the thing a subset of paid users keep asking to lose: it pins
the iPad's position at the desk, and a wireless whiteboard is a genuinely
nicer physical setup for drawing while standing or leaning back.

This spec is that research, done because users asked, not because the current
flow is broken. It should be read as **evidence for a decision**, not a
commitment: the honest finding (see [Recommended
direction](#recommended-direction)) is that wireless is worse for the primary
use case on every axis except the cable itself, and buying "no cable" costs a
second shipped product surface. Cutting the cable is not a small feature bolted
onto the existing Mac app — treat it that way and DESIGN.md §2's "display over
selection" trade-off gets silently re-litigated by capture-pipeline drift, not
by a deliberate decision.

## Why the current pipeline cannot simply go wireless

The iPad shows up to SharePad as a `.muxed`, `.external` `AVCaptureDevice`
(DESIGN.md §6.2), unlocked by setting
`kCMIOHardwarePropertyAllowScreenCaptureDevices` before discovery (DESIGN.md
§6.1). This is not a generic "iPad screen" API — it is CoreMediaIO exposing
the **USB** screen-capture device that QuickTime's "New Movie Recording ▸
[iPad]" source list also uses
([`AVCaptureDevice.DiscoverySession`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/discoverysession),
[`AVCaptureDevice.DeviceType.external`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/external)).
There is no wireless counterpart: no `.muxed` device type, and no CMIO
property, that surfaces an iPad connected over Wi-Fi or AirPlay as an
`AVCaptureDevice`. Apple's own device-selection docs describe `.external` as
the class for cabled/dock-connected accessories, not network peers
([Choosing a capture device —
Apple](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/choosing_a_capture_device)).

So "keep everything, drop the cable" is not on the table. Any wireless path
means a different capture source feeding the same window/share-model — which
is exactly the domain-sensitivity trigger CLAUDE.md calls out (capture
pipeline + permission flow) and why this is a Tier 3 spec rather than a
Tier 2 plan.

## Options considered

| | AirPlay-to-Mac + capture the mirror | Companion iPadOS app, in-app ReplayKit capture over LAN | Companion iPadOS app, Broadcast Upload Extension |
|---|---|---|---|
| **Verdict** | **Rejected — dead end** | **Recommended candidate for a spike** | Heavier alternative, not needed yet |
| How it works | iPad AirPlay-mirrors to the Mac (built-in receiver); SharePad tries to capture the incoming mirrored frames as its window content | A small iPadOS app calls `RPScreenRecorder.startCapture` while foregrounded, encodes locally, and streams frames over the LAN to the Mac app, which decodes and feeds the existing preview/share window | Same iPadOS app instead ships an `RPBroadcastSampleHandler` extension, so capture survives backgrounding and isn't limited to one foreground app |
| What it needs | Nothing new on the iPad (AirPlay is built in) | A second app (iPad target), pairing/discovery UX, an encode/decode/transport layer | All of the above, plus an App Group, IOSurface/CFMessagePort IPC into the extension process, and the extension's separate memory budget |
| Why it's rejected / heavier | `ScreenCaptureKit` only enumerates and streams *local* displays, running apps, and windows on the machine it runs on — there is no supported entry point for an *incoming* AirPlay stream ([Capturing screen content in macOS — Apple](https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos)). Developers hitting this exact wall report the same conclusion on Apple's forums: there is no officially documented way to distinguish or intercept AirPlay-received frames from user code ([Apple Developer Forums, AirPlay tag](https://developer.apple.com/forums/tags/airplay)). Even if it existed, capturing *macOS's AirPlay receiver UI* would drag in whatever chrome macOS draws around it, breaking the clean, borderless, aspect-locked window that is SharePad's whole visual promise (DESIGN.md §3). **Dead end — do not re-investigate without a new public API.** | Foreground-only: capture stops the moment the iPad app backgrounds or locks. For a drawing app the user is actively holding and tapping, that is an acceptable restriction, not a defect, and it sidesteps the Broadcast Upload Extension's IPC and memory ceiling entirely. | The Broadcast Upload Extension process has a **hard ~50 MB memory cap** enforced by the OS jetsam mechanism — exceed it and the extension is killed outright, and this bites harder on iPad's larger, higher-resolution screens (Twilio's ReplayKit integration notes this directly: "The memory usage of a ReplayKit Broadcast Extension is limited to 50 MB… there are cases where [capture] can use more than this amount, especially when capturing larger 2x and 3x retina screens" — [Twilio `video-quickstart-ios` ReplayKit README](https://github.com/twilio/video-quickstart-ios/blob/master/ReplayKitExample/README.md); corroborated on [Apple Developer Forums](https://developer.apple.com/forums/thread/651367)). That means careful downscaling/IPC engineering for a capability — background capture — the whiteboarding use case doesn't need. |

## Recommended direction

If wireless ships at all, it is **path 2: a companion iPadOS app**, framed
honestly as a **second product surface**, not a feature flag on the existing
Mac app. That reframing matters for the decision, not just the engineering:

- **Setup regresses.** "Plug in the iPad" becomes "install our iPad app from
  the App Store, open it, pair it with the Mac, tap Start." That is the exact
  ritual SharePad exists to delete (DESIGN.md §1) — reintroduced on the
  wireless path only.
- **Latency and crispness regress.** USB capture is a live camera feed with no
  encode/decode round trip. Any wireless path adds capture → encode → network
  → decode → render, and ReplayKit throttles the input regardless (see [Known
  constraints](#known-constraints)). For live pen strokes, that is a
  perceptible feel change, not a rounding error.
- **The only thing it buys is no cable.** Real for some desks and some
  postures, but it is one dimension against several regressions.

That is a plausible trade for *some* users, not a strict improvement — hence a
spike to measure the regression before committing, rather than a design
decided from first principles.

### Data flow (path 2)

```
 iPad (companion app, foregrounded)                    Mac (SharePad)
 ───────────────────────────────────                   ──────────────
 RPScreenRecorder.startCapture(handler:)
       │  CMSampleBuffer (BGRA), ~15 fps
       ▼
 VideoToolbox (VTCompressionSession)
       │  H.264, hardware encoder
       ▼
 Network.framework (NWConnection)          ── LAN, 5 GHz Wi-Fi ──▶   Network.framework (NWListener)
       │  length-prefixed H.264 over TCP                                    │
       ▼                                                                    ▼
 Bonjour advertise (NWListener service)  ◀── discovery/pairing ──▶  Bonjour browse (NWBrowser)
                                                                             │
                                                                             ▼
                                                                   VideoToolbox (VTDecompressionSession)
                                                                             │  CVPixelBuffer
                                                                             ▼
                                                                   existing share window /
                                                                   preview layer (DESIGN.md §5.1–5.2)
```

Concrete frameworks, all first-party (CLAUDE.md's "third-party dependency is a
flagged decision" bar would otherwise be triggered):

- **ReplayKit** (`RPScreenRecorder.startCapture(handler:completionHandler:)`)
  for in-app capture on the iPad — chosen over a Broadcast Upload Extension
  because the drawing app is the single foreground app; no background
  capability is needed, and it avoids the extension's IPC/memory ceiling
  entirely (see the options table above).
- **VideoToolbox** on both ends — hardware H.264 encode on the iPad,
  hardware decode on the Mac. No software codec.
- **Network.framework** (`NWListener`/`NWBrowser` with a Bonjour service
  type) for LAN discovery/pairing and the data connection itself.

**No WebRTC, no SFU, no signalling server.** This is one iPad talking to one
Mac on the same LAN — a peer-to-peer link is the entire requirement. WebRTC's
value (NAT traversal, congestion control across the open internet, multi-party
mixing) solves problems this product doesn't have; adopting it here would be
exactly the kind of unjustified abstraction CLAUDE.md's engineering guidance
warns against. A length-prefixed H.264 stream over a `Network.framework`
connection (TCP, or QUIC if head-of-line blocking on Wi-Fi turns out to
matter) is sufficient.

## Known constraints

- **ReplayKit throttles in-app capture to ~15 fps for app content.** This is
  not a bug to work around — it is how `RPScreenRecorder`'s screencast mode
  behaves by design ("The input from ReplayKit is always capped at 15 fps…
  When app content is shown, the input is capped at 15 fps. However, when
  playback of 24 fps video content is detected the input cap is raised" —
  [Twilio `video-quickstart-ios` ReplayKit
  README](https://github.com/twilio/video-quickstart-ios/blob/master/ReplayKitExample/README.md),
  describing `RPScreenRecorder`/`startCapture` behaviour documented at
  [`RPScreenRecorder` —
  Apple](https://developer.apple.com/documentation/replaykit/rpscreenrecorder)).
  15 fps is workable for a mostly-static whiteboard but is a real ceiling on
  how fluid fast pen strokes can look — this is the single biggest open risk
  the spike exists to test.
- **Realistic end-to-end LAN latency is around 90 ms on a good 5 GHz
  network**, once capture, hardware encode, a Wi-Fi hop, hardware decode, and
  render are all summed. That is well above USB capture's effectively
  zero-added latency and is in the range where a pen-and-paper feel starts to
  degrade — untested here, hence the spike.
- **A Broadcast Upload Extension's ~50 MB memory cap** rules out that
  architecture without significant downscaling engineering (see the options
  table); it is why path 2 (in-app capture, no extension) is the pragmatic
  starting point.
- **Pairing/discovery UX is new surface area.** Bonjour discovery on a shared
  office Wi-Fi network can surface multiple Macs/iPads; the companion app
  needs an explicit pick-and-confirm step, not silent auto-connect — a
  material departure from "plug in and it just works."
- **A second App Store listing.** The iPadOS companion app is a distinct
  product to build, sign, and ship (App Store, not the Mac app's Developer-ID
  direct download — see `specs/distribution.md`), with its own review,
  versioning, and support surface.
- **It inverts the "zero install" value proposition** that is SharePad's
  entire differentiator (DESIGN.md §1, §2). Wireless does not extend the
  product; it forks it into "the simple USB one" and "the wireless one with
  more steps."

## The spike

The only question worth answering before any product commitment is: **does a
LAN-streamed iPad feed feel good enough for live drawing?** Everything else in
this document is desk research; this is the one claim that needs hardware.

**This spike has not been run.** It requires an iPad and a Mac on the same
5 GHz Wi-Fi network and has not been scheduled against hardware availability.

### Minimal build

Throwaway code, explicitly not production quality and not to be merged into
`Sources/SharePad/`:

- **iPad sender**: a bare single-view iPadOS app. `RPScreenRecorder.shared()
  .startCapture(handler:)` on a button tap, feeding `CMSampleBuffer`s into a
  `VTCompressionSession` (H.264, hardware encoder), writing length-prefixed
  NAL units to a single `NWConnection` opened against a hardcoded Mac IP:port
  (no Bonjour, no pairing UX — that polish is irrelevant to the latency
  question).
- **Mac receiver**: a bare command-line or single-window tool (not the
  SharePad app) that accepts one `NWListener` connection, feeds bytes into a
  `VTDecompressionSession`, and renders decoded frames as fast as they arrive
  (an `AVSampleBufferDisplayLayer` is the least-code option, mirroring the
  existing popover-thumbnail approach in DESIGN.md §5.2).
- No App Store, no signing ceremony, no reconnect/error handling beyond
  "works for a five-minute session."

### Measurement method

- **Glass-to-glass latency**: film the iPad screen and the Mac screen
  together in one camera shot (a second phone on a tripod is enough), display
  a running stopwatch or millisecond counter as the drawn content on the
  iPad, and step through the video frame-by-frame to read the time delta
  between the same stopwatch value appearing on each screen. Repeat several
  times and take the median — a single sample is noise, not a result.
- **Stroke feel**: draw continuous curves and fast short strokes (the two
  extremes of whiteboarding) while watching only the Mac-side window, the way
  a call participant would. Note, qualitatively, whether strokes look laggy,
  stepped, or juddery rather than smoothly trailing the pen — this is a
  feel judgement the latency number alone doesn't capture, particularly given
  the 15 fps cap.
- **Jitter**: watch for variance between repeated latency measurements, not
  just the median. A high but *consistent* delay is a different (more
  fixable) problem than one that swings wildly.

### Time box

**2–3 days**, hardware-availability permitting. That covers: get the minimal
sender/receiver talking on the LAN (day 1), run and record the latency/feel
measurements above (day 2), write up the result and make the go/kill call
(remainder of day 2 or day 3). If it's taking longer than that, the answer is
probably "kill" on complexity grounds alone — the whole point of a spike is a
fast, cheap answer.

### GO / KILL criteria

- **GO** if median glass-to-glass latency comes in under roughly **120 ms**
  *and* strokes look and feel usable for live drawing during the qualitative
  pass (no visible stepping on fast strokes, no distracting lag between hand
  motion and line appearance) *and* jitter is low enough that the feel is
  consistent, not a lottery. GO means: write a proper Tier 3 implementation
  spec for the companion app and treat it as new-product-surface work
  (roadmap, App Store listing, support), not a quick add-on.
- **KILL** if latency sits meaningfully above the ~90 ms desk-research
  estimate, or drawing visibly lags/steps even at an acceptable latency
  number, or jitter makes the feel inconsistent session-to-session. KILL
  means: document the measured numbers here as the closing entry on this
  spec, and treat "no cable" as a rejected feature for the live-drawing use
  case — USB remains the only supported connection method.

## Open questions

- **Does 15 fps actually feel acceptable for pen strokes**, or does the cap
  bite harder than the latency number alone suggests? This is exactly what
  the qualitative stroke-feel pass in the spike is for — it isn't answerable
  from documentation alone.
- **Does Apple Pencil's own input latency compound with the network path**,
  making the perceived lag worse than glass-to-glass video latency alone
  would suggest? Not measured by the spike as scoped above; worth watching
  for during the qualitative pass even if not formally quantified.
- **Audio**: out of scope, matching the existing Mac app's non-goal (DESIGN.md
  §1) — the companion app should not add a microphone/audio path unless a
  future spec reopens that decision.
- **Security of the LAN link**: the spike's raw TCP link is deliberately
  unauthenticated and unencrypted. A shipped version would need at minimum a
  pairing handshake that isn't "first connection wins" on a shared network
  (e.g. an office Wi-Fi with several iPads and Macs present) — not designed
  here, since it's moot if the spike kills the idea on latency/feel grounds
  first.
- **Pairing UX**: how a user picks *which* Mac their iPad should stream to
  when several are Bonjour-visible is unresolved product design, deferred
  until a GO result makes it worth designing.

# Wireless spike (throwaway)

Answers one question from [`specs/wireless.md`](../../specs/wireless.md): **does a
LAN-streamed iPad feed feel good enough for live drawing?** Everything here is
measurement code with a two-day life. It is outside `Sources/SharePad/`, has its
own Xcode project, and must never be merged into the shipping app.

```text
spike/wireless/
  Spike/                    SwiftPM package (Mac side + shared code)
    Sources/SpikeWire/      wire protocol, H.264 encode/decode, Bonjour link, clock sync
    Sources/SpikeReceiver/  Mac receiver: window, decode, latency HUD, CSV
    Sources/SpikeFakeSender/ stands in for the iPad so the path works with no hardware
  Sender/                   iPadOS app: ReplayKit capture + PencilKit canvas + ms counter
  project.yml               xcodegen spec for the iPad app only
  analyse.swift             reduces a receiver CSV to median/p95/jitter
  justfile                  every command below
```

## Data path

iPad `RPScreenRecorder.startCapture` → `VTCompressionSession` (H.264, hardware,
real-time, no frame reordering) → length-prefixed messages over one
`NWConnection` (TCP, `noDelay`, `interactiveVideo`) → Mac
`VTDecompressionSession` → `AVSampleBufferDisplayLayer` with
`DisplayImmediately`. Discovery is Bonjour (`_sharepadspike._tcp`); first
service wins, because pick-and-confirm pairing is product design the spec defers
until a GO.

## Running it

Mac side, from `spike/wireless`:

```bash
just build              # release build of both executables
just receiver           # windowed receiver, advertises over Bonjour, writes /tmp/spike-latency.csv
just fakesender         # optional: fake iPad on this Mac, no hardware needed
just stats              # median/p95/jitter from the CSV, warm-up discarded
```

iPad side:

```bash
export SPIKE_TEAM_ID=MN4C3MNXU2      # Apple Development: Jon Yardley
just sender-run "Jon's iPad"         # or: just open, then run from Xcode
```

On first run the iPad asks for **local network** access and **screen recording**
(ReplayKit's own confirmation). Both must be granted or `startCapture` returns an
error, which the app surfaces in red under the Start button.

## Measurement runbook

The HUD's `capture→decoded` figure is **not** the number that decides this. It
excludes Apple Pencil input latency, the iPad's own display pipeline and the
Mac's present time. It is useful for isolating *where* time goes; the camera
method below is the verdict.

1. Put iPad and Mac on the same **5 GHz** network, both awake, iPad unlocked.
2. Start `just receiver` on the Mac; leave the window visible at a decent size.
3. Launch the iPad app, tap **Start streaming**, wait for the HUD to show a
   steady 15 fps. **Discard the first two seconds**: the first VideoToolbox
   session takes ~1.8 s to create, so early frames read late.
4. Film the iPad screen and the Mac window together in one shot with a second
   phone on a tripod. The iPad's yellow millisecond counter is the instrument.
5. Step through the recording frame by frame. For each reading, note the iPad
   counter value and the value visible in the Mac window at the same instant.
   The delta is glass-to-glass latency. Take **at least 10 readings** and use the
   median: one sample is noise.
6. Then stop watching the numbers and draw: continuous curves, then fast short
   strokes, watching **only the Mac window**, as a call participant would. Note
   whether strokes trail smoothly or step and judder. The 15 fps ReplayKit cap
   is the risk this pass exists to judge.
7. Run `just stats` for the component figures and jitter, and keep the CSV.

### Results

| Run | Glass-to-glass median (ms) | Spread (ms) | capture→decoded median (ms) | Stroke feel | Notes |
|---|---|---|---|---|---|
| | | | | | |

### GO / KILL

Copied from the spec so the call is made against what was written beforehand:
**GO** needs a glass-to-glass median under roughly **120 ms**, strokes that look
usable for live drawing, and jitter low enough to be consistent. **KILL** if
latency sits meaningfully above the ~90 ms estimate, or drawing visibly
lags/steps even at an acceptable number, or the feel is a lottery run to run.
Either way the measured numbers become the closing entry on
[`specs/wireless.md`](../../specs/wireless.md).

## What has been verified without an iPad

Mac-to-Mac over loopback Bonjour, `spike-fakesender` → `spike-receiver`,
270 frames then 150 frames:

- steady **15.0 fps**, 0 dropped, ~700 kbps for a moving-content 1280x800 frame
- **capture→decoded median 6.8 ms** (p95 9.6, jitter ±0.8), decode 2.6 ms
- decoded frames render correctly (snapshot PNG of the counter is readable)

That establishes the protocol, encode, decode and render path are sound and that
the receiver's numbers are trustworthy. It says **nothing** about Wi-Fi: there is
no radio hop, no ReplayKit, and no real display pipeline in that figure.

## Deliberate omissions

No reconnect polish, no pairing UX, no authentication or encryption on the link,
no audio, no App Store packaging. All of it is moot if the answer is KILL, and
all of it is specced separately if the answer is GO.

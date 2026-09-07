# Crash & diagnostic telemetry (first-party, opt-in)

> Status: spec. Tier 3 (net-new capability; the app reaches the internet for a
> new reason). Decided 2026-09-07.

## Problem

SharePad has paying users and no view of when it breaks on their machines. There
is no crash reporting and no signal for the known silent-failure surfaces: an
empty device list after the CMIO opt-in, an `AVCaptureSession` runtime error that
fails to recover, a share lost mid-call, a licence key that will not validate. We
find out only if a user emails. That is the biggest operational gap now that money
is involved.

## Constraints that shape the design

- **The privacy page is a promise.** `docs/privacy.html` currently states the app
  has "no analytics SDKs or usage tracking" and that "nothing ever leaves your
  machine" bar the Sparkle update check. Any telemetry changes that promise, so it
  must be **genuinely opt-in (default off)**, disclosed, and anonymous. This is the
  load-bearing decision: default-on would contradict a customer-facing commitment.
- **No third-party dependencies** (CLAUDE.md). No Sentry, no crash-SDK. First-party
  frameworks only.
- **No sandbox** today, so MetricKit has no entitlement blocker.

## Approach

First-party `MetricKit` for crashes and hangs, plus a tiny custom sender for the
domain non-fatals MetricKit cannot see, both POSTing anonymous JSON to a new
Cloudflare Worker. This mirrors the existing appcast-analytics posture (anonymous,
aggregate, edge-derived country, no IP) and reuses the Workers + Analytics Engine
infrastructure already in the repo.

```
App (opt-in only)
  ├─ MetricKit MXMetricManagerSubscriber ── crash/hang diagnostics (next launch)
  └─ DiagnosticsReporter.report(event)   ── named non-fatals (immediate)
        │  POST JSON, no device id, no PII
        ▼
  telemetry.sharepad.co  (Cloudflare Worker)
        ├─ Analytics Engine  → time series (kind, name, appVersion, osVersion, country)
        └─ R2 (crash/hang only) → raw MetricKit JSON for later inspection
```

MetricKit delivers crash and hang diagnostics on the **next launch** (aggregated by
the system), so crash reporting is not real-time. That is an accepted trade for
staying first-party and SDK-free; for a small utility, next-launch crash counts
plus the raw payload to read are enough.

### Why both Analytics Engine and R2

- **Analytics Engine** gives the queryable time series ("3 crashes in 1.2.0 this
  week", non-fatal event rates) at near-zero cost, same as `sharepad_appcast`. AE
  rows are small, so it holds counts and coarse fields only.
- **R2** stores the full raw MetricKit `jsonRepresentation()` for crash and hang
  payloads (keyed `YYYY/MM/DD/<uuid>.json`), so when a count spikes there is an
  actual stack to read. Named events are counts only, never written to R2.

## Components

| Unit | Responsibility |
|---|---|
| `Sources/SharePad/Support/Diagnostics.swift` | `DiagnosticsReporting` protocol, `DiagnosticEvent` enum, `DiagnosticsReporter` (MetricKit subscriber + POST), a `.disabled` no-op |
| `Preferences.diagnosticsEnabled` | Bool, **default false**; the opt-in toggle's backing store |
| `PopoverView` toggle | "Send anonymous crash reports" with a one-line rationale |
| `App.swift` | subscribe the reporter to MetricKit at launch **iff** opted in (and not under XCTest) |
| `AppModel` | emit the four non-fatal events at their transitions, via an injected `DiagnosticsReporting` |
| `workers/telemetry/src/index.mjs` | `fetch`: validate POST, write AE, put crash/hang to R2; fail soft |
| `workers/telemetry/wrangler.toml` | AE dataset + R2 binding + `custom_domain` route |
| `workers/telemetry/test/index.test.mjs` | `node --test`, mirrors the appcast worker suite |
| `just telemetry-stats` | query AE: counts by kind/version over N days |

### Domain non-fatal events (what MetricKit cannot see)

Grounded in the code, four events, each a bare name with no payload and no PII:

- `retryExhausted` - the first-connect retry loop gave up with the device still not
  live (`AppModel.retryLoop`).
- `restartFailed` - a runtime-error/wake restart did not bring frames back
  (`AppModel.restart`).
- `shareLost` - the iPad vanished while its share window was up (`raiseShareLost`).
- `licenseEntryFailed` - a user-entered key failed validation (`enterLicense`
  returns false). The email and key are **never** sent, only the fact of a failure.

### POST body

```json
{ "kind": "crash" | "hang" | "event",
  "name": "<terminationReason | 'hang' | eventName>",
  "appVersion": "1.2.0",
  "osVersion": "14.5",
  "payload": { /* MetricKit jsonRepresentation, crash/hang only */ } }
```

### Data point shape (Analytics Engine, dataset `sharepad_telemetry`)

- `blobs`: `[kind, name, appVersion, osVersion, country]`
- `indexes`: `[kind]`
- `doubles`: `[1]`

## Privacy posture

- **Off by default.** No data leaves the machine unless the user turns the toggle on.
- **No identifier.** No device id, no cookies, no IP stored (country is edge-derived
  `cf.country`, same as appcast). Nothing ties a report to a person or device.
- **No content.** Never the drawing, the licence email/key, the device name, or any
  window content. Named events carry only their name.
- Crash/hang payloads are Apple's standard MetricKit diagnostics (stack traces,
  exception type, OS/app version) - the same data Xcode Organizer shows - with no
  user content.
- `docs/privacy.html` gains a paragraph: optional, off-by-default, anonymous crash
  and diagnostic reporting; what it sends and what it never sends.

## Error handling

Two invariants: (a) telemetry never affects the app's behaviour, and (b) a backend
outage is silent.

- The reporter's send is fire-and-forget; a failed or slow POST is swallowed and
  never blocks the main actor or a capture path.
- Worker: `writeDataPoint` and the R2 `put` are each wrapped and optional-chained,
  so a missing binding or a write error still returns `204`. Non-POST → `405`;
  oversized or unparseable body → `400`; body cap rejects payloads over 256 KB.
- Abuse: the endpoint is an unauthenticated POST. A static token baked into the
  client binary would be theatre, so protection is a size cap plus a `SharePad`
  User-Agent check. Blast radius is bounded to R2 storage; revisit if abused.

## App + docs changes

- `Preferences`: add `diagnosticsEnabled` (default false).
- `docs/privacy.html`: the disclosure paragraph above; soften the absolute
  "nothing ever leaves your machine" to name the opt-in exception honestly.
- `project.yml`: no new entitlement or Info.plist key (MetricKit needs none on
  macOS, un-sandboxed). `just gen` not required for this change.
- `DESIGN.md` / `CLAUDE.md`: note the telemetry surface and its opt-in posture.

## Testing

- **Swift unit** (fake `DiagnosticsReporting` spy, no network): `AppModel` emits
  `shareLost` on mid-call disconnect, `licenseEntryFailed` on a bad key,
  `retryExhausted` when the retry loop is exhausted, `restartFailed` when a restart
  brings no frames. Plus the `DiagnosticEvent` → name mapping and POST-body
  encoding. Tests drive the existing designated init, which defaults the reporter to
  `.disabled`, so the suite stays side-effect-free.
- **Worker** (`node --test`, mirrors appcast): POST with a valid event writes one AE
  point and no R2 object; a crash POST writes AE and one R2 object; oversized body →
  400; non-POST → 405; a throwing AE binding and a throwing R2 binding still return
  204; a missing binding does not throw.
- **Manual (post-deploy)**: opt in, force a non-fatal (unplug mid-share), confirm a
  row lands in AE; confirm the toggle off sends nothing.

## Deployment

CI-driven like the other workers: `.github/workflows/deploy-telemetry-worker.yml`
deploys on push to `main` under `workers/telemetry/**`; `workers-ci.yml` gains
`telemetry` to its matrix so the suite runs on PRs. No runtime secrets. The first
deploy provisions the `telemetry.sharepad.co` custom domain and the R2 bucket; the
custom domain needs the CI `CLOUDFLARE_API_TOKEN` to carry Zone DNS + Workers Routes
edit on the sharepad.co zone (same caveat as appcast-analytics), and R2 needs the
bucket to exist (wrangler creates it on deploy, or create once in the dashboard).

## Open questions

- Reading AE via `just telemetry-stats` needs a token with *Account Analytics:
  Read* (the wrangler OAuth token likely lacks it), same as `just appcast-stats`.
- Whether to surface a lightweight "a crash report was sent" acknowledgement in the
  popover, or keep it fully silent. Silent for now.
- MetricKit on macOS delivers on next launch; if real-time crash visibility ever
  matters more than staying SDK-free, revisit (that is the Sentry conversation).

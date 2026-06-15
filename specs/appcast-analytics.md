# Appcast analytics (active installs + version adoption)

> Status: spec. Tier 3 (touches the update/distribution model). Decided 2026-06-15.

## Problem

We have no view of **active installs over time** or **version adoption**. The only
signals today are cumulative GitHub asset counts (`just downloads`) — a floor, not
a time series, and blind to which versions are actually running.

Sparkle already makes a per-install update-check (`SUFeedURL`,
`https://sharepad.co/appcast.xml`, served from gh-pages). That request is a free
heartbeat from every running install — we just don't capture it, because GitHub
Pages has no request logs.

## Approach

Serve the appcast through a thin **Cloudflare Worker logging proxy** at a dedicated
subdomain, recording one anonymous data point per check. The release pipeline is
unchanged: CI keeps publishing `appcast.xml` to gh-pages, which stays the single
source of truth; the Worker proxies it and logs the hit.

```
Sparkle ──GET──▶ appcast.sharepad.co/appcast.xml  (Worker)
                      │  1. fetch upstream https://sharepad.co/appcast.xml (edge-cached ~300s)
                      │  2. writeDataPoint → Workers Analytics Engine (version, country)
                      └─ 3. return appcast body, application/xml
```

### Why a subdomain (not proxying the whole site)

`sharepad.co` DNS is on Cloudflare but **grey-cloud** (resolves straight to GitHub
Pages). Proxying the whole apex would capture existing installs with no app change,
but means reconfiguring SSL on the live revenue site — real risk for little gain,
since the install base is ~nil at launch week. A dedicated `appcast.sharepad.co`
Worker is zero-risk to the live site and gives a stable feed URL we never change
again. Cost: only installs on the **next release onward** are logged (the new
`SUFeedURL` ships in that build) — negligible at current scale.

### Privacy posture

Minimal by construction. The update-check already happens; we only log it.

- **App version** is parsed from Sparkle's existing User-Agent
  (`SharePad/<ver> Sparkle/<ver>`) — no change to what the app transmits.
- **Country** comes from `cf.country` (Cloudflare-derived); the **IP is never
  stored**. No device ID, no cookies, no `SUEnableSystemProfiling`.
- `docs/privacy.html` gains one line: update-checks are logged in aggregate (app
  version, approximate country); no personal data retained.

If a macOS-version / hardware breakdown is wanted later, enabling
`SUEnableSystemProfiling` is a follow-up — and a privacy disclosure change.

## Components

| Unit | Responsibility |
|---|---|
| `workers/appcast/src/index.mjs` | `fetch` handler: proxy upstream appcast + log a data point |
| `parseAppVersion(userAgent)` (exported) | pure: extract `x.y.z` from the UA, else `unknown` |
| `workers/appcast/wrangler.toml` | AE dataset binding + `custom_domain` route |
| `workers/appcast/test/index.test.mjs` | `node --test`: UA parsing + proxy/no-break behaviour |
| `just appcast-stats` | query the AE SQL API: checks/day + version distribution |

Mirrors the existing workers (ESM `.mjs`, `export default { fetch }`, `node:test`,
`globalThis.fetch` stubbing).

### Data point shape (Analytics Engine, dataset `sharepad_appcast`)

- `blobs`: `[appVersion, country, rawUserAgent]`
- `indexes`: `[appVersion]` (group/sample key)
- `doubles`: `[1]`

"Active installs" is **approximate** — without a device ID (deliberately not
collected), the signal is *update-checks per day*, a strong proxy, not unique
devices.

## Error handling

Two invariants: (a) never serve a wrong or unsigned appcast, and (b) a logging
problem never affects what's served.

- `writeDataPoint` is fire-and-forget, wrapped in try/catch, and `env.AE?.` is
  optional-chained — a logging error (or a missing binding) never affects the
  served body.
- Upstream fetch failure → return `502`. This does **not** break auto-update:
  Sparkle treats a failed feed fetch as "no update this cycle" and retries on the
  next interval, so the worst case is a missed check, not a broken updater. The
  upstream is GitHub Pages (highly available), so a hard 502 here is simpler and
  honest — we'd rather 502 than risk serving a stale/wrong appcast from a fallback
  cache. (If GH Pages reliability ever becomes a problem, add a `caches.default`
  stale-serve fallback; not worth the complexity now.)

## App + docs changes

- `project.yml`: `SUFeedURL` → `https://appcast.sharepad.co/appcast.xml`; `just gen`.
- `docs/privacy.html`: aggregate-logging line (see Privacy posture).
- `specs/distribution.md`: fix the stale "GitHub Release asset" appcast lines
  (already contradict `release.yml` — appcast is served from gh-pages).

## Testing

- Unit (`node --test`): `parseAppVersion` happy path + missing/odd UA → `unknown`;
  upstream-failure path still returns the appcast and never throws.
- Manual (post-deploy): `curl https://appcast.sharepad.co/appcast.xml` returns the
  appcast byte-identical to the gh-pages copy; confirm a row lands in AE; bump a
  build and confirm Sparkle still updates against the new feed URL.

## Deployment

CI-driven, like the other workers: `.github/workflows/deploy-appcast-worker.yml`
deploys on push to `main` under `workers/appcast/**` (no manual `wrangler`). It has
no runtime secrets. `workers-ci.yml` runs its tests on PRs.

The **first** deploy provisions the `appcast.sharepad.co` custom domain
(`wrangler.toml` routes). That needs the CI `CLOUDFLARE_API_TOKEN` to carry **Zone
DNS + Workers Routes edit** on the sharepad.co zone, not just Workers Scripts. If
the existing token is workers-only, either widen it once or create the custom
domain in the dashboard first (the same dashboard-managed pattern as the licenses
rate-limit rule) — then CI deploys reconcile cleanly.

## Open questions

- Reading AE via `just appcast-stats` needs a `CLOUDFLARE_API_TOKEN` with
  *Account Analytics: Read* (the wrangler OAuth token likely lacks it). Until then,
  the Cloudflare dashboard shows the same data. One-time setup, documented in the
  recipe.
- Verify Sparkle's exact User-Agent format on the first real check; log the raw UA
  as a fallback blob so a format surprise is recoverable, not lost.

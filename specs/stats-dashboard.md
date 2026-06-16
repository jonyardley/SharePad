# Unified stats dashboard

> Status: spec. Tier 3 (net-new capability). Decided 2026-06-15.

## Problem

Analytics are spread across four places — GitHub Releases (downloads), the appcast
Worker's Analytics Engine (active installs + versions), Cloudflare Web Analytics
(site traffic), and Stripe (revenue). No single view.

## Approach

A small Cloudflare Worker at `stats.sharepad.co` that, on load, queries all four
sources **server-side** and renders one HTML page. API tokens live as **Worker
secrets**, never on a laptop. Consistent with the all-Cloudflare, first-party stack.

```
GET stats.sharepad.co ──▶ Worker
   auth gate (DASHBOARD_TOKEN cookie/param; Cloudflare Access recommended on top)
   ├─ GitHub Releases API        → DMG downloads (public, no secret)
   ├─ Analytics Engine SQL API   → active installs + version split   [CF_API_TOKEN]
   ├─ Web Analytics GraphQL (RUM)→ pageviews + visits                [CF_API_TOKEN]
   └─ Stripe API                 → sales count + gross revenue       [STRIPE_API_KEY]
   → render one HTML dashboard
```

### Auth

Two layers, both optional-to-add but **at least one required to deploy safely**:

1. **`DASHBOARD_TOKEN` secret** (built-in): the Worker 401s unless the request
   carries the token (via `?token=` once → set httpOnly cookie → redirect to strip
   the URL, or `Authorization: Bearer`). If the secret is unset, the Worker serves a
   "not configured" notice, never the data.
2. **Cloudflare Access** (recommended): a Self-hosted Access app over
   `stats.sharepad.co` scoped to Jon's email, for proper SSO. Layered on top.

### Graceful degradation

Each section renders independently. A missing secret or a failing upstream shows
that card as "not configured" / "unavailable" — the rest of the dashboard still
loads. So it can deploy first and have secrets wired incrementally.

### Caching

Each upstream response is cached ~5 min (`caches.default`) so refreshes don't hammer
the APIs or burn GitHub's unauthenticated rate limit.

## Components

| Unit | Responsibility |
|---|---|
| `workers/stats/src/index.mjs` | fetch handler: auth gate → gather sources (parallel, fail-soft) → render |
| `workers/stats/src/lib.mjs` | pure: request builders, response parsers, formatters, HTML render — unit-tested |
| `workers/stats/wrangler.toml` | custom domain `stats.sharepad.co`; vars + secret bindings |
| `workers/stats/test/lib.test.mjs` | `node --test`: parsers (GitHub/AE/Stripe/RUM), auth check, formatters |
| `.github/workflows/deploy-stats-worker.yml` | deploy on `workers/stats/**` push; sync secrets |

### Config

- **Secrets:** `DASHBOARD_TOKEN`, `CF_API_TOKEN` (Account Analytics: Read — covers AE
  SQL *and* RUM GraphQL), `STRIPE_API_KEY` (Checkout Sessions: read — reuse the
  licenses worker's restricted key).
- **Vars:** `CF_ACCOUNT_ID`, `WEB_ANALYTICS_SITE_TAG` (the public beacon token),
  `GITHUB_REPO` (`jonyardley/SharePad`), `AE_DATASET` (`sharepad_appcast`).

### Metrics shown (v1)

- **Downloads:** total DMG downloads (GitHub Releases stable `SharePad.dmg`), per
  release; appcast-check counts as a secondary install proxy.
- **Active installs / versions:** update-checks (last 7d, ≈ active installs) and the
  version split from `sharepad_appcast` (`SUM(_sample_interval)`).
- **Site traffic:** pageviews + visits, last 7d, from `rumPageloadEventsAdaptiveGroups`
  (account-scoped — sharepad.co is grey-cloud, so the RUM beacon, not zone analytics,
  holds this). Summed across **all** the account's Web Analytics sites with **no
  siteTag filter**: the GraphQL `siteTag` is not the JS beacon token, and sharepad.co
  is currently split across two (duplicate) sites — summing matches the dashboard.
  Revisit if an unrelated property ever gets Web Analytics on this account.
- **Revenue:** completed checkout sessions — count + gross (last 100; paginate later).

## Error handling

The auth gate fails closed (401 / "not configured"). Every upstream fetch is wrapped
so one failing source never blanks the page. Secrets are read defensively; absent →
that card says "not configured".

## Testing

- Unit (`node --test`): each parser against a representative API payload, the auth
  check (valid/invalid/missing token), and the formatters. The live API calls are
  verified manually post-deploy.
- Manual: hit `stats.sharepad.co?token=…`, confirm each card; confirm 401 without it.

## Open questions / later

- Pagination for Stripe beyond 100 sessions and GitHub beyond the first page.
- Time-series charts (this is a current-snapshot view); revisit Grafana if trends matter.
- Whether to verify the `Cf-Access-Jwt-Assertion` header in-Worker once Access is on
  (defense in depth) — v1 relies on Access at the edge + the token.

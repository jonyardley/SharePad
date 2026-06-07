# purchase-email Worker

A Cloudflare Worker that sends buyers a **re-download email** after checkout.

Under Stripe **Managed Payments**, Stripe owns the receipt email and we can't add a
download link to it. This Worker listens for `checkout.session.completed` and emails
the buyer the durable thank-you page link (`thanks-a7f3c92b.html?owner`), which
resolves the current DMG from the appcast. The `?owner` param selects the page's
re-download view (a plain download, no buy prompt). See [`specs/purchase-email.md`](../../specs/purchase-email.md).

The link is sent **only by email**, never published on the site, so the
download-URL-hardening funnel stays intact.

## How it works

```
Stripe checkout.session.completed
        │  (signed webhook)
        ▼
  Cloudflare Worker  ──verify Stripe-Signature──▶ reject if invalid (400)
        │
        ├─ not checkout.session.completed → 200 ignore
        ▼
  Resend API ──▶ branded email with the download button
```

## Deployment — via GitHub Actions

`.github/workflows/deploy-worker.yml` deploys this Worker automatically on every push
to `main` that touches `workers/purchase-email/**` (or on **Actions → Deploy Worker →
Run workflow**). The Worker's runtime secrets are **synced from GitHub Actions
secrets on each deploy**, so GitHub is the single source of truth — no manual
`wrangler secret put`.

### GitHub repo secrets to set
Settings → Secrets and variables → **Actions** → New repository secret:

| Secret | Where to get it |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Cloudflare → My Profile → API Tokens → Create Token → **Edit Cloudflare Workers** template. |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare → Workers & Pages → right-hand sidebar (Account ID). |
| `RESEND_API_KEY` | Resend → API Keys (`re_…`). Verify the `sharepad.co` sending domain first. |
| `STRIPE_WEBHOOK_SECRET` | The `whsec_…` from the Stripe webhook endpoint (created **after** the first deploy — see bootstrap). |

### First-time bootstrap (chicken-and-egg)
The Stripe signing secret can only be made *after* the Worker has a URL, so:

1. Set `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `RESEND_API_KEY`.
2. Merge to `main` (or run the workflow) → the Worker deploys. It's live but inert:
   with no `STRIPE_WEBHOOK_SECRET` yet it safely rejects all webhooks (no emails).
3. Create the Stripe webhook endpoint (`checkout.session.completed`) pointing at the
   Worker's `*.workers.dev` URL; copy its `whsec_…` signing secret.
4. Add `STRIPE_WEBHOOK_SECRET` to the repo secrets, then re-run the workflow. Done.

## Test it
```bash
# Signature + happy path (needs the Stripe CLI, logged in):
stripe trigger checkout.session.completed
#   → Worker returns 200, a download email arrives.

# Negative: a tampered/unsigned request must be rejected with NO email sent.
curl -i -X POST <worker-url> -d '{}'            # expect HTTP 400
```
Then do **one real live purchase** (your own card, refund after): confirm both the
Stripe receipt *and* the re-download email arrive, and the button downloads the
current DMG.

## Local deploy (optional, for development only)
You can still deploy by hand to iterate — run from `workers/purchase-email`:
```bash
npx wrangler login
npx wrangler deploy
```
Local manual `wrangler secret put …` only affects your manual deploys; CI re-syncs
secrets from the GitHub secrets above on its next run.

## Config
| Name | Type | Purpose |
|---|---|---|
| `STRIPE_WEBHOOK_SECRET` | secret (GitHub → Worker) | Verify the `Stripe-Signature` header. |
| `RESEND_API_KEY` | secret (GitHub → Worker) | Auth for the Resend send API. |
| `DOWNLOAD_URL` | var (`wrangler.toml`) | Link in the email. Defaults to the thank-you page re-download view (`?owner`). |
| `EMAIL_FROM` | var (`wrangler.toml`) | Sender; the domain must be verified in Resend. |

## Notes
- **At-least-once**: a transient Resend failure returns 500 so Stripe retries; a
  duplicate email is acceptable. Add Workers KV dedupe on `session.id` only if it
  becomes a problem (spec §5/§8).
- No npm dependencies — signature verification uses Web Crypto.

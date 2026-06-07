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

## One-time setup

### 1. Resend (email sending)
1. Sign up at [resend.com](https://resend.com) and **verify the `sharepad.co`
   domain** (add the SPF/DKIM DNS records it gives you — you manage DNS in
   Cloudflare, so this is quick). Verifying the domain is what lets you send from
   `hello@sharepad.co`.
2. Create an **API key** (`re_…`).

### 2. Deploy the Worker
```bash
cd workers/purchase-email
npx wrangler login          # once
npx wrangler secret put RESEND_API_KEY        # paste the re_… key
npx wrangler deploy                            # note the printed *.workers.dev URL
```

### 3. Wire up the Stripe webhook
1. Stripe Dashboard → **Developers → Webhooks → Add endpoint**.
2. **Endpoint URL** = the Worker URL from step 2.
3. **Events**: select only `checkout.session.completed`.
4. Copy the endpoint's **Signing secret** (`whsec_…`) and store it:
   ```bash
   npx wrangler secret put STRIPE_WEBHOOK_SECRET   # paste the whsec_… secret
   ```
5. The secret is read at request time — no redeploy needed, but `wrangler deploy`
   again if you want to be sure.

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

## Config
| Name | Type | Purpose |
|---|---|---|
| `STRIPE_WEBHOOK_SECRET` | secret | Verify the `Stripe-Signature` header. |
| `RESEND_API_KEY` | secret | Auth for the Resend send API. |
| `DOWNLOAD_URL` | var (`wrangler.toml`) | Link in the email. Defaults to the thank-you page re-download view (`?owner`). |
| `EMAIL_FROM` | var (`wrangler.toml`) | Sender; the domain must be verified in Resend. |

## Notes
- **At-least-once**: a transient Resend failure returns 500 so Stripe retries; a
  duplicate email is acceptable. Add Workers KV dedupe on `session.id` only if it
  becomes a problem (spec §5/§8).
- No npm dependencies — signature verification uses Web Crypto.

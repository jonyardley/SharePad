# Purchase Email (re-download link) — Spec

> Status: **accepted, pending deploy** (2026-06-07). Siblings:
> `specs/licensing.md` (sell-the-build model), `specs/download-url-hardening.md`
> (why the DMG URL is unguessable), `specs/distribution.md` (release pipeline).

## 1. Problem & goal

A buyer who closes the post-checkout thank-you tab has **no way back to their
download**. We're on **Stripe Managed Payments (Stripe = merchant of record)**, and
Stripe *owns* the receipt/confirmation emails — `custom_text` and `invoice_creation`
are unsupported under Managed Payments, and "your receipt settings don't affect
these emails." So we **cannot inject a link into Stripe's email**.

Goal: every buyer gets a **durable re-download link in their inbox**, without
publishing that link on the marketing site (which would defeat the
download-URL-hardening funnel — see that spec).

## 2. Approach

A small **Cloudflare Worker** subscribes to the Stripe `checkout.session.completed`
webhook and sends a branded courtesy email containing the **existing thank-you page
URL** (`https://sharepad.co/thanks-a7f3c92b.html`).

Why this reconciles the constraints:

- The thank-you page already (a) handles direct visits — it softens "payment
  confirmed" copy when there's no `session_id` — and (b) resolves the current DMG
  from `/appcast.xml` at load. So it's the **perfect durable link**: no hardcoded
  (hashed) DMG filename, works forever across releases.
- The link lives **only in buyers' inboxes**, never on the public site, so casual
  visitors still hit the paywall — the hardening funnel is intact.
- No licence key, no gating — consistent with `licensing.md` *Enforcement: None*.
  The email is a *courtesy*, not an entitlement. (Anyone reading the appcast can
  already get the build; that's an accepted ceiling.)

## 3. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Host** | **Cloudflare Worker** | DNS + site already on Cloudflare; first-party, ~free, no server to run. |
| **Deploy** | **GitHub Actions** (`deploy-worker.yml`) | Consistent with the other workflows (`pages.yml`/`release.yml`); no manual `wrangler` step. Worker secrets are synced from GitHub Actions secrets on each deploy, so GitHub is the single source of truth. |
| **Email sender** | **Resend** | Simple HTTP API, free tier (3k/mo) covers this volume, easy domain auth. MailChannels dropped free Cloudflare sending in 2024; SES/Postmark are heavier. Isolated to this Worker — **not** an app dependency. |
| **Trigger** | `checkout.session.completed` | Fires for Managed Payments payment links; carries `customer_details.email`. |
| **Link target** | `thanks-a7f3c92b.html` | Reuse — already direct-visit-safe and appcast-resolving. No new page. |
| **Signature** | **Verify `Stripe-Signature`** (HMAC-SHA256 via Web Crypto) | Webhook endpoints are public; an unverified endpoint lets anyone spam emails. Non-negotiable. |

## 4. Security

- **Verify the webhook signature** against `STRIPE_WEBHOOK_SECRET` before doing
  anything. Reject (400) on missing/invalid signature or a timestamp outside a
  5-minute tolerance (replay guard). Handle multiple `v1` signatures (secret
  rotation).
- Only act on `checkout.session.completed`; 200-ignore everything else.
- Secrets (`STRIPE_WEBHOOK_SECRET`, `RESEND_API_KEY`) are Worker secrets via
  `wrangler secret put` — never committed.

## 5. Delivery semantics

- **At-least-once**: Stripe retries on non-2xx. A transient Resend failure returns
  500 so Stripe retries. A duplicate email is low-harm and acceptable for v1.
- **Optional hardening (deferred)**: dedupe on `session.id` in a Workers KV
  namespace if duplicates ever become a problem. Not built in v1 — flagged here.
- If `customer_details.email` is absent (shouldn't happen for card checkout),
  200-ignore rather than erroring.

## 6. Config & deploy (one-time)

Deploy is via **GitHub Actions** (`.github/workflows/deploy-worker.yml`): push to
`main` touching `workers/purchase-email/**`, or run the workflow manually. Worker
secrets are synced from GitHub Actions secrets on each deploy. See
`workers/purchase-email/README.md` for the click-by-click. Summary:

1. **Resend**: verify the `sharepad.co` sending domain (SPF/DKIM DNS records — added
   in Cloudflare), create an API key.
2. Set GitHub repo **Actions secrets**: `CLOUDFLARE_API_TOKEN`,
   `CLOUDFLARE_ACCOUNT_ID`, `RESEND_API_KEY`.
3. Merge/dispatch → Worker deploys (inert until the Stripe secret exists: it safely
   rejects all webhooks when `STRIPE_WEBHOOK_SECRET` is empty).
4. **Stripe → Developers → Webhooks**: add endpoint = the Worker's `*.workers.dev`
   URL, event = `checkout.session.completed`; copy the `whsec_…` signing secret.
5. Add `STRIPE_WEBHOOK_SECRET` to the repo secrets, re-run the workflow.

## 7. Verification (pending)

Cannot be proven until deployed. The "done" checklist:

1. `stripe trigger checkout.session.completed` (Stripe CLI) → Worker returns 200,
   email arrives with a working download button.
2. Tamper with the body or drop the signature → Worker returns 400, **no** email.
3. A **real live test purchase** (own card, then refund) → receipt *and* the
   re-download email both arrive; the link downloads the current DMG.
4. Confirm the email link still works after a subsequent release (appcast
   resolution picks up the new hashed DMG).

## 8. Open questions

1. **Sender address** — `hello@sharepad.co` vs `noreply@…`? (Proposed:
   `hello@sharepad.co` so replies reach support.)
2. **KV dedupe** — add now or wait for evidence of duplicates? (Proposed: wait.)
3. **Worker route** — `*.workers.dev` URL, or a `sharepad.co/...` route? Either
   works for a Stripe webhook target; `workers.dev` is simplest.

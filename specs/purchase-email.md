# Purchase Email (licence key + download link) — Spec

> Status: **shipped — live 2026-06-14** (see `CHANGELOG.md` 1.1.0). Originally
> accepted as a link-only courtesy (2026-06-07); folded into the 7-day trial +
> Ed25519 licence-key gate, so the single post-purchase email now carries the
> **licence key *and* the download link**. Siblings: `specs/licensing.md` (v2 —
> honor-system soft gate), `specs/marketing-copy.md` §3–§4 (email copy + wiring),
> `specs/purchase-flow.md` (flow + Stripe config), `specs/download-url-hardening.md`
> (why the DMG URL is unguessable), `specs/distribution.md` (release pipeline).

## 1. Problem & goal

A buyer who closes the post-checkout thank-you tab has **no way back to their
download** — and, under the v2 gate (`specs/licensing.md`), **no copy of their
licence key**. We're on **Stripe Managed Payments (Stripe = merchant of record)**,
and Stripe *owns* the receipt/confirmation emails — `custom_text` and
`invoice_creation` are unsupported under Managed Payments, and "your receipt
settings don't affect these emails." So we **cannot inject anything into Stripe's
email**.

Goal: every buyer gets, in one email in their inbox, both a **durable re-download
link** and their **offline licence key** — without publishing the download link on
the marketing site (which would defeat the download-URL-hardening funnel — see that
spec).

## 2. Approach

A small **Cloudflare Worker** (`sharepad-purchase-email`) subscribes to the Stripe
`checkout.session.completed` webhook and sends one branded email carrying both the
**existing thank-you page URL** (`https://sharepad.co/thanks-a7f3c92b.html?owner`)
**and the buyer's licence key**. The key is the Ed25519 signature of the
normalised buyer email, derived in the worker from `ED25519_PRIVATE_KEY` (the same
signing key the `sharepad-licenses` worker holds), so issuance needs no database —
`specs/licensing.md` §3.

Why this reconciles the constraints:

- The thank-you page resolves the current DMG from `/appcast.xml` at load, so it's
  the **perfect durable link**: no hardcoded (hashed) DMG filename, works forever
  across releases. The `?owner` param selects its re-download view (a plain
  download, no buy prompt); a visit without it shows the buy page.
- The link lives **only in buyers' inboxes**, never on the public site, so casual
  visitors still hit the buy page; the hardening funnel is intact.
- The email is the buyer's durable copy of their **entitlement**, not just a
  download convenience. This is the **honor-system soft gate** of `licensing.md`
  v2: the official build runs a 7-day trial, then asks for a licence key; the key
  in this email is what clears that gate. The gate is honor-system by design
  (source builders can compile it out, and the key derives deterministically from
  the email so it's always re-recoverable at `/recover`) — we sell convenience,
  not enforcement.

## 3. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Host** | **Cloudflare Worker** | DNS + site already on Cloudflare; first-party, ~free, no server to run. |
| **Deploy** | **GitHub Actions** (`deploy-worker.yml`) | Consistent with the other workflows (`pages.yml`/`release.yml`); no manual `wrangler` step. Worker secrets are synced from GitHub Actions secrets on each deploy, so GitHub is the single source of truth. |
| **Email sender** | **Resend** | Simple HTTP API, free tier (3k/mo) covers this volume, easy domain auth. MailChannels dropped free Cloudflare sending in 2024; SES/Postmark are heavier. Isolated to this Worker — **not** an app dependency. |
| **Trigger** | `checkout.session.completed` (paid only) | Fires for Managed Payments payment links; carries `customer_details.email`. Ignore non-`paid` sessions (async payment methods can complete unpaid). |
| **Link target** | `thanks-a7f3c92b.html?owner` | Reuse: already appcast-resolving; `?owner` gives the re-download view. No new page. |
| **Licence key** | **Derived in-worker** (Ed25519-sign the normalised email; base64url) | No database: keys are deterministic, so the email is the buyer's copy and `/recover` re-derives it. Needs `ED25519_PRIVATE_KEY` — the same signing key as `sharepad-licenses` (`licensing.md` §3–§4). |
| **One email** | Download link **and** key in a single send | The webhook fires exactly-once per paid checkout; one email avoids a second, separate "here's your key" message. `sharepad-licenses` sends *no* email — it only serves `/recover` (and an optional `/key` page). |
| **Signature** | **Verify `Stripe-Signature`** (HMAC-SHA256 via Web Crypto) | Webhook endpoints are public; an unverified endpoint lets anyone spam emails. Non-negotiable. |

## 4. Security

- **Verify the webhook signature** against `STRIPE_WEBHOOK_SECRET` before doing
  anything. Reject (400) on missing/invalid signature or a timestamp outside a
  5-minute tolerance (replay guard). Handle multiple `v1` signatures (secret
  rotation).
- Only act on `checkout.session.completed`; 200-ignore everything else (and
  200-ignore a completed-but-unpaid session, and a session with no buyer email).
- Secrets (`STRIPE_WEBHOOK_SECRET`, `RESEND_API_KEY`, `ED25519_PRIVATE_KEY`) are
  Worker secrets synced from GitHub Actions secrets on deploy — never committed.
  `ED25519_PRIVATE_KEY` is the **signing private key** and must match the
  `sharepad-licenses` worker's value, or the app rejects every emailed key.

## 5. Delivery semantics

- **At-least-once**: Stripe retries on non-2xx. A transient Resend failure returns
  500 so Stripe retries. A duplicate email is low-harm and acceptable for v1.
- **Optional hardening (deferred)**: dedupe on `session.id` in a Workers KV
  namespace if duplicates ever become a problem. Not built in v1 — flagged here.
- A completed session with `payment_status !== "paid"` (async/delayed methods)
  200-ignores — no key is issued until the payment clears.
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
   `CLOUDFLARE_ACCOUNT_ID`, `RESEND_API_KEY`, `ED25519_PRIVATE_KEY` (the same
   signing key the `sharepad-licenses` worker uses).
3. Merge/dispatch → Worker deploys (inert until the Stripe secret exists: it safely
   rejects all webhooks when `STRIPE_WEBHOOK_SECRET` is empty).
4. **Stripe → Developers → Webhooks**: add endpoint = the Worker's `*.workers.dev`
   URL, event = `checkout.session.completed`; copy the `whsec_…` signing secret.
5. Add `STRIPE_WEBHOOK_SECRET` to the repo secrets, re-run the workflow.

## 7. Verification (done at deploy, 2026-06-14)

The "done" checklist that was run:

1. `stripe trigger checkout.session.completed` (Stripe CLI) → Worker returns 200,
   email arrives with a working download button **and** a licence key.
2. The emailed key pastes into the app's "Enter licence…" and clears the trial
   gate (it must match `ED25519_PRIVATE_KEY` ↔ the app's embedded public key).
3. Tamper with the body or drop the signature → Worker returns 400, **no** email.
4. A **real live test purchase** (own card, then refund) → receipt *and* the
   licence-and-download email both arrive; the link downloads the current DMG and
   the key activates.
5. Confirm the email link still works after a subsequent release (appcast
   resolution picks up the new hashed DMG).

## 8. Open questions

1. ~~**Sender address**~~ — **resolved**: `hello@sharepad.co` (the `EMAIL_FROM`
   default), so replies reach support — the email invites "just reply to this email".
2. **KV dedupe** — add now or wait for evidence of duplicates? (Shipped without it;
   relies on the exactly-once webhook + at-least-once retry of §5. Revisit only if
   duplicates appear.)
3. ~~**Worker route**~~ — **resolved**: a `*.workers.dev` URL is the Stripe webhook
   target; the licences worker (`/recover`) is reached at
   `sharepad-licenses.jonyardley.workers.dev`.

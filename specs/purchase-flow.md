# SharePad — Purchase & Trial Flow

> How the trial -> purchase -> activation journey works end to end, the unhappy
> paths, the "buy again" decision, and the Stripe configuration it needs. Sits
> alongside `specs/licensing.md` (the design) and `specs/marketing-copy.md` (the
> words). No emojis.

## The one fact that shapes everything

A licence **key is a deterministic Ed25519 signature of the buyer's email.** Same
email in, same key out, forever. There is **no database** — Stripe itself is the
record of who paid, and `/recover` simply re-derives the key for any email with a
paid session. This is what makes the app account-free and fully offline, and it is
why "buy again" behaves the way it does (below).

## Happy path

1. **Trial.** Download (free). First launch seeds a 7-day trial. Popover shows
   "Free trial — N days left". Everything works.
2. **Expiry.** After 7 days the share window pauses ~5 min into each session behind
   an overlay; relaunch resets it (honor system). Popover shows "Free trial ended".
3. **Buy.** "Buy a licence" opens `buy.sharepad.co` -> 302 -> Stripe Checkout
   (GBP 6.99, Apple Pay or card). Buyer pays.
4. **Deliver.** Two paths, both fed by the same email-derived key:
   - **Email (primary, exactly-once):** the `sharepad-purchase-email` webhook fires
     on `checkout.session.completed`, derives the key, and sends one branded email
     with the **download link + licence key**.
   - **Page (instant, optional):** if the Payment Link redirects to the
     `sharepad-licenses` worker `/key?session_id=...`, that page also shows the key.
   `/recover` re-derives the key for any paid email at any time.
5. **Activate.** Buyer opens SharePad -> Enter licence... -> pastes email + key.
   The app validates it **offline** against the embedded public key -> Licensed.
   The pause stops and the Buy button disappears.

One purchase covers all the buyer's Macs (re-enter the same email + key); the
licence is bound to the email, not the machine.

## Unhappy paths

| Situation | Handling |
|---|---|
| Card declined / payment fails | Stripe shows the error; no redirect, no key. Retry. |
| Paid, but closed the tab before `/key` | The **email** delivers the key; **`/recover`** re-derives it anytime. |
| Email never arrives (spam / Resend down) | `/key` page already showed it; `/recover` is the durable fallback. |
| `/key` with a bad/expired `session_id` | "Purchase not found" (404) + recover hint. |
| Stripe API down during `/key` or `/recover` | "Temporary problem — try again" (502), not a false 404. |
| Worker misconfigured (bad signing key) | "Something went wrong" (500), distinct from a Stripe outage. |
| Wrong email at `/recover` | "No purchase found" (404). Mitigated by "use your checkout email" copy. |
| Wrong email/key in the app | "That key doesn't match this email — check both." |
| New Mac / reinstall, lost key | Re-enter email + key, or `/recover`. No account needed. |
| Refund / chargeback, keeps using it | Key still works (offline, no revocation). Accepted — honor-system gate. |
| Deletes app data during trial | Trial resets to a fresh 7 days. Accepted — honor system. |

The last two are deliberate consequences of the offline + honor-system design;
closing them would require an activation server, which is exactly what we avoid.

## "Buy again" — decision: one licence per email, unlimited emails

Because the key is derived from the email:
- **Same email twice** -> the **identical key**. They have paid twice for the same
  thing. Always a mistake.
- **Different email** -> a second, genuinely valid licence (a gift, a colleague).

So **do not hard-limit purchases** — it would block legitimate gift/team buys, and
Payment Links cannot do "one per customer" anyway (their limit is a global total).
Instead, make a duplicate unnecessary and detectable:

1. The app hides "Buy" once licensed — a happy owner never sees it. (Done.)
2. Recovery is the obvious answer to "I lost my key": the email, the `/recover`
   page, the "recover anytime, no account" line, and a "you don't need to buy
   again" nudge on the recover page. (Done.)
3. Refund accidental same-email duplicates by hand (trivial volume at GBP 6.99).
   If duplicates ever get common, extend the existing `sharepad-purchase-email`
   webhook to auto-refund a second same-email payment — the webhook is already
   there, so this is a small add when it's worth it.

## Delivery architecture

- **`sharepad-purchase-email`** (webhook, `checkout.session.completed`): the single
  exactly-once post-purchase email — download link + licence key. Needs
  `STRIPE_WEBHOOK_SECRET`, `RESEND_API_KEY`, and `ED25519_PRIVATE_KEY` (same value
  as the licences worker).
- **`sharepad-licenses`** (`/key`, `/recover`): `/recover` is the self-service
  "lost my key" path; `/key` optionally shows the key instantly if the Payment
  Link redirects there. No email is sent from here (the webhook owns email).

Both Workers deploy via GitHub Actions on push to `main` (paths `worker/**` and
`workers/purchase-email/**`), running their `npm test` first. Secrets are synced
from GitHub Actions secrets — GitHub is the source of truth, not manual `wrangler
secret put`. Required repo secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`,
`ED25519_PRIVATE_KEY` (both Workers), `STRIPE_API_KEY` (licences), `RESEND_API_KEY`
+ `STRIPE_WEBHOOK_SECRET` (purchase-email).

## Stripe configuration

**Do before launch (wiring + hygiene):**
1. **Receipt emails** on (Settings -> Customer emails -> Successful payments).
2. **Statement descriptor -> `SHAREPAD`** (otherwise it reads "Yardley Software"
   and invites "what's this charge?" disputes).
3. **Turn off "let customers adjust quantity"** — a per-email licence has no
   "buy 5 of".
4. **Link Terms & refunds** (`docs/terms.html`) in checkout.
5. *(Optional)* point the success redirect at the `sharepad-licenses` worker
   `/key?session_id={CHECKOUT_SESSION_ID}` for an instant on-screen key; not
   required, since the webhook email already delivers it.

**Confirm (likely already true):** the `checkout.session.completed` webhook is
configured and points at `sharepad-purchase-email`; email is collected at checkout;
Apple Pay / wallets on; Managed Payments handles tax (merchant of record).

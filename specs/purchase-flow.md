# SharePad — Purchase & Trial Flow

> How the trial → purchase → activation journey works end to end, the unhappy
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
4. **Deliver.** Stripe redirects to the worker `/key?session_id=...`. The worker
   confirms the session is paid via the Stripe API, derives the key from the
   buyer's email, shows it, and emails it (best-effort).
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
   If duplicates ever get common, add a `checkout.session.completed` webhook that
   auto-refunds a second same-email payment and re-sends the key — deferred,
   because it reopens the "no webhook" stance.

## Stripe configuration

**Do before launch (wiring + hygiene):**
1. **Success redirect** on the Payment Link: *Don't show confirmation page ->
   Redirect to* `https://<worker>/key?session_id={CHECKOUT_SESSION_ID}` (keep the
   placeholder literal). This is the link that delivers the key.
2. **Receipt emails** on (Settings -> Customer emails -> Successful payments).
3. **Statement descriptor -> `SHAREPAD`** (otherwise it reads "Yardley Software"
   and invites "what's this charge?" disputes).
4. **Turn off "let customers adjust quantity"** — a per-email licence has no
   "buy 5 of".
5. **Link Terms & refunds** (`docs/terms.html`) in checkout.

**Confirm (likely already true):** email is collected at checkout (the worker needs
`customer_details.email`); Apple Pay / wallets on; Managed Payments handles tax
(merchant of record).

**Later, only if needed:** a `checkout.session.completed` webhook for exactly-once
licence email + auto-refund of same-email duplicates.

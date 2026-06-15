# Recover delivers the key by email, not on-screen — Spec

> Status: **proposed** (2026-06-15). A small security hardening of the
> `sharepad-licenses` worker's `/recover` route. Siblings: `specs/licensing.md`
> (§4 checkout backend, §8 open questions), `specs/purchase-flow.md` (delivery
> architecture), `specs/purchase-email.md` (the post-purchase email), and
> `specs/marketing-copy.md` §2 (recover-page copy). No emojis.

## 1. Problem

`/recover` is an **open key oracle**. It takes an email, confirms via the Stripe
API that the email has a paid checkout, then **renders the working licence key on
the page** ([`workers/licenses/src/index.mjs`](../workers/licenses/src/index.mjs)
`recoverPage`). The Stripe check proves *"this email bought SharePad"* — it does
**not** prove *"you control this email."*

So the effective gate is **knowing a buyer's email = a free working key**, slowed
only by a 5 req/min/IP rate limit. `specs/licensing.md` §4 calls `/recover`
"gated by purchase existence, so it leaks nothing" — that claim is wrong: it leaks
the key to anyone who can name a customer's email.

## 2. What this does and does not fix (honest framing)

- **Fixes (real):** raises the bar from *know the email* to *control the inbox* —
  the standard send-to-registered-address recovery pattern. Closes the recovery
  oracle.
- **Does NOT fix (by design):** keys are deterministic Ed25519 signatures,
  validated fully offline, non-revocable. A legitimate buyer can still paste their
  key anywhere. Nothing in the offline + honor-system model (`specs/licensing.md`)
  can stop deliberate sharing, and this change does not pretend to. This is
  friction in the right place, not enforcement.

Frame it as *close the recovery oracle*, not *stop piracy*.

## 3. Approach

`/recover` **emails** the key to the address instead of displaying it, then
returns a neutral "check your inbox" page. The licence key never appears in an
HTTP response again from this route.

`/key` is **unchanged**: it still renders the key inline. `/key` is reached only
via a fresh Stripe `session_id` redirect immediately after checkout, where the
buyer is present in that session — it is not an open oracle the way `/recover` is.

### Send path

The `sharepad-licenses` worker gains its own Resend send, mirroring the
self-contained pattern of `sharepad-purchase-email` (the two workers already each
carry their own copy of the `license.mjs` helpers — there is no shared package,
and we are not introducing one for one function). A dedicated, slimmer recover
email — "Here is your SharePad licence key" — carries the email, the key,
activation instructions, and the download button (the common recover case is a new
Mac, so the download link is useful there).

### Preserved guards

- **Stripe paid-check stays before sending.** `/recover` only ever emails an
  address that has a paid Stripe session, so it cannot be turned into an
  open email relay to arbitrary addresses.
- **Rate limit stays** (5 req/min/IP). It now also caps how often someone can
  trigger a recover email to a real customer's inbox.

### Failure handling

- Resend send failure → a distinct 502 "couldn't send right now, try again" page.
  The key is **never** shown as a fallback. Distinguished from the existing Stripe
  outage 502 only by copy.
- Misconfigured signing key → 500 (unchanged).

## 4. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Where email is sent from | **In the `sharepad-licenses` worker itself** (own Resend call) | Mirrors the self-contained `purchase-email` worker; avoids coupling `/recover` to the webhook worker. The workers already duplicate `license.mjs`; one more small duplication is consistent. |
| `/key` behaviour | **Unchanged — still shows the key** | Reached via a fresh post-checkout `session_id`; the buyer is present. Not an open oracle. |
| Recover email content | **Dedicated slim email**: email + key + activation + download button | Different moment from "thanks for buying"; the new-Mac case wants the download too. |
| Response after sending | **Neutral "check your inbox" page**, echoing the (escaped) address | Confirms the send without ever returning the key. |
| Typo'd / non-buyer email | **Keep the friendly "no purchase found" (404)** | Helps the legitimate typo case. The thing that matters — the key — now needs inbox control regardless; bare customer-email enumeration is low-value and unaffected by the offline model. (Strict identical-response alternative noted in §7.) |
| New secret | **`RESEND_API_KEY`** synced to the licences worker via its deploy workflow | The repo secret already exists (used by `purchase-email`); add it to `deploy-licenses-worker.yml`'s synced secrets. `EMAIL_FROM` / `DOWNLOAD_URL` use in-code defaults like `purchase-email`, so no new config vars. |

## 5. Files touched

- `workers/licenses/src/index.mjs` — `recoverPage` sends email + returns the
  confirmation page; add `sendRecoverEmail` / `recoverEmailHtml` /
  `recoverEmailText` and an `EmailUnavailableError` → 502 path. `keyHtml` stays
  for `/key` only.
- `workers/licenses/test/index.test.mjs` — the two "/recover ... shows the key"
  tests become "emails the key, does not show it"; route the `fetch` stub by host
  (Stripe vs Resend); add a Resend-failure-is-502 test and assert the key never
  appears in any `/recover` body.
- `.github/workflows/deploy-licenses-worker.yml` — add `RESEND_API_KEY` to the
  synced secrets.
- Cross-ref doc updates: `specs/licensing.md` (§4 "leaks nothing" correction; §8
  note), `specs/purchase-flow.md` (delivery architecture: `/recover` now emails),
  `specs/marketing-copy.md` (its copy already says "send your key straight back" —
  now accurate; note the change).
- **No `CHANGELOG.md` entry**: that file is the in-app Sparkle update note, and
  this is a worker-only change (web `/recover` page + email) with no app release.

## 6. Verification

Worker unit tests (`npm test` in `workers/licenses`) cover the logic — no hardware
needed:

1. `/recover` with a paid email → 200, a Resend send happened, body says "inbox",
   body contains **no** key.
2. Resend failure → 502, no key in body.
3. Non-buyer email → 404 (unchanged).
4. Rate-limit denial → 429 (unchanged).
5. `/key` with a paid session still shows the key (unchanged).

At deploy: confirm `RESEND_API_KEY` is synced, then a live `/recover` with a real
paid email lands the key in the inbox and the page shows only the confirmation.

## 7. Open questions

1. **Strict anti-enumeration** — return an identical "if that email bought
   SharePad, we've emailed the key" for both buyer and non-buyer, hiding customer
   status entirely? Rejected for v1 (hurts the typo case; low value given the
   offline model), but trivial to switch later. Flagged.
2. **Per-email rate limit** — the limiter is per-IP. A per-email cap would further
   limit recover-email bombing of one customer. Deferred; the per-IP limit +
   paid-check is enough at this volume.

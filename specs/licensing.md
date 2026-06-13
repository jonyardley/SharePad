# Licensing & Monetisation — Spec (v2)

> Status: **app + worker landed 2026-06-13; Stripe/Cloudflare deployment + live
> URLs pending — §8.**
>
> **Reopens the 2026-06-07 "no-gate" decision.** That decision shipped a live
> Stripe Managed Payments storefront (£6.99 one-time, `buy.sharepad.co`,
> sell-the-build, *no* trial / keys / in-app gate). This v2 deliberately adds a
> 7-day in-app trial + offline licence-key gate on top of that storefront — an
> **honor-system soft gate** (source builders can still compile it out), trading
> the "byte-for-byte identical build" property for conversion. The existing
> `buy.sharepad.co` storefront is reused as the Buy destination; wiring checkout
> to licence-key issuance (the `worker/` route) is the pending deployment step.
> Sibling: `specs/distribution.md` (release pipeline this builds on).

## 1. Problem & goal

Sell SharePad to fund its development, while keeping it **open source** (GPLv3).
v1 concluded enforcement is pointless on open source — that still holds. What
changed: a completely frictionless "buy if you feel like it" model converts ~no
one. The goal is **friendly friction**: a real trial and a real purchase step in
the official build, implemented as an **honor-system soft gate** that source
builders can compile out. We sell convenience, not enforcement.

## 2. Decisions (locked, 2026-06-12)

| Decision | Choice | Rationale |
|---|---|---|
| Source licence | **GPLv3** (unchanged) | Still truly open source; the gate is honor-system by design. |
| Price model | **One-time purchase**, all updates included | Right weight for a single-purpose menu-bar utility. Price set in the Stripe dashboard (open question — not load-bearing). |
| Trial | **7 days**, full-featured, starts at first launch | Client-side only; no server involvement. |
| Expired-trial gate | **Session limit**: share window works ~5 min/session, then a polite overlay; app relaunch (or window re-show) resets it; a trial expiring while the window is already open gates on the next show — deliberate honor-system leniency | Converts daily users without ever bricking someone mid-meeting — they can always restart. |
| Checkout | **Stripe Managed Payments** (merchant of record on Jon's existing Stripe account) + **Stripe Payment Link**, opened in the default browser | MoR handles global VAT/sales tax (the thing that made self-remittance a non-starter); ~3.5% on top of standard processing, ≈6–7% all-in. Browser checkout beats an embedded webview for autofill/Apple Pay/trust. |
| Licence keys | **Offline-signed**: Ed25519 signature of the buyer's email, base64url-encoded; app verifies with an embedded public key via CryptoKit | No activation server, no network calls, works offline forever, no third-party dependency (~50 lines, no CocoaFob). |
| Key issuance | **One Cloudflare Worker, two GET routes, no webhook, no database** | Ed25519 signatures are deterministic → a key can always be re-derived from the email; Stripe itself is the purchase record. |
| Storefront | **Reuse the existing live `buy.sharepad.co`** (Stripe MP, £6.99) — the in-app Buy affordances point there | The no-gate model already shipped this storefront; the gate layers on top rather than replacing it. Wiring checkout success → key issuance is the pending step (§8). |

Anti-goals (out of scope): subscriptions, device-count activation limits,
embedded webview checkout, online revocation, obfuscating or hardening the gate.

## 3. Licence key scheme

```text
key = base64url( Ed25519-sign(privateKey, lowercase(trim(email))) )
```

- The **private key** exists only as a Cloudflare Worker secret.
- The **public key** is embedded in the app; `LicenseValidator` checks
  `verify(key, email)` locally with CryptoKit.
- "Enter licence" = email + key fields. Valid → licensed forever; persisted via
  `Preferences` (UserDefaults).
- Deterministic signatures ⇒ lost keys are recovered by **regenerating**, not
  looking up — no key database anywhere.
- Existing `buy.sharepad.co` buyers (from the no-gate era): mint keys manually
  with a one-off script (`worker/scripts/mint-key.mjs`) using the same signing key.

## 4. Checkout backend (Cloudflare Worker)

- **Buy** opens the existing live **`buy.sharepad.co`** Stripe link. To issue keys,
  its checkout success URL must redirect to
  `https://<worker>/key?session_id={CHECKOUT_SESSION_ID}` (the pending wiring step).
- **`GET /key`** — verifies via the Stripe API that the Checkout Session is paid,
  derives the key from the buyer's email, renders it on a small branded page
  (with a note that it's recoverable anytime at `/recover`).
- **`GET /recover`** — email form → look up a completed purchase for that email
  in Stripe → re-show the key. Gated by purchase existence, so it leaks nothing.
- Secrets: the Ed25519 private key + a **restricted** Stripe API key (read
  Checkout Sessions / Customers only).
- Optional later nicety: email the key via Resend on purchase. Not v1.

**Note:** Stripe Managed Payments is already live for the no-gate storefront
(`buy.sharepad.co`), so SMP availability is settled. The remaining work is wiring
that checkout's success URL to the worker's `/key` route (§8).

## 5. In-app architecture

Follows the existing non-negotiables (pure reducers, dumb views, state in
`AppModel`).

- **New `Sources/SharePad/Licensing/`**:
  - `LicenseValidator` — pure CryptoKit signature check.
  - `EntitlementClock` — pure function
    `(firstLaunchDate, now, licenseStatus) → Entitlement` where
    `Entitlement = .trial(daysLeft) | .trialExpired | .licensed`.
  - No AVFoundation imports; both fully unit-tested.
- **`AppModel`** owns entitlement state and the session-limit timer: starts when
  the share window opens while `.trialExpired`, fires at 5 minutes. Never runs
  mid-trial or when licensed. Views render state and send intents only.
- **Gate overlay**: at the limit, an opaque full-window overlay renders *in* the
  share window ("Your free trial has ended — buy a licence to keep sharing your
  iPad" + Buy button). Copy never mentions the relaunch reset (honor-system, but
  don't advertise the bypass). The capture session keeps running underneath;
  relaunching resets the session.
- **Popover**: a status row — "Free trial — N days left" / "Free trial ended — sharing
  pauses after 5 min" — with **Buy** (opens `buy.sharepad.co`) and **Enter
  licence…** (sheet: email + key). Licensed state stays quiet.
- **Trial start** = first-launch date in UserDefaults. Deliberately resettable —
  honor system; no hide-the-timestamp games. If `now < firstLaunchDate` (clock
  set backwards), treat the trial as **expired** — never as restarted.
- **About panel / landing page / README**: left as main's live storefront
  (`buy.sharepad.co`, already Gumroad-free); the in-app Buy affordances point
  there. Trial-aware marketing copy waits until the gate is deployment-wired.

## 6. Testing

- **Unit**: `LicenseValidator` (valid / invalid / tampered / wrong-email key),
  `EntitlementClock` (day boundaries, backwards clock, licensed overrides trial,
  expiry exactly at day 7).
- **Manual** (the part that counts):
  1. Stripe **test mode** end-to-end: Payment Link → pay → `/key` page shows key
     → paste into app → licensed persists across relaunch.
  2. `/recover` returns the same key for a paid email; rejects an unknown email.
  3. 5-minute overlay appears (debug-shortened limit), restart resets, Buy
     button opens checkout; overlay never appears mid-trial or licensed.
  4. Gate changes don't touch capture — share still works in Zoom + a browser
     meeting (standard capture checklist).

## 7. Rollout order

1. Worker + Payment Link in Stripe test mode; verify SMP (§4 blocking check).
2. App-side gate (`Licensing/`, `AppModel`, popover, overlay) behind it.
3. Wire `buy.sharepad.co` checkout success → worker `/key`; mint keys for existing
   `buy.sharepad.co` buyers.
4. Add trial-aware copy to the landing page once the gate is live.
5. Release via the existing Sparkle pipeline (`specs/distribution.md`).

## 8. Open questions

1. ~~**Price**~~ — **resolved**: £6.99 one-time, already live on `buy.sharepad.co`.
2. **Worker domain** — workers.dev subdomain vs a custom domain on the existing
   gh-pages site's DNS. *(pending deployment)*
3. ~~**SMP availability**~~ — **resolved**: Stripe Managed Payments is already live
   for the no-gate storefront, so eligibility is settled.
4. **Past-buyer outreach** — how to reach existing `buy.sharepad.co` buyers with
   their minted keys (Stripe customer export).
5. **/recover rate limit** — add a Cloudflare rate-limiting rule (e.g. 5 req/min/IP)
   at deployment; it's a purchase oracle and each probe costs a Stripe API call.

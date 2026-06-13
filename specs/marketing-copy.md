# SharePad — Marketing & Lifecycle Copy

> Single source of truth for the words across the buyer journey. One voice
> throughout: **free trial -> one-time GBP 6.99 licence -> works offline, no
> account, recover anytime, no subscription.** No emojis. British spelling.
>
> Touchpoints: marketing site (`docs/`, live), Stripe checkout + thank-you page,
> the licence-delivery email (`worker/src/email.mjs`), and the in-app copy
> (popover / overlay / licence sheet — see `Sources/SharePad/UI/`). Keep them in
> step; if you change a promise here, change it everywhere.

> **Constraint:** the 7-day trial is entirely client-side with no account or
> email capture (the privacy win — the app never phones home). So there is **no
> way to email trial users** (no "trial ending" nudges). Email starts at the
> receipt, after purchase.

---

## 1. Marketing site (`docs/index.html`) — apply when the gate ships

### Hero
- **Headline:** Share your thinking, not just your screen.
- **Sub:** SharePad turns a USB-connected iPad into a clean, always-ready window
  you share in any call. Plug in, and the window opens itself — pick it from the
  "Share window" list and your drawing app is live. No mid-call faff.
- **CTAs:** `Download — free for 7 days` (primary) · `Buy a licence — GBP 6.99`
- **Reassurance line:** macOS 14+ · signed & notarized · one-time payment, no subscription

### How it works
1. **Plug in your iPad** over USB. SharePad opens a clean, aspect-locked window automatically.
2. **Pick it in your call** — it appears in Zoom, Meet, or Teams' "Share window" list, clearly named.
3. **Draw.** Your favourite whiteboard app fills the shared window — full-size, not a tiny webcam tile.

### Why it's different
- **A window, not a webcam.** Screen-sharing a drawing app means hunting for the
  right window mid-call; a virtual camera shrinks your work to a corner tile.
  SharePad gives the iPad its own clean, full-size shared window.
- **Always ready.** Plug in once; it reconnects through sleep, wake, and
  unplug/replug on its own. No per-call QuickTime ritual.
- **Yours, privately.** No account, no cloud, no telemetry. The feed goes over
  USB to your Mac and nowhere else.

### Trial & pricing
- **Heading:** Try it free for 7 days. Keep it for GBP 6.99.
- **Body:** Use every feature free for a week — no card, no account. After that, a
  one-time GBP 6.99 licence keeps it running. One payment, updates for life, no
  subscription. Works fully offline, and you can recover your licence anytime.

### FAQ
- **Is it a subscription?** No — one payment, and all future updates are included.
- **Do I need an account?** No. The trial needs nothing, and your licence is just
  an email + key you enter once. It works offline; SharePad never checks in with a server.
- **What happens after the trial?** The app keeps working; sharing just pauses
  periodically until you add a licence. Nothing is deleted, and a licence removes
  the pause instantly.
- **Lost my licence key?** Recover it anytime with your purchase email — no account needed.
- **Is it really open source?** Yes, GPLv3. You can read or build the source
  yourself; buying gets you the signed, notarized, auto-updating build and supports development.

### Footer
macOS 14+ · signed & notarized · works offline · open source (GPLv3) · made by Yardley Software

---

## 2. Stripe

- **Product name:** SharePad
- **Statement descriptor:** `SHAREPAD` (so it is recognisable on bank statements —
  otherwise it shows "Yardley Software", which buyers may not recognise).
- **Settings to check:** enable customer receipt emails; set a recognisable public
  business name and a support email.

### Product description (checkout)
Share your thinking, not just your screen. SharePad turns your iPad into a live
whiteboard you share in any call. Connect to your Mac over USB and a clean window
opens automatically — pick it from the "Share window" list in Zoom, Meet, or Teams
and your drawing app is ready, full-size. No mid-call faff. One-time payment,
updates for life, no subscription. Works offline; recover your licence anytime.

### Post-payment thank-you page (`docs/thanks-*.html`)
- **Heading:** You're all set — thanks for backing SharePad.
- **Body:**
  Your licence and key are on their way to your email. To activate:
  1. Open SharePad from the menu bar -> Enter licence...
  2. Paste the email you used here and your key.
  It activates instantly and works offline. Lost your key later? Recover it
  anytime — no account needed.
- **CTA:** `Download SharePad` (for anyone who has not already)

---

## 3. Email — licence delivery (`worker/src/email.mjs`)

Stripe sends the receipt automatically. This is the durable key-delivery email.
Implemented as best-effort in the worker; sends only once `RESEND_API_KEY` (and
optionally `RESEND_FROM`) are configured. See §4.

- **Subject:** Your SharePad licence
- **Body:**
  Thanks for buying SharePad — here is your one-time licence.

  Email: {email}
  Key: {key}

  To activate: open SharePad from the menu bar, choose "Enter licence...", and
  paste both. It activates instantly and works offline — SharePad never phones
  home to check it.

  Keep this email, or recover your key anytime at {recover_url} with the email
  above. No account needed.

  Happy sharing,
  Jon — Yardley Software

  Do not have the app yet? Download it at https://sharepad.co.

---

## 4. Wiring notes (delivery, deferred steps)

- **Licence email** is best-effort from the worker's `/key` route, gated behind
  `RESEND_API_KEY`. To turn it on: verify a sending domain in Resend, then
  `wrangler secret put RESEND_API_KEY` (and optionally set `RESEND_FROM`, default
  `SharePad <licences@sharepad.co>`).
- **Known limitation:** `/key` sends on each load, so a buyer who refreshes could
  get a duplicate. For exactly-once delivery, move the send to a Stripe webhook
  (`checkout.session.completed`) — deferred; it reopens the "no webhook" stance in
  `specs/licensing.md`, so decide deliberately.
- **Existing buyers** (from the no-gate era): mint with `worker/scripts/mint-key.mjs`
  and send by hand using the §3 copy.

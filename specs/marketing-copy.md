# SharePad — Marketing & Lifecycle Copy

> **The live site (`docs/index.html`) is the canonical voice and the source of
> truth.** This doc mirrors its tone and extends the same voice to the surfaces
> the site doesn't cover — Stripe, the thank-you page, and the licence email.
> When the wording on the site changes, this doc follows it, not the other way
> round. No emojis. British spelling.

## Voice

Honest, plain, and understated — confident without hype. It explains *how it
actually works* and trusts the reader. Section headings are short statements, not
slogans. Examples straight from the live site:

- "Share your thinking, not just your screen."
- "Turn the iPad into a live whiteboard using your favourite drawing or writing
  app. Connect it to your Mac and share in any call, without the faff."
- "Ready the moment you plug in." · "Nothing leaves your Mac." · "How it ships,
  honestly." · "Questions, answered." · "Make every call more visual."
- "£6.99 once · no subscription · macOS 14+"

> **Constraint:** the 7-day trial is entirely client-side, with no account or
> email capture (that's the privacy promise — the app never sends your data). So
> there is **no way to email trial users**. Email begins at the receipt, after
> purchase.

---

## 1. Marketing site — `docs/index.html` (canonical; this is the live copy)

Reproduced here as the reference. Edit the HTML for any change; keep this in step.

- **Title:** SharePad: Share your iPad on any call, in an instant
- **Hero:** Share your thinking, not just your screen.
  - Turn the iPad into a live whiteboard using your favourite drawing or writing
    app. Connect it to your Mac and share in any call, without the faff.
  - £6.99 once · no subscription · macOS 14+
- **See it in action.** On the left, the SharePad window. On the right, that same
  window shared into Google Meet at full size.
- **Ready the moment you plug in.** SharePad lives in your menu bar and finds your
  iPad as soon as it connects to your Mac.
  1. **Plug in the iPad** — Connect it over USB. There's nothing to install on the iPad.
  2. **The window appears** — A clean window opens automatically, matched to your
     iPad's shape so nothing looks squished. Show or hide it whenever you like.
  3. **Share it in the call** — Pick it from the "Share window" list in Zoom, Meet
     or Teams, open your favourite app, and you're ready to go.
- **Nothing leaves your Mac.** SharePad just shows the iPad in a window on your
  machine. No account, no sign-in, no in-app tracking or analytics. The only time
  it reaches the internet is an automatic check for a new version, never to send
  your data or anything about what you share.
- **How it ships, honestly.** SharePad isn't on the Mac App Store, so you download
  it straight from here.
  - £6.99, paid once. No subscription and no account, just a one-off payment, with
    automatic updates for life.
  - Every build is signed and notarised by Apple, so it opens with a normal double-click.
  - It runs outside Apple's sandbox, because that's the only way macOS will treat a
    plugged-in iPad as a camera. That's also why it can't be on the App Store.
  - The code is open, so you can read what it does.
- **Questions, answered.** Full FAQ lives in the HTML — that's canonical. It covers
  cost/updates, how to share in Zoom/Meet/Teams, nothing-to-install, "is it a
  virtual camera?", Apple Pencil/drawing apps, requirements, why-not-App-Store,
  lag, the black-window fixes, audio, notifications, and privacy.
- **Make every call more visual.** Plug in, pick the window, and draw.
  £6.99 · one-time payment · updates for life · no subscription
- **Footer:** SharePad · Privacy · Terms & refunds · GitHub

### When the trial gate ships — additions in the same voice
The live site has no trial yet. When the gate goes live, add, don't rewrite:
- Hero CTA pair: **Download — free for 7 days** and **Buy a licence — £6.99**.
- One honest line under pricing: "Try everything free for a week — no card, no
  account. After that, £6.99 keeps it yours for good."
- One FAQ entry, in the site's voice: *"What happens after the trial?"* — "The app
  keeps working; sharing just pauses now and then until you add your licence."

---

## 2. Stripe

- **Product name:** SharePad
- **Statement descriptor:** `SHAREPAD` (recognisable on a bank statement — otherwise
  it shows "Yardley Software").
- **Settings:** enable customer receipt emails; set a recognisable public business
  name and a support email.

### Product description (checkout — already live, on voice)
Share your thinking, not just your screen. SharePad turns your iPad into a live
whiteboard you can share in any call. Connect to your Mac over USB, and a clean
window opens automatically. Select from the "Share window" list in Zoom, Meet or
Teams and your favourite drawing app is ready to share. No mid-call faff. A
one-time payment with automatic updates for life, and no subscription.

### Thank-you page (`docs/thanks-*.html`)
- **Heading:** Thanks — you're all set.
- **Body:** Your licence is on its way to your email. To switch it on: open
  SharePad from the menu bar, choose "Enter licence...", and paste the email you
  used here along with your key. It takes effect straight away and works offline.
  Lost your key later? You can get it again anytime — no account needed, and no
  need to buy again.
- **CTA:** Download SharePad (for anyone who hasn't already)

### Recover page (`/recover`)
- Already bought SharePad? You don't need to buy again. Enter the email you used at
  checkout and we'll send your key straight back. (No account, no sign-in.)

---

## 3. Purchase email — `workers/purchase-email/src/worker.js`

One email, sent exactly-once by the Stripe webhook on `checkout.session.completed`:
the **download link + the licence key**. The HTML lives in `purchaseEmailHtml`.

- **Subject:** Your SharePad licence and download
- **Shape:**
  - Heading: Thanks for buying SharePad
  - Download: "Your download is ready whenever you need it, including if you ever
    switch Macs. Keep this email; the link below always points at the latest
    version." + a **Download SharePad** button, then the signed/notarised install note.
  - **Your licence:** Email + Key, then "In SharePad's menu bar, choose 'Enter
    licence...' and paste both. It takes effect straight away and works offline —
    SharePad never checks in with a server." + "Lost your key later? Get it again
    anytime at {recover_url} with the email above — no account, no sign-in."
  - Footer: open source (GPLv3), updates for life, "reply to this email" for help.

---

## 4. Wiring notes

- **The purchase email** is sent by the `sharepad-purchase-email` webhook worker,
  exactly-once per paid checkout. It needs `STRIPE_WEBHOOK_SECRET`, `RESEND_API_KEY`,
  and `ED25519_PRIVATE_KEY` (same value as the licences worker). Deploy it *with* the
  gated app release — until then, a no-gate buyer would get a key they can't yet use.
- **`sharepad-licenses`** worker: `/recover` (self-service re-derivation) and an
  optional `/key` page. It does not send email.
- **Existing buyers** (from the no-gate era): mint with `workers/licenses/scripts/mint-key.mjs`
  and send by hand using the §3 shape.

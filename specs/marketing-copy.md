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

- "Draw on your iPad. Share it in any call."
- "Turn the iPad into a live whiteboard using your favourite drawing or writing
  app. Connect it to your Mac with a cable or over Wi-Fi and share it in any call."
- "Ready the moment you plug in, or without the cable." "Your drawing never leaves
  your desk." "How you get it." "Questions, answered." "Make every call more visual."
- "Then £2.99 once, no subscription, macOS 14 or later"

> **Constraint:** the 7-day trial is entirely client-side, with no account or
> email capture (that's the privacy promise — the app never sends your data). So
> there is **no way to email trial users**. Email begins at the receipt, after
> purchase.

---

## 1. Marketing site — `docs/index.html` (canonical; this is the live copy)

Reproduced here as the reference. Edit the HTML for any change; keep this in step.

- **Title:** SharePad: Share your iPad on any call, in an instant
- **Hero:** Draw on your iPad. Share it in any call.
  - Turn the iPad into a live whiteboard using your favourite drawing or writing
    app. Connect it to your Mac with a cable or over Wi-Fi and share it in any call.
  - CTA pair: **Try free for 7 days** and **Buy for £2.99**.
  - Free for 7 days, then £2.99 once, no subscription, macOS 14 or later
- **See it in action.** On the left, the SharePad window. On the right, that same
  window shared into Google Meet at full size.
- **Ready the moment you plug in, or without the cable.** SharePad lives in your
  menu bar and finds your iPad as soon as it connects to your Mac, by cable or over
  Wi-Fi. Two cards side by side:
  - **With a cable:** plug the iPad into your Mac; the window appears by itself;
    share it in your call. Any drawing app works.
  - **Over Wi-Fi:** get SharePad for iPad, free; scan the code on your Mac, once;
    open it and draw in the SharePad canvas. Apple's App Store badge sits under the
    steps.
- **Your drawing never leaves your desk.** No account, no sign-in, no tracking.
  SharePad goes online to check for updates, and sends crash reports only if you
  switch them on. Over Wi-Fi, your drawing goes straight from your iPad to your Mac
  on your local network, encrypted, and never through a server.
- **How you get it.** SharePad for Mac isn't on the Mac App Store, so you download
  it straight from here. SharePad for iPad is free on the App Store.
  - £2.99, paid once. No subscription, no account, and automatic updates for life.
    The iPad app is free. One licence covers both.
  - Every build is signed and notarised by Apple, so it opens with a normal double-click.
  - It runs outside Apple's sandbox, because that's the only way macOS will treat a
    plugged-in iPad as a camera, and that's why the Mac app can't be on the App Store.
  - The code is open, so you can read what it does.
- **Questions, answered.** The full FAQ lives in the HTML, which is canonical. It
  covers cost and updates, the trial, sharing in Zoom, Meet and Teams, how it shows
  the iPad, drawing apps (any app over the cable, the SharePad canvas over Wi-Fi),
  requirements and why not the App Store, cable or Wi-Fi, the black-window fixes,
  audio, notifications, privacy and support.
- **Make every call more visual.** Connect your iPad, pick the window, and draw.
- **Footer:** Guide, Privacy, Terms & refunds, GitHub

The iPad app and its App Store listing follow the wording rules in
`specs/wireless-product.md` §9: they never mention price, "free", trial or licence.
The website may say the iPad app is free.

### Trial gate copy — live since 2026-06-14
The 7-day trial + licence gate shipped, and the site now carries this copy (added,
not rewritten, in the same voice):
- Hero CTA pair: **Download — free for 7 days** and **Buy a licence — £2.99**.
- One honest line near the pricing: "Try everything free for a week, no card and no
  account. After that, £2.99 keeps it yours for good."
- One FAQ entry, in the site's voice: *"What happens after the trial?"* — "The app
  keeps working; sharing just pauses now and then until you add your licence."

---

## 2. Stripe

- **Product name:** SharePad
- **Statement descriptor:** `SHAREPAD` (recognisable on a bank statement — otherwise
  it shows "Yardley Software").
- **Settings:** enable customer receipt emails; set a recognisable public business
  name and a support email.

### Product description (checkout, live)

Still says "over USB". On launch day change it in the Stripe dashboard to "Connect
it to your Mac with a cable or over Wi-Fi, and a clean window opens automatically."

Draw on your iPad. Share it in any call. SharePad turns your iPad into a live
whiteboard you can share in any call. Connect to your Mac over USB, and a clean
window opens automatically. Select from the "Share window" list in Zoom, Meet or
Teams and your favourite drawing app is ready to share. No mid-call faff. A
one-time payment with automatic updates for life, and no subscription.

### Thank-you page (`docs/thanks-*.html`)
- **Heading:** Thanks, you're all set.
- **Body:** Your licence is on its way to your email. To switch it on: open
  SharePad from the menu bar, choose "Enter Licence…", and paste the email you
  used here along with your key. It takes effect straight away and works offline.
  Lost your key later? You can get it again anytime, with no account needed and
  no need to buy again.
- **Setup steps:** open the DMG; enter your licence ("Enter Licence…"); plug in
  your iPad over USB and tap Trust, or get the free SharePad app for iPad and choose
  "Pair an iPad…" from the menu bar; pick the SharePad window in your call.
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
    Licence…' and paste both. It takes effect straight away and works offline, as
    SharePad never checks in with a server." + "Lost your key later? Get it again
    anytime at {recover_url} with the email above, with no account and no sign-in."
  - Footer: open source (GPLv3), updates for life, "reply to this email" for help.

---

## 4. Wiring notes

- **The purchase email** is sent by the `sharepad-purchase-email` webhook worker,
  exactly-once per paid checkout. It needs `STRIPE_WEBHOOK_SECRET`, `RESEND_API_KEY`,
  and `ED25519_PRIVATE_KEY` (same value as the licences worker). Deploy it *with* the
  gated app release — until then, a no-gate buyer would get a key they can't yet use.
- **`sharepad-licenses`** worker: `/recover` (self-service re-derivation, which
  **emails** the key to the buyer's address — the page above promises exactly that,
  "we'll send your key straight back" — see `specs/recover-email-delivery.md`) and
  an optional `/key` page that renders the key inline.
- **Existing buyers** (from the no-gate era): mint with `workers/licenses/scripts/mint-key.mjs`
  and send by hand using the §3 shape.

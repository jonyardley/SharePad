# SharePad for iPad: App Store submission

> Prepared 2026-10-04 for the first submission (W5, `specs/wireless-product.md`
> §10). Everything to paste into App Store Connect, the demo video shot list, and
> the order to do it in. Decisions behind it, all Jon, 2026-10-04: keep the
> private palette lookup and ship (#169, 1a); make the icon full bleed (2a);
> give review a demo video plus a working Mac build and a licence key (3a).

## 1. Before you start

- **A Mac build that has wireless.** Review pairs the iPad app with the Mac app,
  and the latest public DMG (1.2.0) has no wireless. Decided (Jon, 2026-10-04,
  4a): a notarised 1.3.0 dry-run build from the Release workflow sits on the
  `review-1.3.0` GitHub pre-release, which is not "latest" and not in the
  appcast, so existing users see nothing. Link: `https://github.com/jonyardley/SharePad/releases/download/review-1.3.0/SharePad.dmg`
- **A licence key for review.** Mint one for an address you own (for example
  `appreview@sharepad.co`), from `workers/licenses`:
  `ED25519_PRIVATE_KEY=<from your password manager> node scripts/mint-key.mjs appreview@sharepad.co`.
  The repo is public: the key goes into App Store Connect only, never here.
- **A TestFlight build with the full-bleed icon:** `just pad-upload`, or the
  **TestFlight (iPad)** workflow. Check the icon on your iPad's home screen: no
  second rounded edge inside the corners.
- **The demo video** (§5) and **screenshots** (§6).

## 2. App Store Connect, in order

App: `com.jonyardley.sharepad.ipad`, version 1.0.0.

1. **App Information.** Name and subtitle from §3. Category **Productivity**,
   secondary **Graphics & Design**. Content rights: no third-party content.
2. **Pricing and Availability.** Free. All territories.
3. **App Privacy.** Privacy policy URL `https://sharepad.co/privacy.html`.
   Data collection: **No, we do not collect data from this app.** This matches
   the privacy page and the bundle's `PrivacyInfo.xcprivacy`.
4. **Age rating.** Answer **None** or **No** to every question (no web access,
   no user-generated content shared with others, no messaging). Expect 4+.
5. **Version 1.0.0.** Promotional text, description and keywords from §3.
   Support URL `https://sharepad.co/#support`, marketing URL
   `https://sharepad.co`. Copyright `2026 Jon Yardley`.
6. **Screenshots** (§6) in the 13-inch iPad slot.
7. **Build.** Pick the TestFlight build from §1. No export compliance question:
   `ITSAppUsesNonExemptEncryption` is false (the link uses the OS's TLS).
8. **App Review Information.** Sign-in required: **No**. Contact: your name,
   phone and email. Notes from §4, with `<EMAIL>` and `<KEY>` filled in. Attach the demo video file in **Attachment**.
9. **Version release.** **Manually release this version**, so launch day
   (merge #171, tag the Mac release) is your call after approval.
10. **Add for Review**, then **Submit**.

## 3. Listing copy

Wording rules (guidelines 3.1.1 and 3.1.3(f), `specs/wireless-product.md` §9):
outside the US storefront the listing may not steer people to buy elsewhere, so
it names the Mac app plainly and never says buy, free, trial, price or licence.
Other companies' app names stay out of the keywords (guideline 2.3.7).

**Name** (30 max): `SharePad`
If the name is taken: `SharePad: Draw on Your Mac`

**Subtitle** (30 max): `Draw on your Mac over Wi-Fi`

**Promotional text** (170 max):
```
Draw on your iPad and show it in any video call, full size and live. Pair with your Mac once, then just open the app and draw.
```

**Keywords** (100 bytes max, comma separated, no spaces after commas):
```
whiteboard,drawing,sketch,pencil,screen share,video call,teaching,tutor,diagram,canvas,wireless
```

**Description** (4000 max):
```
Requires SharePad for Mac.

Draw on your iPad and show it in your video call at full size, without a cable. SharePad turns your iPad into a live whiteboard for your Mac: what you draw appears in a clean window on your Mac, ready to pick in any call's "Share window" list.

Pair once
On your Mac, click the SharePad icon in the menu bar and choose Pair an iPad. Scan the code with your iPad. From then on, open SharePad on your iPad and your drawing appears on your Mac whenever both are on the same Wi-Fi.

Only your drawing
The Mac sees the canvas and nothing else. The tool palette, menus and settings stay on your iPad, so your call sees a clean page.

Made for drawing live
- Apple Pencil and finger drawing with the familiar iPad tools
- Plain, grid or dot paper, in light or dark
- Save or share your drawing as an image or a PDF

Private by design
Your drawing goes from your iPad to your paired Mac over your own network, encrypted, and nowhere else. There's no account and no server in between, and the app collects no data.

Good to know
- Each time you open SharePad, your iPad asks to record the screen. Tap Allow. This is how the drawing reaches your Mac.
- Your iPad and Mac need to be on the same Wi-Fi network.
```

## 4. Review notes

Paste into **App Review Information, Notes** (4000 max). Fill the two blanks.

```
SharePad for iPad is a companion to SharePad for Mac, a menu-bar app that shows an iPad drawing in a window on the Mac so it can be shared in a video call (Zoom, Google Meet and so on). The iPad app streams its own drawing canvas to a paired Mac over the local network. Without a paired Mac, the app is a drawing canvas that shows "Not paired".

A demo video of the full flow is attached.

TO TRY IT
1. Download the Mac app: https://github.com/jonyardley/SharePad/releases/download/review-1.3.0/SharePad.dmg . It runs on macOS 14 or later and starts a 7-day trial on first launch. If the trial has ended on your Mac, click the SharePad icon in the menu bar and enter this licence: email <EMAIL>, key <KEY>
2. Put the Mac and iPad on the same Wi-Fi network. Networks that block devices from seeing each other (some guest and corporate Wi-Fi) will stop pairing.
3. On the Mac, click the SharePad icon in the menu bar, then Pair an iPad. A window shows a QR code and a typed code.
4. On the iPad, open SharePad and tap Pair. Allow local network access and the camera, then scan the code, or tap Type the code instead.
5. Draw on the iPad. The drawing appears in the SharePad window on the Mac. Open any video call app on the Mac and share that window to see what the other people in the call see.

PERMISSIONS
- Screen recording: each time the app opens, iPadOS asks whether SharePad may record the screen. This is ReplayKit in-app capture, which is how the canvas is encoded and sent to the Mac. Only the canvas area leaves the device; the tool palette, menus and sheets are cropped out or held back. Recording stops when the app goes to the background.
- Local network: to find the paired Mac over Bonjour.
- Camera: only to scan the pairing code. Typing the code works without it.
- Photos: only when you save a drawing to Photos.

DATA
The app collects no data. There is no account, no analytics and no server: the drawing goes directly from the iPad to the paired Mac over the local network, encrypted with TLS using a key agreed during pairing. Pairing only works with a Mac that showed the code.

The iPad app is free and has no purchases. The Mac app is sold on the developer's website.
```

## 5. Demo video shot list

About 90 seconds, landscape, no voice-over needed. Record the Mac with
Cmd-Shift-5 and the iPad with Control Centre's screen recording (or film both
with a phone, which shows the two devices together and is fine for review).
Trim, then attach the file (MP4 or MOV) in App Review Information.

| # | Seconds | Shot | Must be visible |
|---|---|---|---|
| 1 | 0 to 8 | Mac desktop, SharePad icon in the menu bar; click it | The popover with **Pair an iPad…** |
| 2 | 8 to 18 | Click **Pair an iPad…** | The pairing window: QR code and typed code |
| 3 | 18 to 35 | iPad: open SharePad from the home screen | The screen recording prompt, and tapping **Allow**; the **Not paired** pill |
| 4 | 35 to 50 | iPad: tap **Pair**, allow camera and local network, scan the QR | The scan landing, then **Paired with** your Mac's name |
| 5 | 50 to 65 | Draw a simple diagram with the Pencil | The same strokes appearing in the Mac's SharePad window, palette absent on the Mac |
| 6 | 65 to 85 | Mac: start a Zoom or Meet call, Share, pick the SharePad window | The window in the call's share picker, then the shared drawing |
| 7 | 85 to 90 | iPad: press Home, then reopen | The record prompt again on reopen (it asks every time) |

The QR in shot 2 is a live pairing code, but it is spent once your iPad uses it
and expires after 5 minutes anyway, so the video gives nothing away.

## 6. Screenshots

The 13-inch iPad slot is required: **2064 × 2752** portrait or **2752 × 2064**
landscape (12.9-inch sizes, 2048 × 2732, are also accepted). One minimum, up to
ten. Take them on the iPad Pro 13-inch simulator (`just pad-build`, then run it
in Simulator, Cmd-S) or on a 13-inch iPad.

1. The canvas with a clear diagram, landscape, the pill showing connected.
2. The pairing sheet with the steps and the scanner (Scan Code tapped).
3. The paper menu with grid paper chosen.
4. The save menu (Image and PDF).

Screenshots show the iPad app only. A photo of the Mac in a call belongs on the
website, not the store page.

## 7. After approval (launch day)

1. Release the iPad version in App Store Connect.
2. Fill the App Store link in `site/site.config.json` and merge #171.
3. Tag the Mac release (`specs/release-runbook.md` Step 5) so 1.3.0 reaches
   existing users with its what's-new window.
4. Delete the `review-1.3.0` pre-release and its tag once 1.3.0 is out.
5. Run the W5 verify-by checks (`specs/wireless-product.md` §10) that need the
   live listing: the pairing QR scanned with the Camera app on an iPad without
   the app reaches the App Store.

If review rejects over the private palette lookup (#169), the fallback is our
own tool bar in place of Apple's palette, about 2 to 3 days.

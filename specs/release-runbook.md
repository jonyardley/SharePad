# First Release Runbook — SharePad 1.0

> The how-to for cutting the first signed, notarized, auto-updating build. Sibling:
> `specs/distribution.md` (the *design* of the pipeline) and `specs/licensing.md`
> (selling it). This page is the **checklist you follow when you're ready to ship.**

**Ground rule:** never commit or paste a private key, certificate, certificate
password, or `.p8`/`.p12` file. Those go straight into GitHub secrets. The Sparkle
**public** key is already committed (`project.yml`, `SUPublicEDKey`); it's safe.

Budget ~1–2 hours the first time; most of it is on Apple's website.

## Prerequisites
- **Apple Developer Program** membership ($99/year, developer.apple.com). Required —
  without it you can't sign or notarize, and the app shows "unidentified developer".
- The Sparkle PR merged to `main` (the pipeline lives there).

## Step 1 — Developer ID Application certificate
Easiest via **Xcode**: Settings → Accounts → add Apple ID → **Manage Certificates…**
→ **＋** → **Developer ID Application** (not "Apple Development"). Then in **Keychain
Access**, find "Developer ID Application: …", right-click → **Export** → `DeveloperID.p12`
with a password (kept as the `CERT_PASSWORD` secret).

Get the identity string for the `SIGN_IDENTITY` secret:
```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
# e.g. "Developer ID Application: Jon Yardley (AB12CD34EF)"
```

## Step 2 — App Store Connect API key (for notarization)
appstoreconnect.apple.com → **Users and Access** → **Integrations → App Store Connect
API** → **＋** (role: Developer). Note the **Key ID** and **Issuer ID**, and download
the **`.p8`** (one-time download).

## Step 3 — Sparkle private key
The public key is already embedded. You need the **matching private key** as a secret.
If you generated the keypair already, export it; otherwise generate then export:
```bash
BIN=.build/SourcePackages/artifacts/sparkle/Sparkle/bin   # appears after a build
"$BIN/generate_keys"                        # only if you haven't already
"$BIN/generate_keys" -x sparkle_private_key # export the private key to a file
```
The exported key must match the committed `SUPublicEDKey`
(`dENS5eDuSc3QhXyD4HZ115jBNiZGK3gGbaVehtrk5yM=`). If you ever regenerate the keypair,
update `SUPublicEDKey` in `project.yml` too.

## Step 4 — Set the GitHub secrets (8)
From the repo folder:
```bash
base64 -i DeveloperID.p12   | gh secret set DEVELOPER_ID_CERT_P12_BASE64
base64 -i AuthKey_XXXXXX.p8 | gh secret set AC_API_KEY_P8_BASE64
gh secret set SPARKLE_ED_PRIVATE_KEY < sparkle_private_key

gh secret set CERT_PASSWORD     --body 'the .p12 password from Step 1'
gh secret set KEYCHAIN_PASSWORD --body 'any strong password you invent'
gh secret set SIGN_IDENTITY     --body 'Developer ID Application: Your Name (TEAMID)'
gh secret set AC_API_KEY_ID     --body 'Key ID from Step 2'
gh secret set AC_API_ISSUER_ID  --body 'Issuer ID from Step 2'
```
Then delete the local secret files:
```bash
rm DeveloperID.p12 AuthKey_*.p8 sparkle_private_key
```

## Step 5 — Cut the release
> **Gate (one-time, then whenever the appcast Worker changes):** the
> `appcast.sharepad.co` logging-proxy Worker must be **deployed and serving**
> before tagging any build that carries `SUFeedURL =
> https://appcast.sharepad.co/appcast.xml` — otherwise that build's first update
> check hits a dead host and can't auto-update. Verify:
> ```bash
> cd workers/appcast && npx wrangler deploy   # if not already live
> curl -s https://appcast.sharepad.co/appcast.xml | diff - <(curl -s https://sharepad.co/appcast.xml)  # must be identical
> ```

First, **add a `## <version>` section at the top of `CHANGELOG.md`** (in a normal
PR to `main`) — its contents are shown to users in the in-app update dialog. Then
tag. **Push tags over SSH** — the HTTPS token can't push to Actions/workflow paths.
```bash
git checkout main && git pull
git tag v1.0.0
git push git@github.com:jonyardley/SharePad.git v1.0.0
gh run watch    # follow the build
```
Success → the DMG + `appcast.xml` published to **gh-pages** (`sharepad.co/appcast.xml`).
The app's update feed is `https://appcast.sharepad.co/appcast.xml` — the logging-proxy
Worker that serves this appcast unchanged and records install/version stats
(`specs/appcast-analytics.md`) — so cutting a new tag is all it takes to ship an update.

## Step 6 — Verify on the iPad (the step that proves it works)
1. **Download the DMG in a browser** (so it carries the quarantine flag a real user
   gets) → open → **no Gatekeeper warning** → drag to Applications → launch.
2. First launch asks for **Camera only** (no microphone).
3. Plug in the iPad → **the feed appears** (proves hardened runtime didn't break CMIO —
   the headline risk, `distribution.md` §2).
4. Share in **Zoom** and a **browser meeting**; test sleep/wake and unplug/replug.
5. Auto-update: later, release `v1.0.1` and confirm the installed 1.0.0 offers it.

## Known first-run caveats
- **create-dmg** can exit non-zero on headless CI even on success (`distribution.md`
  §11.7) — check the DMG was actually produced before trusting a red step.
- The appcast is attached to the GitHub Release (no push to the protected `main`), so
  branch protection is a non-issue. If you ever need to regenerate it by hand, run
  `just sparkle-appcast` locally and upload `appcast.xml` to the release.

## After a verified build: selling it
Separate from shipping. The **storefront** is live — Stripe Managed Payments at
[buy.sharepad.co](https://buy.sharepad.co); see `specs/licensing.md` for the decision
record. No app code; a buy button → DMG download.

### Pre-release checklist for the first *gated* (trial + licence-key) release
The 7-day trial gate (`specs/licensing.md` v2) reopens the no-gate model. Do **not**
tag the first gated build until all of these are done — otherwise paying customers hit
the 5-minute session pause 7 days after updating:
- [ ] Checkout is wired to licence-key issuance: the `workers/licenses/` route is deployed
  (`wrangler deploy` + `ED25519_PRIVATE_KEY` / restricted `STRIPE_API_KEY` secrets), and
  `https://buy.sharepad.co`'s success URL redirects to `/key?session_id={CHECKOUT_SESSION_ID}`.
- [ ] `License.recoverURL` points at the deployed worker (it's a placeholder → `nil` until
  then, which correctly hides the in-app "Lost your key?" affordance).
- [ ] Keys for existing `buy.sharepad.co` buyers are minted (`workers/licenses/scripts/mint-key.mjs`)
  and sent.
- [ ] A Cloudflare rate-limit rule guards `/recover` (it's a purchase oracle + Stripe-quota drain).

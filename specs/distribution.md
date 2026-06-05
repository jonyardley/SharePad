# Distribution & Release — Spec

> Tier 3, **domain-sensitive** (touches entitlements + the capture runtime —
> CLAUDE.md says these go up a tier and must be verified on the iPad). Status:
> **proposed**, not yet implemented. Plan mode follows approval.
>
> Sibling: **`specs/licensing.md`** (GPLv3 + sell-the-build monetisation) sits *on
> top* of this. This
> spec is the foundation and the critical path — do it first.

## 1. Problem & goal

SharePad was a personal local build with ad-hoc signing (`CODE_SIGN_IDENTITY:
"-"`, no hardened runtime, no entitlements file). To sell it (per
`specs/licensing.md`) it must be a **signed, notarized, stapled** app a stranger
can download and open with **no Gatekeeper warning**, that **auto-updates**, built
**reproducibly by CI from a git tag**.

App Store is out (sandbox kills the CMIO opt-in — DESIGN.md §6). Path: **Developer
ID + notarization + direct download (DMG) + Sparkle**.

## 2. The headline risk (read first)

Enabling **Hardened Runtime** (mandatory for notarization) changes the capture
runtime. Under hardened runtime, camera access requires the
**`com.apple.security.device.camera`** entitlement *in addition to* the usage
string. **Without it, the iPad feed dies silently** — the same class of
"empty/black, no obvious cause" failure as the sandbox/CMIO trap.

Therefore: **every signed build must be re-verified on the actual iPad in a real
meeting app** (DESIGN.md §11). A green build and successful notarization prove
*nothing* about whether frames still flow. This is the one place a unit suite
cannot help.

## 3. Decisions (locked / proposed)

| Decision | Choice |
|---|---|
| Signing identity | **Developer ID Application** (not "Apple Development") |
| Runtime | **Hardened Runtime ON**, **App Sandbox OFF** |
| Entitlements | `com.apple.security.device.camera` = **true**; **no** audio entitlement (preserve the no-mic design, DESIGN.md §6.5) |
| Notarization | `notarytool submit --wait` + `stapler staple`, via App Store Connect API key |
| Package | **DMG** (create-dmg), notarized + stapled |
| Auto-update | **Sparkle 2** (EdDSA-signed appcast) — first third-party dep, flagged |
| Appcast hosting | **GitHub Release asset** (`releases/latest/download/appcast.xml`) |
| Versioning | `MARKETING_VERSION` → **1.0.0**; `CURRENT_PROJECT_VERSION` auto from CI |
| Release trigger | git tag `v*` → release CI workflow |

## 4. `project.yml` changes

- `CODE_SIGN_IDENTITY: "Developer ID Application"`, `CODE_SIGN_STYLE: Manual`.
- `ENABLE_HARDENED_RUNTIME: YES`.
- `CODE_SIGN_ENTITLEMENTS: Sources/SharePad/SharePad.entitlements`.
- `OTHER_CODE_SIGN_FLAGS: --timestamp` (secure timestamp required for notarization).
- `MARKETING_VERSION: 1.0.0`; leave `CURRENT_PROJECT_VERSION` overridable by CI.
- Info.plist (via `INFOPLIST_KEY_*` or a plist): Sparkle `SUFeedURL`,
  `SUPublicEDKey`, `SUEnableAutomaticChecks`.

New file **`Sources/SharePad/SharePad.entitlements`**:
```xml
<key>com.apple.security.device.camera</key><true/>
```
Deliberately minimal. **No** `com.apple.security.device.audio-input`. **Resolved:**
Sparkle 2 needs **no** `com.apple.security.cs.*` exception for a non-sandboxed app —
the entitlements file stays camera-only. (Confirm against the on-iPad notarized build.)

## 5. Notarization flow

1. Build **Release**, signed Developer ID + hardened runtime + entitlements +
   `--timestamp`.
2. Zip (or DMG) → `xcrun notarytool submit <archive> --wait` authenticated with an
   **App Store Connect API key** (issuer id + key id + `.p8`).
3. On success, `xcrun stapler staple SharePad.app` (and the DMG).
4. Verify: `spctl -a -vvv -t install SharePad.app` and `stapler validate`.

## 6. Packaging

`create-dmg` → a branded DMG (app + Applications symlink). Sign the app *before*
building the DMG; notarize + staple the **app**, then build the DMG, then notarize
+ staple the **DMG** too (so the downloaded artifact itself is stapled and opens
offline cleanly).

## 7. Sparkle (auto-update) — **implemented** (`feature/sparkle-autoupdate`)

> Status: integrated. Sparkle 2.9.x via SPM; `protocol SoftwareUpdating` +
> `SparkleUpdater` in `Sources/SharePad/Updater/`; a "Check for Updates…" button in
> the popover; `SUFeedURL`/`SUPublicEDKey`/`SUEnableAutomaticChecks` in the Info.plist
> (now an explicit xcodegen `info` block — custom `SU*` keys can't go through
> `INFOPLIST_KEY_*`); nested-code re-signing in the `sign` recipe; appcast generation
> in `just sparkle-appcast` + `release.yml`. The production `SUPublicEDKey` is
> embedded; **remaining launch step:** set the matching `SPARKLE_ED_PRIVATE_KEY` repo
> secret so CI can sign the appcast.

- Added via SPM in `project.yml` (flagged dependency; recorded in DESIGN.md §7).
- Generate an **EdDSA keypair** (`generate_keys`); **private key is a CI secret**,
  public key goes in Info.plist as `SUPublicEDKey`.
- Each release: `sign_update <archive>` produces the signature for the appcast
  entry; CI generates/updates `appcast.xml` and publishes it to the feed URL.
- A **Check for updates…** menu item in the popover (the UI hook noted in
  `specs/licensing.md` §7) calls `SPUStandardUpdaterController`.
- **Release notes:** the top `## <version>` section of `CHANGELOG.md` is extracted to
  `SharePad.md` and baked into the appcast via `generate_appcast --embed-release-notes`;
  Sparkle shows it in the update dialog. Edit `CHANGELOG.md` before tagging.

## 8. Release CI workflow (`.github/workflows/release.yml`)

Separate from the existing PR `ci.yml`. Trigger: push tag `v*`.

Steps: checkout → import Developer ID cert into a temporary keychain → `just gen`
→ build Release → codesign (hardened runtime + entitlements + timestamp) →
notarytool submit --wait → staple → create-dmg → notarize + staple DMG →
`sign_update` (Sparkle) → update `appcast.xml` → create GitHub Release with the
DMG attached → publish the appcast.

**Secrets required:**
`DEVELOPER_ID_CERT_P12_BASE64`, `CERT_PASSWORD`, `KEYCHAIN_PASSWORD`,
`SIGN_IDENTITY` (the full `Developer ID Application: …` string the `sign` recipe
signs with), `AC_API_KEY_ID`, `AC_API_ISSUER_ID`, `AC_API_KEY_P8_BASE64`. Plus
`SPARKLE_ED_PRIVATE_KEY` once Sparkle lands. (We sign by identity string, so no
separate `TEAM_ID` secret is needed.)

`CURRENT_PROJECT_VERSION` (build number) comes from `github.run_number`;
`MARKETING_VERSION` is derived from the tag (`v1.2.3` → `1.2.3`) so the released
version always matches the tag — the single source of truth.

## 9. Adjacent production gaps (fold in here)

These aren't "distribution" proper but belong to the same 1.0 push:
- ✅ **PR CI now runs tests** — `ci.yml` switched from `just build` to `just test`.
- ✅ **`LICENSE` is GPLv3** — open source. The notarized build is sold as a paid
  convenience, not enforced (see `specs/licensing.md`). Replaced the MIT license
  that had briefly landed on main.
- ✅ **README/DESIGN** updated for paid direct distribution (DESIGN.md §12.5
  resolved to "direct sale, Developer ID notarized").
- ✅ **Issue [#24](https://github.com/jonyardley/SharePad/issues/24)** (watchdog
  gap) — closed on main via #33 before this work landed.

## 10. Verification (the part that counts)

- **Automated:** `spctl`/`stapler validate` pass in CI; PR CI green incl. tests.
- **Manual, on the iPad, against a notarized build** (non-negotiable):
  1. Download the DMG **via a browser** (so it carries the
     `com.apple.security.quarantine` xattr a real user gets), open → **no Gatekeeper
     warning**, drag to Applications, launch.
  2. First launch prompts for **Camera only** (no mic).
  3. Plug iPad → **feed appears** (proves the camera entitlement + hardened runtime
     didn't break CMIO — §2).
  4. Shares cleanly in **Zoom** and a **browser meeting** (keep-on-top path).
  5. Sleep/wake recovers; disconnect/reconnect cycles.
  6. Sparkle: bump to a test build, confirm the app sees and installs the update.

## 11. Open questions

1. ~~**Appcast hosting**~~ — **Resolved:** a **GitHub Release asset** at the stable
   `…/releases/latest/download/appcast.xml`. The release job generates the appcast and
   attaches it alongside the DMG. (Switched from GitHub Pages because `main` is branch-
   protected — the Actions bot can't push to it — and the appcast is a build artifact,
   not source. No Pages dependency, no branch push.)
2. ~~**DMG vs zip**~~ — **Resolved (v1):** the notarized **DMG** is both the download
   and the Sparkle feed enclosure (Sparkle 2 installs from a DMG). Delta/zip deferred.
3. **dSYM handling** — keep dSYMs as release artifacts for future crash
   symbolication even though no crash reporter ships in v1?
4. **Storefront terms** — GPLv3 is the software licence (no EULA needed); decide
   whether the paid download needs a short terms-of-sale/refund note. See
   `specs/licensing.md`.
5. **Cert storage** — App Store Connect API key (`.p8`) vs app-specific password
   for `notarytool`. (Proposed: API key — cleaner for CI.)
6. ~~**Sparkle hardened-runtime entitlements**~~ — **Resolved:** none beyond camera
   (non-sandboxed app); nested Sparkle code is re-signed inside-out in `sign` (§4, §7).
7. **`create-dmg` in headless CI** — the Homebrew `create-dmg` (andreyvit) drives
   Finder/AppleScript for window styling and is known to exit non-zero on headless
   runners even when the DMG is produced. Verify on the first real release; if it
   trips `set -e`, pin a version or tolerate its known exit code (without masking
   genuine failures).

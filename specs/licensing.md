# Licensing & Monetisation — Spec

> Status: **locked (2026-06-05, revised).** Revises the immediately-prior
> "no enforcement" draft — see the decision and its history below. Sibling:
> `specs/distribution.md` (the release pipeline this builds on).

## 1. Problem & goal

Sell SharePad to fund its development while keeping the **source open**. The model:
the *code* is GPLv3 (anyone may build it free), but the **official prebuilt build
that Jon sells** carries a **14-day free trial → license-key unlock**. The trial
nudges the people who download the ready-to-run app — the overwhelming majority —
to pay. It is deliberately a **soft nudge, not DRM**: because the source is public,
a technical user can build an un-gated SharePad, and that's fine. We optimise for
the convenience-buyer, not the source-compiler.

## 2. Decision (locked)

| Decision | Choice | Rationale |
|---|---|---|
| **Source licence** | **GPLv3** | Truly open source; copyleft removes the incentive to repackage-and-undercut. As sole copyright holder, Jon may also license his own code commercially and sell builds. |
| **Monetisation** | **Sell the prebuilt build** — signed, notarized, auto-updating DMG — **with a 14-day trial then a license key** | The value is the *ready-to-run* app. The trial lets people try before buying; the key unlocks the build they downloaded. (Open-core / "sell the official build" model.) |
| **Enforcement** | **Soft** | A 14-day trial gate in the prebuilt build, then a capture gate until a key is entered. Not unbreakable — a source build can omit it — and that's acceptable; the gate targets convenience-buyers, not adversaries. |
| **Validation** | **Offline** | No server, no phone-home. A key is a signature of the licensee name, verified against an embedded public key (see §3). |
| **Price model** | **TBD** (open question) — fixed price vs pay-what-you-want | Not load-bearing for the build. |

### History

The first draft locked CocoaFob + FastSpring trial machinery. A subsequent draft
swung the other way — GPLv3 with **no** enforcement at all — on the reasoning that
open source makes enforcement pointless. This revision keeps GPLv3 but restores a
**soft trial**: "can't fully enforce" became "don't bother," which over-corrected.
Most buyers never touch the source; a trial nudge on the official build is worth
the small, honest amount of code it costs.

## 3. What we build

### 3.1 In-app licensing layer (`Sources/SharePad/Licensing/`)

A small, **pure, unit-tested** layer — one orthogonal state axis plus one gate. It
does **not** touch the one-session/one-owner capture model: the gate only
*withholds* `start`, it never mutates or stops the session.

- **`LicenseState`** — `enum { trial(daysRemaining:), trialExpired, licensed }` with
  `isEntitled` (trial or licensed). A **pure** reducer
  `Licensing.state(firstLaunch:now:name:key:validator:)` mirrors `State/AppState.swift`:
  licensed-overrides-trial; trial-day arithmetic; an absent/invalid key falls back
  to the (possibly expired) trial window. No I/O, no AVFoundation.
- **`KeyValidating`** + **`LicenseValidator`** — offline check via **CryptoKit**
  `Curve25519.Signing` (first-party, zero-dependency). A key is a base64 Ed25519
  signature of the licensee name, verified against an **embedded public key** (only
  the public key ships). Behind the `KeyValidating` protocol, so the scheme is
  swappable in one file if the storefront can't emit this format.
- **`LicenseStore`** — write-once trial start + key persistence on `Preferences`.
  The trial-start key name is deliberately non-obvious — a small bump against a
  casual `defaults delete` reset, nothing more.
- **`Purchase`** — opens the storefront checkout URL.

### 3.2 AppModel wiring

`licenseState` + `isEntitled` (published); `refreshLicense()` on `start()`;
`enterLicense(name:key:)` (validate → persist → recompute → start the device the
gate had withheld); `openPurchasePage()`. The gate is a `guard isEntitled` at the
two capture-start sites: when not entitled the iPad is still **detected**
(`currentDeviceName` set, so the popover says so) but the session is **not started**
and the window is **not shown** — surface, don't swallow.

### 3.3 UI (`PopoverView` + `LicenseEntryView`)

- `.trial` → a discreet "Trial — N days left" caption.
- `.trialExpired` → the device row is replaced with **Buy SharePad** + **Enter
  license key…** (a small sheet with inline validation error).
- `.licensed` → no banner.
- **About panel** (#29): add the GPLv3 notice — a one-line "free software, no
  warranty" statement, a **View source** link to the GitHub repo, and a **View
  licence** link. Satisfies GPLv3 §0's "Appropriate Legal Notices" for an
  interactive UI.

### 3.4 Storefront & updates

- **Storefront** — a checkout that takes payment and emails a license key.
  Candidates: **FastSpring/Paddle** (Merchant-of-Record, custom key generators) or
  **Gumroad**. The key generator must emit the §3.1 format (Ed25519 signature of
  the name) — **confirm before launch**, else swap `LicenseValidator`.
- **Updates** — **Sparkle** for the sold build (`specs/distribution.md` §7). Source
  builders update via `git pull` + rebuild.
- **GPL compliance** — the source is public on GitHub, satisfying GPLv3's "offer the
  source" obligation for the binaries distributed.

## 4. Testing

The layer is almost entirely pure logic, fully unit-testable **without hardware or
a real key**:

- **`LicenseStateTests`** — day 0 / 13 / 14 boundaries, negative clock-skew,
  licensed-overrides-trial, invalid-key fallback, entitlement.
- **`LicenseValidatorTests`** — a throwaway keypair generated in the test bundle:
  valid passes; tampered name / foreign key / garbage base64 / empty embedded key
  fail. (The production private key never enters the repo.)
- **`LicenseStoreTests`** — write-once first-launch, license round-trip via an
  ephemeral `UserDefaults` suite.
- **`AppModelTests`** (via `FakeCaptureController`) — not-entitled withholds
  `start` and the window; entering a valid key flips entitlement and starts the
  withheld device; the entitled path is unchanged.

The only **manual** check (deferred to a notarized build): one storefront test
order → emailed key → paste → unlock.

## 5. Launch blockers (config, not code)

- **Embed the production license public key** — `AppModel.licensePublicKey` is an
  empty placeholder; until set, no key validates (trial still works).
- **Set the production storefront checkout URL** — `Purchase` opens a placeholder.
- **Confirm the storefront's key generator** can emit the §3.1 format.

## 6. Open questions

1. **Storefront + price** — FastSpring/Paddle vs Gumroad; fixed price vs
   pay-what-you-want. (Must support emailing a custom-format key.)
2. **Buy affordance placement** — expired popover only, or also a quiet About link?
3. **Activation cap** — none in v1, or a storefront-side device cap?
4. **Per-file GPLv3 headers** — add to source files, or rely on top-level `LICENSE`
   + About notice? (Proposed: top-level + About is enough for a single-author app.)

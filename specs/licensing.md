# Licensing & Trial — Spec

> Tier 3 (net-new top-level capability touching the `AppModel` state). Status:
> **proposed**, not yet implemented. Plan mode follows approval of this spec.
>
> Sibling spec: **`specs/distribution.md`** owns signing, notarization, the
> hardened-runtime camera entitlement, DMG packaging, Sparkle auto-update, and the
> release CI. This spec owns *only* the buy/trial/unlock logic. The two are
> developed together for 1.0 but kept separate because the distribution work is
> domain-sensitive (entitlements + capture) and this work is not.

## 1. Problem & goal

SharePad shipped as a personal local build (DESIGN.md §1, §12.5 deferred
distribution). With a paid Apple Developer ID, the goal is to **sell it as a
notarized, direct-download Mac app** — no App Store, because the App Store
mandates the sandbox and the sandbox kills the CMIO opt-in the app depends on
(see DESIGN.md §6; confirmed via research 2026-06-05). This spec defines how the
app trials, sells, and unlocks.

Non-goals: subscriptions, in-app purchase, accounts, a license server, seat
management beyond a simple activation cap, hardened anti-piracy DRM.

## 2. Decisions (locked)

| Decision | Choice | Rationale |
|---|---|---|
| **Pricing model** | **One-time purchase** for the 1.x line; 2.0 is a paid upgrade | No server costs → subscription would breed resentment for a small utility. Recurring revenue, if ever wanted, is Route B (Setapp), not this. |
| **Trial** | **14-day** full-feature trial, then gated | Spans several real calls; short enough to drive a decision. |
| **Trial gate** | On expiry, the app **detects the iPad but won't start the feed**; popover surfaces Buy / Enter-key | The share feed *is* the value. Not starting capture also saves CPU vs. running-then-blocking. |
| **Payment provider** | **FastSpring** (Merchant of Record) | Handles global VAT/sales-tax. Documented Mac path (CleanCocoa book + sample repo). Provider is a checkout detail, swappable later. |
| **License scheme** | **CocoaFob** — offline public-key signature validation | No backend, works offline; matches the app's no-deps/offline ethos. App embeds only the *public* key. |
| **Price point** | **TBD** (open question) | Set before launch; not load-bearing for the build. |

## 3. License model

### 3.1 Format & validation
- A license is a **name + signed key string** (CocoaFob's DSA/PKCS-style code).
  FastSpring generates it at purchase from our **private** key and emails it to the
  buyer.
- The app embeds **only the public key** and verifies the signature **locally,
  offline**. No network call, ever, for validation.
- Activation cap (e.g. personal-use, generous) is enforced **at FastSpring's side**
  on key issuance, not in-app — the app does no per-machine activation call in v1.

### 3.2 Entitlement = trial-active OR licensed
`isEntitled` is the single boolean the rest of the app keys off:
- **Licensed** — a stored key validates against the public key → entitled forever.
- **Trial** — `now < firstLaunch + 14d` and no valid key → entitled, show days left.
- **Trial expired** — past the window, no valid key → **not** entitled.
- **Invalid key** — a stored key fails validation (corrupt/tampered) → treated as
  no key; fall back to trial state (which may itself be expired).

### 3.3 Threat model (explicit)
This is a small utility, not banking software. Offline validation **deters casual
sharing**; a determined user can bypass it (reset `firstLaunch`, share a key). That
is **accepted** — we do not invest in obfuscation, jailbreak-style checks, or a
phone-home. v1 stores `firstLaunch` in a slightly non-obvious location (not a
plainly-named `UserDefaults` key) as the *only* anti-reset measure, and stops
there. Revisit only if piracy ever proves material.

## 4. State model (pure, testable)

A new pure reducer mirrors `State/AppState.swift` so it's unit-tested without I/O:

```
enum LicenseState: Equatable {
    case trial(daysRemaining: Int)
    case trialExpired
    case licensed
}

enum Licensing {
    // Pure: (firstLaunch, now, storedKey, publicKey) → LicenseState.
    static func state(firstLaunch: Date, now: Date,
                      key: String?, validator: KeyValidating) -> LicenseState
}
```

`isEntitled` is derived: `.trial`/`.licensed` → true; `.trialExpired` → false.

Licensing is kept **orthogonal to `AppState`** (the capture lifecycle reducer) —
the two axes don't merge. The popover composes both: capture state for the feed,
license state for the buy/trial banner.

## 5. Module layout

Mirrors the existing `Support/` and `State/` conventions:

```
Sources/SharePad/
  Licensing/
    LicenseState.swift     # enum + pure reducer (unit-tested)
    LicenseValidator.swift # CocoaFob signature check vs embedded public key
    LicenseStore.swift     # persists firstLaunch + key (UserDefaults-backed)
    Purchase.swift         # the FastSpring checkout URL + "enter key" plumbing
```

CocoaFob is added via SPM in `project.yml`, **or vendored** (~few hundred lines) to
keep the third-party count at zero — decide in plan mode. Either way it is a
**flagged dependency decision** per CLAUDE.md; record it in DESIGN.md when landed.

## 6. `AppModel` integration

Smallest possible blast radius — one new axis of state plus one gate:

- `AppModel` gains `private(set) var licenseState: LicenseState` and a computed
  `isEntitled`. It reads `LicenseStore` on `start()` and recomputes on key entry.
- **The gate** sits at the capture-start decision points in `reconcile(...)` and
  `switchTo(...)` (`AppModel.swift`): if `!isEntitled`, set `currentDeviceName`
  (so the popover can say "iPad connected") but **do not** call `capture.start`,
  and do not present the window. The `.teardown`/device-vanished paths are
  unchanged.
- New intents: `enterLicense(_ key: String)` (validate, persist on success,
  recompute), `openPurchasePage()` (opens the FastSpring checkout URL).
- **Non-negotiables preserved:** one session/one owner untouched (we just don't
  start it); no decisions in views; errors surfaced. The `start()` skip-under-
  XCTest guard in `App.swift` is unaffected.

## 7. UI (`PopoverView`)

Dumb presentation reading `model.licenseState`, consistent with existing toggles:

- **Trial banner** — "Trial: N days left" (subtle) when `.trial`.
- **Expired state** — replaces the device row with "Your trial has ended" + a
  prominent **Buy SharePad** button (opens checkout) and an **Enter license key…**
  affordance (a small sheet: name + key field, inline validation error on failure).
- **Licensed** — no banner; optionally a quiet "Licensed" line in an About area.
- **Check for updates** — menu item wired to Sparkle (implemented in
  `specs/distribution.md`, surfaced here).

## 8. Persistence (`Preferences` / `LicenseStore`)

Extends the existing `Preferences` (`UserDefaults`) pattern:
- `firstLaunchDate: Date` — written once, on the first `start()` where it's absent.
  Stored under a non-obvious key (§3.3).
- `licenseName: String?`, `licenseKey: String?` — set on successful entry, cleared
  never (re-validated on each launch).

## 9. Testing strategy

This capability is **almost entirely pure logic** — it fits the existing test
philosophy (DESIGN.md §11) far better than the capture layer does:

- **`LicenseState` reducer** — trial-day arithmetic (boundaries: day 0, day 13,
  day 14, clock-skew/negative), expired vs active, licensed-overrides-trial,
  invalid-key-falls-back. Pure, no I/O.
- **`LicenseValidator`** — sign sample keys with a **test keypair** in the test
  bundle; assert valid keys pass and tampered/foreign keys fail. (The production
  private key never enters the repo.)
- **`AppModel` gate** — drive via the existing `FakeCaptureController`: when not
  entitled, `reconcile([device])` must **not** call `capture.start` and must not
  show the window; when entitled, behaviour is unchanged (existing tests still
  pass); `enterLicense` with a valid key flips entitlement and a subsequent
  reconcile starts capture.
- **`LicenseStore`** — round-trips via an ephemeral `UserDefaults` suite, like the
  existing `Preferences` tests.

No hardware needed for any of the above. The only manual check is the end-to-end
purchase → email key → paste → unlock flow against a FastSpring **test** order,
run once on a notarized build.

## 10. Open questions

1. **Price point** — set before launch. (Doesn't block the build.)
2. **Upgrade policy** — does a 1.x key keep working forever on 1.x, and 2.0 is a
   fresh purchase? (Proposed: yes; encode a version ceiling in the key or just
   gate by app major version.)
3. **Activation cap** — what number, and do we ever need in-app activation
   tracking, or is FastSpring-side issuance enough for v1? (Proposed: enough.)
4. **CocoaFob: SPM vs vendored** — decide in plan mode (zero-deps vs convenience).
5. **Refunds / key revocation** — offline validation can't revoke a key. Accepted
   for v1 (refunds handled by FastSpring; revocation not supported). Confirm.
6. **Trial-reset hardening** — is the single non-obvious-key measure (§3.3) enough,
   or do we want a Keychain-backed first-launch marker? (Proposed: enough for v1.)

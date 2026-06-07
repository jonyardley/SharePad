# Licensing & Monetisation — Spec

> Status: **accepted**. Supersedes the earlier trial/licence-key draft — see the
> decision below. Sibling: `specs/distribution.md` (the release pipeline this
> builds on).

## 1. Problem & goal

Sell SharePad to fund its development, while keeping it **open source**. Those two
goals only reconcile one way: you can't *enforce* payment on open-source software
(anyone can build it, or compile out any gate), so monetisation is **selling
convenience and goodwill**, not licence enforcement.

## 2. Decision (locked, 2026-06-05)

| Decision | Choice | Rationale |
|---|---|---|
| **Source licence** | **GPLv3** | Truly open source; copyleft means anyone redistributing a modified build must also open *their* source, which removes the incentive to repackage-and-undercut. As sole copyright holder, Jon can still sell builds freely. |
| **Monetisation** | **Sell the prebuilt build** — signed, notarized, auto-updating DMG | The thing of value is the *ready-to-run* app, not the bits. Most users will happily pay rather than build from source. (Maccy / OBS / NetNewsWire model.) |
| **Enforcement** | **None** | No trial, no licence keys, no in-app gate. Open source makes enforcement pointless *and* against the spirit. The bought build and the self-built build are byte-for-byte the same. |
| **Price model** | **Fixed price, ≥£4.99** (resolved 2026-06-07) | Not load-bearing for the build. At sub-£5 the platform's fixed per-transaction fee is a punishing share of the sale, so PWYW / £1.99 is gutted by fees; a fixed price near/above £4.99 dilutes that drag. See §6.1. |

**This deletes the previous plan's trial/CocoaFob/FastSpring-licence machinery.**
There is **no `Licensing/` module, no `AppModel` gate, no licence-key validation.**
The app ships identical whether built or bought — a large simplification.

## 3. What we actually build

Almost nothing in the app itself. The work is storefront + obligations:

- **Storefront** — a checkout that takes payment and delivers the notarized DMG.
  Since there are no licence keys to issue, this is just a buy button → DMG
  download. **Decided 2026-06-07: Stripe Managed Payments** — Stripe's
  merchant-of-record product (handles global VAT/tax, UK-eligible, strongest
  payout reliability, lowest fixed per-transaction fee at this price). Chosen over
  **Gumroad** (rejected — documented payout-freeze/suspension pattern) and
  **Paddle** (kept as the fallback if a Stripe MP eligibility review fails). DMG
  delivery via the Stripe thank-you page / receipt or a SendOwl-style add-on —
  still no key, still byte-for-byte identical to a source build. (Open question #1
  below: now resolved.)
- **Updates** — **Sparkle** for the sold build (covered in `specs/distribution.md`
  §7). Source builders update via `git pull` + rebuild; that's fine.
- **GPL compliance** — the source is public on GitHub, which satisfies GPLv3's
  "offer the source" obligation for the binaries we distribute. Nothing extra to
  host.

## 4. In-app changes (minimal)

- **About panel** (already exists, #29): add the GPLv3 notice — a one-line "free
  software, no warranty" statement, a **View source** link to the GitHub repo, and
  a **View licence** link. This also satisfies GPLv3 §0's "Appropriate Legal
  Notices" for an interactive UI, so it's worth doing properly.
- A discreet **"Buy / support"** affordance (popover or About) linking to the
  storefront — optional, low-key; the app is fully functional without it.
- **No** trial banner, **no** licence-entry sheet, **no** entitlement state.

## 5. Testing

There is essentially no new pure logic to unit-test (the whole point). The About
panel's links are static. The only verification is manual: the About panel shows
the correct licence/source links, and the storefront delivers a DMG that opens
cleanly (covered by `specs/distribution.md` §10).

## 6. Open questions

1. **Storefront + price** — **RESOLVED 2026-06-07** (was: Gumroad vs
   Paddle/FastSpring, pay-what-you-want). Storefront = **Stripe Managed Payments**
   (MoR, UK-eligible; Gumroad rejected for payout-freeze risk; Paddle is the
   fallback). Price = **fixed, ≥£4.99** — *not* pay-what-you-want: at sub-£5 the
   platform's fixed per-transaction fee is ~13–25% of the sale, so PWYW / £1.99 is
   gutted by fees, while a fixed price near/above £4.99 dilutes that drag. Caveat:
   Stripe MP requires a digital-goods tax code (a downloadable GPL binary qualifies;
   selling GPL binaries is legal and, with no key, stays the no-enforcement model).
   The full platform-evaluation trail is in the session memory
   (`sharepad-sales-platform-decision`).
2. **Buy affordance placement** — About panel only, or also a quiet popover link?
3. **Donations** — also offer GitHub Sponsors, or keep a single buy path?
4. **Per-file licence headers** — add GPLv3 headers to source files, or rely on the
   top-level `LICENSE` + About notice? (Proposed: top-level + About is enough for a
   single-author app; revisit if contributors arrive.)

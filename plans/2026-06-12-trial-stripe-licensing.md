# Trial + Stripe Licensing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `specs/licensing.md` v2 — a 7-day client-side trial with a 20-minute session limit after expiry, offline Ed25519 licence keys, a two-route Cloudflare Worker for key issuance via Stripe Managed Payments, and removal of all Gumroad references.

**Architecture:** Pure, unit-tested `Licensing/` layer (`EntitlementClock`, `LicenseValidator`) feeding entitlement state into `AppModel` (which owns the session-limit timer); `ShareWindowController` renders a trial overlay; checkout is a Stripe Payment Link whose success URL hits a Cloudflare Worker that derives keys by signing the buyer's email. No webhook, no database.

**Tech Stack:** Swift 6 / CryptoKit (Curve25519.Signing), XCTest, Cloudflare Workers (WebCrypto Ed25519, plain JS), `node --test`, Stripe Payment Links + Checkout Sessions API.

**Conventions that bind every task:** no force-unwrap/`try!`/`as!`; comments only per CLAUDE.md's three buckets; `just fmt` before every commit; new Swift files are picked up automatically by xcodegen (directory-based sources) but run `just gen` once after creating new files.

---

## Task 0: Stripe pre-flight (BLOCKING — requires Jon's Stripe dashboard)

The spec (§4) makes this a blocking check. Nothing in Tasks 10–12 can be verified without it; Tasks 1–9 don't depend on it and may proceed in parallel.

**Files:** none (dashboard work).

- [ ] **Step 1: Verify Stripe Managed Payments availability**

In the Stripe dashboard: Settings → check for "Managed Payments" (or visit https://stripe.com/managed-payments → "Get started" with the existing account). Confirm it can be enabled for the account.
Expected: SMP can be enabled. **If not available:** STOP, per spec §8.3 the fallback is Lemon Squeezy — return to design, do not improvise.

- [ ] **Step 2: Create the product + test-mode Payment Link**

In test mode: Products → Add product → "SharePad licence" (one-time price; amount = whatever Jon picks, spec open question §8.1). Create a **Payment Link** for it. Under the link's confirmation settings choose "Don't show confirmation page" and set the redirect URL to:
`https://sharepad-licenses.<account>.workers.dev/key?session_id={CHECKOUT_SESSION_ID}`
(The exact worker hostname is printed by `wrangler deploy` in Task 12; create the link now with a guess and correct it in Task 12 — the placeholder `{CHECKOUT_SESSION_ID}` must be kept verbatim.)
Expected: a test-mode URL like `https://buy.stripe.com/test_XXXX`.

- [ ] **Step 3: Create a restricted Stripe API key**

Developers → API keys → Create restricted key, test mode: **Checkout Sessions: Read** only. Name it `sharepad-license-worker`. Record it for Task 12 (`wrangler secret put STRIPE_API_KEY`).

---

## Task 1: Production keypair + `License.swift` constants

**Files:**
- Create: `worker/scripts/generate-keys.mjs`
- Create: `Sources/SharePad/Licensing/License.swift`

- [ ] **Step 1: Write the keygen script**

```js
// worker/scripts/generate-keys.mjs
// One-off: prints the Ed25519 keypair for SharePad licensing.
// The PRIVATE key is a secret — store it in a password manager and
// `wrangler secret put ED25519_PRIVATE_KEY`. Never commit it.
const { publicKey, privateKey } = await crypto.subtle.generateKey(
  { name: 'Ed25519' }, true, ['sign', 'verify'],
);
const raw = Buffer.from(await crypto.subtle.exportKey('raw', publicKey));
const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', privateKey));
console.log('PUBLIC  (embed in License.swift):', raw.toString('base64'));
console.log('PRIVATE (worker secret, DO NOT COMMIT):', pkcs8.toString('base64'));
```

- [ ] **Step 2: Run it**

Run: `node worker/scripts/generate-keys.mjs` (Node ≥ 20)
Expected: two base64 lines. Save the PRIVATE line in Jon's password manager now. Only the PUBLIC value is used in the next step.

- [ ] **Step 3: Create `License.swift` with the real public key**

```swift
import Foundation

enum License {
    /// Ed25519 public key matching the worker's ED25519_PRIVATE_KEY secret.
    static let publicKeyBase64 = "<PUBLIC value from Step 2>"

    /// Stripe Payment Link (test-mode URL from Task 0 until Task 12 goes live).
    static let buyURLString = "<test-mode Payment Link URL from Task 0 Step 2>"

    static let recoverURLString = "https://sharepad-licenses.<account>.workers.dev/recover"

    static var buyURL: URL? { URL(string: buyURLString) }
    static var recoverURL: URL? { URL(string: recoverURLString) }
}
```

If Task 0 hasn't produced a Payment Link yet, use `https://example.invalid/buy` so the file compiles, and add `// FIXME(#<issue>): replace with live Payment Link before release` tied to a tracked issue.

- [ ] **Step 4: Commit**

```bash
just gen && just fmt
git add worker/scripts/generate-keys.mjs Sources/SharePad/Licensing/License.swift
git commit -m "Add licensing keypair generation and embedded constants"
```

---

## Task 2: `Entitlement` + `EntitlementClock` (pure, TDD)

**Files:**
- Create: `Sources/SharePad/Licensing/EntitlementClock.swift`
- Test: `Tests/SharePadTests/EntitlementClockTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@testable import SharePad
import XCTest

final class EntitlementClockTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    func testLicensedOverridesEverything() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start + 100 * day, isLicensed: true
        )
        XCTAssertEqual(result, .licensed)
    }

    func testFreshInstallHasSevenDays() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start, isLicensed: false
        )
        XCTAssertEqual(result, .trial(daysLeft: 7))
    }

    func testMidTrialCountsDown() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start + 2.5 * day, isLicensed: false
        )
        XCTAssertEqual(result, .trial(daysLeft: 5))
    }

    func testLastSecondStillTrial() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start + 7 * day - 1, isLicensed: false
        )
        XCTAssertEqual(result, .trial(daysLeft: 1))
    }

    func testExactlySevenDaysIsExpired() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start + 7 * day, isLicensed: false
        )
        XCTAssertEqual(result, .trialExpired)
    }

    func testClockRolledBackIsExpiredNotRestarted() {
        let result = EntitlementClock.entitlement(
            firstLaunch: start, now: start - 1, isLicensed: false
        )
        XCTAssertEqual(result, .trialExpired)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: FAIL — `EntitlementClock` / `Entitlement` not found.

- [ ] **Step 3: Implement**

```swift
import Foundation

enum Entitlement: Equatable {
    case trial(daysLeft: Int)
    case trialExpired
    case licensed
}

enum EntitlementClock {
    static let trialDays = 7

    static func entitlement(firstLaunch: Date, now: Date, isLicensed: Bool) -> Entitlement {
        if isLicensed { return .licensed }
        // Spec §5: a clock set backwards never restarts the trial.
        guard now >= firstLaunch else { return .trialExpired }
        let day: TimeInterval = 86_400
        let remaining = firstLaunch
            .addingTimeInterval(TimeInterval(trialDays) * day)
            .timeIntervalSince(now)
        guard remaining > 0 else { return .trialExpired }
        return .trial(daysLeft: Int((remaining / day).rounded(.up)))
    }
}
```

- [ ] **Step 4: Run tests**

Run: `just test` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
just fmt
git add Sources/SharePad/Licensing/EntitlementClock.swift Tests/SharePadTests/EntitlementClockTests.swift
git commit -m "Add pure EntitlementClock for trial state"
```

---

## Task 3: `LicenseValidator` (CryptoKit, TDD)

**Files:**
- Create: `Sources/SharePad/Licensing/LicenseValidator.swift`
- Test: `Tests/SharePadTests/LicenseValidatorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import CryptoKit
@testable import SharePad
import XCTest

final class LicenseValidatorTests: XCTestCase {
    private let privateKey = Curve25519.Signing.PrivateKey()

    private var validator: LicenseValidator {
        LicenseValidator(
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    private func key(for email: String) throws -> String {
        let message = Data(LicenseValidator.normalize(email).utf8)
        let signature = try privateKey.signature(for: message)
        return signature.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func testValidKeyMatchesEmail() throws {
        XCTAssertTrue(validator.isValid(key: try key(for: "buyer@example.com"), email: "buyer@example.com"))
    }

    func testEmailIsNormalizedBeforeChecking() throws {
        XCTAssertTrue(validator.isValid(key: try key(for: "buyer@example.com"), email: "  Buyer@Example.COM\n"))
    }

    func testKeyWhitespaceIsTolerated() throws {
        XCTAssertTrue(validator.isValid(key: " \(try key(for: "buyer@example.com")) \n", email: "buyer@example.com"))
    }

    func testWrongEmailFails() throws {
        XCTAssertFalse(validator.isValid(key: try key(for: "buyer@example.com"), email: "other@example.com"))
    }

    func testTamperedKeyFails() throws {
        let tampered = try String(key(for: "buyer@example.com").dropLast()) + "A"
        XCTAssertFalse(validator.isValid(key: tampered, email: "buyer@example.com"))
    }

    func testGarbageKeyFails() {
        XCTAssertFalse(validator.isValid(key: "not-a-key!!", email: "buyer@example.com"))
    }

    func testBadPublicKeyRejectsEverythingAndIsNotConfigured() throws {
        let broken = LicenseValidator(publicKeyBase64: "garbage")
        XCTAssertFalse(broken.isConfigured)
        XCTAssertFalse(broken.isValid(key: try key(for: "a@b.c"), email: "a@b.c"))
    }

    func testProductionKeyIsConfigured() {
        XCTAssertTrue(LicenseValidator.production.isConfigured)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test` — Expected: FAIL — `LicenseValidator` not found.

- [ ] **Step 3: Implement**

```swift
import CryptoKit
import Foundation

struct LicenseValidator {
    private let publicKey: Curve25519.Signing.PublicKey?

    static let production = LicenseValidator(publicKeyBase64: License.publicKeyBase64)

    init(publicKeyBase64: String) {
        publicKey = Data(base64Encoded: publicKeyBase64)
            .flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }

    /// A malformed embedded key fails safe (nothing validates);
    /// testProductionKeyIsConfigured guards against shipping that state.
    var isConfigured: Bool { publicKey != nil }

    func isValid(key: String, email: String) -> Bool {
        guard let publicKey, let signature = Self.decodeBase64URL(key) else { return false }
        return publicKey.isValidSignature(signature, for: Data(Self.normalize(email).utf8))
    }

    static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func decodeBase64URL(_ key: String) -> Data? {
        var base64 = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `just test` — Expected: PASS (including `testProductionKeyIsConfigured`, which proves the Task 1 embedded key parses).

- [ ] **Step 5: Commit**

```bash
just fmt
git add Sources/SharePad/Licensing/LicenseValidator.swift Tests/SharePadTests/LicenseValidatorTests.swift
git commit -m "Add offline Ed25519 licence validation"
```

---

## Task 4: `Preferences` additions (TDD)

**Files:**
- Modify: `Sources/SharePad/Support/Preferences.swift`
- Test: `Tests/SharePadTests/PreferencesTests.swift`

- [ ] **Step 1: Add failing tests to `PreferencesTests.swift`**

```swift
    func testLicensingDefaultsAreNil() throws {
        let prefs = try Preferences(defaults: makeEphemeralDefaults())
        XCTAssertNil(prefs.firstLaunchDate)
        XCTAssertNil(prefs.licenseEmail)
        XCTAssertNil(prefs.licenseKey)
    }

    func testLicensingValuesRoundTrip() throws {
        let defaults = try makeEphemeralDefaults()
        let prefs = Preferences(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        prefs.firstLaunchDate = date
        prefs.licenseEmail = "buyer@example.com"
        prefs.licenseKey = "some-key"

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.firstLaunchDate, date)
        XCTAssertEqual(reloaded.licenseEmail, "buyer@example.com")
        XCTAssertEqual(reloaded.licenseKey, "some-key")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `just test` — Expected: FAIL — no such properties.

- [ ] **Step 3: Implement in `Preferences.swift`**

Add before `private enum Key`:

```swift
    var firstLaunchDate: Date? {
        get { defaults.object(forKey: Key.firstLaunchDate) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.firstLaunchDate) }
    }

    var licenseEmail: String? {
        get { defaults.string(forKey: Key.licenseEmail) }
        nonmutating set { defaults.set(newValue, forKey: Key.licenseEmail) }
    }

    var licenseKey: String? {
        get { defaults.string(forKey: Key.licenseKey) }
        nonmutating set { defaults.set(newValue, forKey: Key.licenseKey) }
    }
```

Add to `Key`:

```swift
        static let firstLaunchDate = "firstLaunchDate"
        static let licenseEmail = "licenseEmail"
        static let licenseKey = "licenseKey"
```

- [ ] **Step 4: Run tests** — `just test` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
just fmt
git add Sources/SharePad/Support/Preferences.swift Tests/SharePadTests/PreferencesTests.swift
git commit -m "Persist trial start and licence in Preferences"
```

---

## Task 5: `ShareWindowControlling.setTrialOverlay` + fake

**Files:**
- Modify: `Sources/SharePad/Windows/ShareWindowControlling.swift`
- Modify: `Tests/SharePadTests/Fakes.swift`
- Modify: `Sources/SharePad/Windows/ShareWindowController.swift` (stub only; real UI in Task 8)

- [ ] **Step 1: Extend the protocol**

```swift
import CoreGraphics

@MainActor
protocol ShareWindowControlling {
    func show(size: CGSize)
    func hide()
    func updateSize(_ size: CGSize)
    func setKeepOnTop(_ enabled: Bool)
    func setTrialOverlay(_ visible: Bool)
}
```

- [ ] **Step 2: Record it in `FakeShareWindow` (Fakes.swift)**

Add inside `FakeShareWindow`:

```swift
    private(set) var trialOverlayStates: [Bool] = []

    func setTrialOverlay(_ visible: Bool) {
        trialOverlayStates.append(visible)
    }
```

- [ ] **Step 3: Stub in `ShareWindowController`**

Add to `ShareWindowController` (implementation lands in Task 8):

```swift
    func setTrialOverlay(_ visible: Bool) {
        _ = visible
    }
```

- [ ] **Step 4: Build + test** — `just test` — Expected: PASS (compiles, no behaviour change).

- [ ] **Step 5: Commit**

```bash
just fmt
git add Sources/SharePad/Windows/ShareWindowControlling.swift Sources/SharePad/Windows/ShareWindowController.swift Tests/SharePadTests/Fakes.swift
git commit -m "Add trial-overlay hook to share window protocol"
```

---

## Task 6: `AppModel` entitlement + licence entry (TDD)

**Files:**
- Modify: `Sources/SharePad/AppModel.swift`
- Test: `Tests/SharePadTests/LicenseGateTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

```swift
import AVFoundation
import CryptoKit
@testable import SharePad
import XCTest

@MainActor
final class LicenseGateTests: XCTestCase {
    private let privateKey = Curve25519.Signing.PrivateKey()
    private let day: TimeInterval = 86_400

    private func ephemeralPreferences() throws -> Preferences {
        let name = "sharepad.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: name)))
    }

    private func validator() -> LicenseValidator {
        LicenseValidator(
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    private func signedKey(for email: String) throws -> String {
        let message = Data(LicenseValidator.normalize(email).utf8)
        return try privateKey.signature(for: message).base64EncodedString()
    }

    private func makeModel(
        preferences: Preferences,
        window: FakeShareWindow = FakeShareWindow(),
        now: @escaping () -> Date = Date.init,
        sessionLimit: TimeInterval = 1200
    ) -> AppModel {
        AppModel(
            preferences: preferences,
            capture: FakeCaptureController(),
            window: window,
            thumbnailLayer: AVSampleBufferDisplayLayer(),
            validator: validator(),
            now: now,
            sessionLimit: sessionLimit
        )
    }

    func testFirstLaunchIsRecordedOnce() throws {
        let prefs = try ephemeralPreferences()
        _ = makeModel(preferences: prefs)
        let recorded = try XCTUnwrap(prefs.firstLaunchDate)
        _ = makeModel(preferences: prefs)
        XCTAssertEqual(prefs.firstLaunchDate, recorded)
    }

    func testFreshInstallIsInTrial() throws {
        let model = makeModel(preferences: try ephemeralPreferences())
        XCTAssertEqual(model.entitlement, .trial(daysLeft: 7))
    }

    func testOldInstallIsExpired() throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let model = makeModel(preferences: prefs)
        XCTAssertEqual(model.entitlement, .trialExpired)
    }

    func testEnterValidLicensePersistsAndLicenses() throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let model = makeModel(preferences: prefs)
        XCTAssertTrue(model.enterLicense(email: " Buyer@Example.com ", key: try signedKey(for: "buyer@example.com")))
        XCTAssertEqual(model.entitlement, .licensed)
        XCTAssertEqual(prefs.licenseEmail, "buyer@example.com")
        XCTAssertNotNil(prefs.licenseKey)
    }

    func testEnterInvalidLicenseIsRejected() throws {
        let model = makeModel(preferences: try ephemeralPreferences())
        XCTAssertFalse(model.enterLicense(email: "buyer@example.com", key: "bogus"))
        XCTAssertNotEqual(model.entitlement, .licensed)
    }

    func testStoredLicenseSurvivesRelaunch() throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        prefs.licenseEmail = "buyer@example.com"
        prefs.licenseKey = try signedKey(for: "buyer@example.com")
        XCTAssertEqual(makeModel(preferences: prefs).entitlement, .licensed)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `just test` — Expected: FAIL — `AppModel` has no `validator/now/sessionLimit` parameters, no `entitlement`, no `enterLicense`.

- [ ] **Step 3: Implement in `AppModel.swift`**

Add stored properties (near the other `private let`s):

```swift
    private(set) var entitlement: Entitlement = .trial(daysLeft: EntitlementClock.trialDays)
    private let validator: LicenseValidator
    private let now: () -> Date
    private let sessionLimit: TimeInterval
```

Change the designated `init` signature and body (defaulted parameters keep the convenience init and existing tests unchanged):

```swift
    init(
        preferences: Preferences,
        capture: CaptureControlling,
        window: ShareWindowControlling,
        thumbnailLayer: AVSampleBufferDisplayLayer,
        validator: LicenseValidator = .production,
        now: @escaping () -> Date = Date.init,
        sessionLimit: TimeInterval = 20 * 60
    ) {
        self.preferences = preferences
        self.capture = capture
        self.window = window
        self.thumbnailLayer = thumbnailLayer
        self.validator = validator
        self.now = now
        self.sessionLimit = sessionLimit
        monitor = DeviceMonitor()
        autoShowOnConnect = preferences.autoShowOnConnect
        keepOnTop = preferences.keepOnTop
        launchAtLogin = LaunchAtLogin.isEnabled
        if preferences.firstLaunchDate == nil {
            preferences.firstLaunchDate = now()
        }
        refreshEntitlement()
    }
```

Add the licensing section (e.g. after `openCameraSettings()`):

```swift
    // ── Licensing ──

    @discardableResult
    func enterLicense(email: String, key: String) -> Bool {
        guard validator.isValid(key: key, email: email) else { return false }
        preferences.licenseEmail = LicenseValidator.normalize(email)
        preferences.licenseKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshEntitlement()
        return true
    }

    func openBuyPage() {
        guard let url = License.buyURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openRecoverPage() {
        guard let url = License.recoverURL else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshEntitlement() {
        entitlement = EntitlementClock.entitlement(
            firstLaunch: preferences.firstLaunchDate ?? now(),
            now: now(),
            isLicensed: isStoredLicenseValid
        )
    }

    private var isStoredLicenseValid: Bool {
        guard let email = preferences.licenseEmail,
              let key = preferences.licenseKey else { return false }
        return validator.isValid(key: key, email: email)
    }
```

In `popoverDidAppear()` add `refreshEntitlement()` as the first line (keeps the days-left count fresh while the app stays running).

- [ ] **Step 4: Run tests** — `just test` — Expected: ALL PASS (existing AppModel tests untouched by the defaulted parameters).

- [ ] **Step 5: Commit**

```bash
just fmt
git add Sources/SharePad/AppModel.swift Tests/SharePadTests/LicenseGateTests.swift
git commit -m "Wire entitlement state and licence entry into AppModel"
```

---

## Task 7: Session-limit timer + overlay state (TDD)

**Files:**
- Modify: `Sources/SharePad/AppModel.swift`
- Test: `Tests/SharePadTests/LicenseGateTests.swift`

- [ ] **Step 1: Add failing tests to `LicenseGateTests.swift`**

```swift
    func testOverlayAppearsAfterSessionLimitWhenExpired() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(preferences: prefs, window: window, sessionLimit: 0.05)
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        XCTAssertTrue(model.isWindowVisible)
        try await Task.sleep(for: .seconds(0.3))
        XCTAssertEqual(window.trialOverlayStates, [true])
        XCTAssertTrue(model.isTrialOverlayShown)
    }

    func testNoOverlayDuringTrial() async throws {
        let window = FakeShareWindow()
        let model = makeModel(preferences: try ephemeralPreferences(), window: window, sessionLimit: 0.05)
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        try await Task.sleep(for: .seconds(0.3))
        XCTAssertEqual(window.trialOverlayStates, [])
    }

    func testHidingWindowClearsOverlayAndTimer() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(preferences: prefs, window: window, sessionLimit: 0.05)
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        try await Task.sleep(for: .seconds(0.3))
        model.toggleWindow()
        XCTAssertFalse(model.isTrialOverlayShown)
        XCTAssertEqual(window.trialOverlayStates, [true, false])
    }

    func testEnteringLicenseClearsOverlay() async throws {
        let prefs = try ephemeralPreferences()
        prefs.firstLaunchDate = Date(timeIntervalSinceNow: -8 * day)
        let window = FakeShareWindow()
        let model = makeModel(preferences: prefs, window: window, sessionLimit: 0.05)
        await model.reconcile(devices: [CaptureDevice(id: "a", name: "iPad")])
        try await Task.sleep(for: .seconds(0.3))
        XCTAssertTrue(model.enterLicense(email: "buyer@example.com", key: try signedKey(for: "buyer@example.com")))
        XCTAssertFalse(model.isTrialOverlayShown)
        XCTAssertEqual(window.trialOverlayStates, [true, false])
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `just test` — Expected: FAIL — no `isTrialOverlayShown`, overlay never set.

- [ ] **Step 3: Implement in `AppModel.swift`**

Add state:

```swift
    private(set) var isTrialOverlayShown = false
    private var sessionTimer: Task<Void, Never>?
```

In `presentWindow()` append `startTrialSessionIfNeeded()`:

```swift
    private func presentWindow() {
        window.show(size: videoSize ?? Self.defaultSize)
        isWindowVisible = true
        startTrialSessionIfNeeded()
    }
```

Add alongside the licensing section:

```swift
    private func startTrialSessionIfNeeded() {
        refreshEntitlement()
        guard entitlement == .trialExpired, sessionTimer == nil else { return }
        sessionTimer = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(sessionLimit))
            guard !Task.isCancelled, isWindowVisible, entitlement == .trialExpired else { return }
            isTrialOverlayShown = true
            window.setTrialOverlay(true)
        }
    }

    private func endTrialSession() {
        sessionTimer?.cancel()
        sessionTimer = nil
        if isTrialOverlayShown {
            isTrialOverlayShown = false
            window.setTrialOverlay(false)
        }
    }
```

In `enterLicense`, after `refreshEntitlement()` add `endTrialSession()`.
In `toggleWindow()`'s hide branch, add `endTrialSession()` after `isWindowVisible = false`.
In `reconcile`'s `.teardown` case, add `endTrialSession()` after `isWindowVisible = false`.

- [ ] **Step 4: Run tests** — `just test` — Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
just fmt
git add Sources/SharePad/AppModel.swift Tests/SharePadTests/LicenseGateTests.swift
git commit -m "Add expired-trial session limit with overlay state"
```

---

## Task 8: Trial overlay UI in the share window

**Files:**
- Create: `Sources/SharePad/UI/TrialOverlayView.swift`
- Modify: `Sources/SharePad/Windows/ShareWindowController.swift` (replace the Task 5 stub)

- [ ] **Step 1: Create `TrialOverlayView.swift`**

```swift
import SwiftUI

struct TrialOverlayView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.row * 2) {
            Image(systemName: "hourglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Free trial ended")
                .font(.title2.bold())
            Text("Restart SharePad to keep sharing, or buy a licence to remove this pause.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let url = License.buyURL {
                Link("Buy SharePad", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.row * 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
```

- [ ] **Step 2: Implement `setTrialOverlay` in `ShareWindowController`**

Replace the Task 5 stub. Add a property next to the others:

```swift
    private var overlayHost: NSView?
```

```swift
    func setTrialOverlay(_ visible: Bool) {
        guard visible else {
            overlayHost?.removeFromSuperview()
            overlayHost = nil
            return
        }
        guard overlayHost == nil, let contentView = window?.contentView else { return }
        let host = NSHostingView(rootView: TrialOverlayView())
        host.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            host.topAnchor.constraint(equalTo: contentView.topAnchor),
            host.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        overlayHost = host
    }
```

- [ ] **Step 3: Build and verify manually**

Run: `just test` (compiles + suite green), then `just run` with a temporary `sessionLimit: 10` override and `firstLaunchDate` cleared/backdated:
`defaults write com.jonyardley.sharepad firstLaunchDate -date "2026-05-01T00:00:00Z"` then relaunch, connect the iPad, wait for the overlay.
Expected: overlay covers the share window with material background; Buy opens the Payment Link; hiding/reshowing the window clears it. **Revert any temporary override before commit.**

- [ ] **Step 4: Commit**

```bash
just fmt
git add Sources/SharePad/UI/TrialOverlayView.swift Sources/SharePad/Windows/ShareWindowController.swift
git commit -m "Render trial-ended overlay in the share window"
```

---

## Task 9: Popover licence row + licence sheet + About link

**Files:**
- Create: `Sources/SharePad/UI/LicenseSheet.swift`
- Modify: `Sources/SharePad/UI/PopoverView.swift`
- Modify: `Sources/SharePad/UI/AboutPanel.swift`

- [ ] **Step 1: Create `LicenseSheet.swift`**

```swift
import SwiftUI

struct LicenseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var key = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Text("Enter your licence")
                .font(.headline)
            TextField("Email used at purchase", text: $email)
            TextField("Licence key", text: $key)
            if failed {
                Text("That key doesn't match this email.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Lost your key?") { model.openRecoverPage() }
                    .buttonStyle(.link)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Activate") {
                    if model.enterLicense(email: email, key: key) {
                        dismiss()
                    } else {
                        failed = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(email.isEmpty || key.isEmpty)
            }
        }
        .padding()
        .frame(width: 340)
    }
}
```

- [ ] **Step 2: Add the licence section to `PopoverView.swift`**

Add state below the `updater` property:

```swift
    @State private var showingLicenseSheet = false
```

In `body`, insert `licenseSection` between the first `Divider()`-after-toggles and the `Button("Check for Updates…")` line (i.e. directly after that `Divider()`), and attach the sheet to the outer `VStack` (after `.frame(width: 260)`):

```swift
        .sheet(isPresented: $showingLicenseSheet) {
            LicenseSheet().environment(model)
        }
```

Add the section views:

```swift
    @ViewBuilder private var licenseSection: some View {
        switch model.entitlement {
        case .licensed:
            EmptyView()
        case let .trial(daysLeft):
            licenseRow(status: "Trial — \(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
        case .trialExpired:
            licenseRow(status: "Trial ended — sharing pauses after 20 min")
        }
    }

    private func licenseRow(status: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Buy SharePad…") { model.openBuyPage() }
                Button("Enter licence…") { showingLicenseSheet = true }
            }
            Divider()
        }
    }
```

- [ ] **Step 3: Swap the About panel link**

In `AboutPanel.swift` replace:

```swift
    private static let support = "https://yardley31.gumroad.com/l/sharepad"
```

with:

```swift
    private static let support = License.buyURLString
```

and change the link label `"Support SharePad"` to `"Buy SharePad"`.

- [ ] **Step 4: Build + manual check**

Run: `just test` then `just run`.
Expected: popover shows "Trial — 7 days left" with Buy / Enter licence; sheet validates a minted key (mint one with `worker/scripts/mint-key.mjs` after Task 10, or temporarily test with a key from the unit-test keypair by injecting that validator — simplest is to defer the positive-path manual check to Task 12's E2E). Licensed state hides the row. About panel shows "Buy SharePad".

- [ ] **Step 5: Commit**

```bash
just fmt
git add Sources/SharePad/UI/LicenseSheet.swift Sources/SharePad/UI/PopoverView.swift Sources/SharePad/UI/AboutPanel.swift
git commit -m "Add trial status, buy, and licence entry to the popover"
```

---

## Task 10: Worker pure module + tests

**Files:**
- Create: `worker/package.json`
- Create: `worker/src/license.mjs`
- Create: `worker/test/license.test.mjs`
- Create: `worker/scripts/mint-key.mjs`

- [ ] **Step 1: `worker/package.json`**

```json
{
  "name": "sharepad-licenses",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test test/"
  }
}
```

- [ ] **Step 2: Write the failing tests (`worker/test/license.test.mjs`)**

```js
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { base64url, escapeHtml, licenseKey, normalizeEmail } from '../src/license.mjs';

test('normalizeEmail trims and lowercases', () => {
  assert.equal(normalizeEmail('  Buyer@Example.COM \n'), 'buyer@example.com');
});

test('base64url has no padding or url-unsafe chars', () => {
  const encoded = base64url(new Uint8Array([251, 255, 190, 62, 63, 0]));
  assert.ok(!/[+/=]/.test(encoded));
});

test('licenseKey round-trips against WebCrypto verify', async () => {
  const { publicKey, privateKey } = await crypto.subtle.generateKey(
    { name: 'Ed25519' }, true, ['sign', 'verify'],
  );
  const key = await licenseKey(privateKey, '  Buyer@Example.com ');
  const padded = key.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(key.length / 4) * 4, '=');
  const signature = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
  const valid = await crypto.subtle.verify(
    'Ed25519', publicKey, signature, new TextEncoder().encode('buyer@example.com'),
  );
  assert.equal(valid, true);
});

test('escapeHtml neutralises markup', () => {
  assert.equal(escapeHtml('<b>&"\'</b>'), '&lt;b&gt;&amp;&quot;&#39;&lt;/b&gt;');
});
```

- [ ] **Step 3: Run to verify failure**

Run: `cd worker && npm test`
Expected: FAIL — cannot find `../src/license.mjs`.

- [ ] **Step 4: Implement `worker/src/license.mjs`**

```js
export function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

export function base64url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export async function importPrivateKey(pkcs8Base64) {
  const der = Uint8Array.from(atob(pkcs8Base64), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey('pkcs8', der, { name: 'Ed25519' }, false, ['sign']);
}

export async function licenseKey(privateKey, email) {
  const message = new TextEncoder().encode(normalizeEmail(email));
  const signature = await crypto.subtle.sign('Ed25519', privateKey, message);
  return base64url(new Uint8Array(signature));
}

export function escapeHtml(text) {
  const map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  return text.replace(/[&<>"']/g, (c) => map[c]);
}
```

- [ ] **Step 5: Run tests** — `cd worker && npm test` — Expected: PASS.

- [ ] **Step 6: Add `worker/scripts/mint-key.mjs`** (Gumroad-era buyers, spec §3)

```js
// Usage: ED25519_PRIVATE_KEY=<pkcs8 base64> node scripts/mint-key.mjs buyer@example.com
import { importPrivateKey, licenseKey } from '../src/license.mjs';

const email = process.argv[2];
const secret = process.env.ED25519_PRIVATE_KEY;
if (!email || !secret) {
  console.error('Usage: ED25519_PRIVATE_KEY=<pkcs8 base64> node scripts/mint-key.mjs <email>');
  process.exit(1);
}
console.log(await licenseKey(await importPrivateKey(secret), email));
```

- [ ] **Step 7: Commit**

```bash
git add worker/package.json worker/src/license.mjs worker/test/license.test.mjs worker/scripts/mint-key.mjs
git commit -m "Add licence key derivation module for the worker"
```

---

## Task 11: Worker routes + wrangler config

**Files:**
- Create: `worker/src/index.mjs`
- Create: `worker/wrangler.toml`

- [ ] **Step 1: `worker/wrangler.toml`**

```toml
name = "sharepad-licenses"
main = "src/index.mjs"
compatibility_date = "2026-06-01"
```

- [ ] **Step 2: `worker/src/index.mjs`**

```js
import { escapeHtml, importPrivateKey, licenseKey, normalizeEmail } from './license.mjs';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/key') return keyPage(url, env);
    if (url.pathname === '/recover') return recoverPage(url, env);
    return htmlResponse(messagePage('Not found', 'Nothing to see here.'), 404);
  },
};

async function keyPage(url, env) {
  const sessionId = url.searchParams.get('session_id');
  if (!sessionId) return htmlResponse(messagePage('Missing session', 'This link is incomplete.'), 400);
  const session = await stripeGet(`/v1/checkout/sessions/${encodeURIComponent(sessionId)}`, env);
  const email = session?.customer_details?.email;
  if (!session || session.payment_status !== 'paid' || !email) {
    return htmlResponse(messagePage(
      'Purchase not found',
      'We could not verify this checkout. If you paid, recover your key at /recover.',
    ), 404);
  }
  return htmlResponse(keyHtml(email, await deriveKey(env, email)));
}

async function recoverPage(url, env) {
  const email = url.searchParams.get('email');
  if (!email) return htmlResponse(recoverFormHtml());
  const sessions = await stripeGet(
    `/v1/checkout/sessions?customer_details[email]=${encodeURIComponent(normalizeEmail(email))}&status=complete&limit=100`,
    env,
  );
  const paid = sessions?.data?.some((s) => s.payment_status === 'paid');
  if (!paid) {
    return htmlResponse(messagePage(
      'No purchase found',
      'No SharePad purchase matches that email. Check you used the email from checkout.',
    ), 404);
  }
  return htmlResponse(keyHtml(email, await deriveKey(env, email)));
}

async function deriveKey(env, email) {
  return licenseKey(await importPrivateKey(env.ED25519_PRIVATE_KEY), email);
}

async function stripeGet(path, env) {
  const response = await fetch(`https://api.stripe.com${path}`, {
    headers: { Authorization: `Bearer ${env.STRIPE_API_KEY}` },
  });
  if (!response.ok) return null;
  return response.json();
}

function htmlResponse(body, status = 200) {
  return new Response(body, {
    status,
    headers: { 'content-type': 'text/html; charset=utf-8' },
  });
}

function keyHtml(email, key) {
  return page('Your SharePad licence', `
    <p>Thanks for buying SharePad! Your licence:</p>
    <p><strong>Email:</strong> <code>${escapeHtml(normalizeEmail(email))}</code></p>
    <p><strong>Key:</strong></p>
    <pre>${escapeHtml(key)}</pre>
    <p>In SharePad's menu-bar popover choose <em>Enter licence…</em> and paste both.</p>
    <p>Lost it later? Recover it anytime at <a href="/recover">/recover</a> — no account needed.</p>`);
}

function recoverFormHtml() {
  return page('Recover your licence', `
    <p>Enter the email you used at checkout and we'll re-derive your key.</p>
    <form method="get" action="/recover">
      <input type="email" name="email" placeholder="you@example.com" required>
      <button type="submit">Recover key</button>
    </form>`);
}

function messagePage(title, text) {
  return page(title, `<p>${escapeHtml(text)}</p>`);
}

function page(title, body) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)} — SharePad</title>
<style>
  body { font: 16px/1.6 -apple-system, system-ui, sans-serif; max-width: 560px;
         margin: 12vh auto; padding: 0 24px; color: #1d1d1f; }
  pre { background: #f5f5f7; padding: 12px 16px; border-radius: 8px;
        overflow-x: auto; user-select: all; }
  input { font: inherit; padding: 8px 12px; }
  button { font: inherit; padding: 8px 16px; }
</style></head>
<body><h1>${escapeHtml(title)}</h1>${body}</body></html>`;
}
```

- [ ] **Step 3: Sanity-run locally**

Run: `cd worker && npm test && npx wrangler dev --local` then `curl 'http://localhost:8787/recover'`
Expected: tests pass; the recover form HTML renders. (`/key` needs real Stripe secrets — covered in Task 12.)

- [ ] **Step 4: Commit**

```bash
git add worker/wrangler.toml worker/src/index.mjs
git commit -m "Add licence issuance worker (key + recover routes)"
```

---

## Task 12: Deploy worker + test-mode E2E (requires Jon's Cloudflare + Stripe access)

**Files:**
- Modify: `Sources/SharePad/Licensing/License.swift` (final URLs)

- [ ] **Step 1: Deploy and set secrets**

```bash
cd worker
npx wrangler deploy
npx wrangler secret put ED25519_PRIVATE_KEY   # paste the PRIVATE value from Task 1
npx wrangler secret put STRIPE_API_KEY        # paste the restricted TEST key from Task 0
```

Expected: deploy prints the workers.dev URL. Update the Payment Link redirect URL (Task 0 Step 2) and `License.recoverURLString` to match the real hostname.

- [ ] **Step 2: End-to-end in Stripe test mode**

1. Open the test Payment Link in a browser; pay with card `4242 4242 4242 4242`.
2. Expected: redirect to `/key?session_id=…` showing email + key.
3. `curl 'https://<worker>/recover?email=<same email>'` — Expected: same page, same key.
4. `curl 'https://<worker>/recover?email=nobody@example.com'` — Expected: 404 "No purchase found".
5. `curl 'https://<worker>/key?session_id=cs_test_garbage'` — Expected: 404 "Purchase not found".
6. In SharePad (`just run`): Enter licence… → paste email + key → Expected: activates, trial row disappears, persists across relaunch.

- [ ] **Step 3: Go live (when Jon is ready to launch)**

Repeat Task 0 Steps 2–3 in **live mode** (live Payment Link + live restricted key), `wrangler secret put STRIPE_API_KEY` with the live key, update `License.buyURLString` to the live Payment Link. Mint keys for past Gumroad buyers: export buyer emails from Gumroad, run `worker/scripts/mint-key.mjs` per email, send them.

- [ ] **Step 4: Commit**

```bash
just fmt
git add Sources/SharePad/Licensing/License.swift
git commit -m "Point licence constants at the deployed worker"
```

---

## Task 13: Remove Gumroad, update landing page + README

**Files:**
- Modify: `README.md:4,15,56`
- Modify: `docs/index.html:339,362,545`
- Modify: `specs/release-runbook.md:96`

- [ ] **Step 1: README**

- Line 4 badge: replace with `[![Buy SharePad](https://img.shields.io/badge/Buy-SharePad-635bff)](<live Payment Link>)`.
- Line 15: replace the Gumroad sentence with: `> Download the ready-to-run build from [jonyardley.github.io/SharePad](https://jonyardley.github.io/SharePad/) — free for 7 days, then £<price> one-time.`
- Line 56: replace the Gumroad link with the same gh-pages landing URL and wording: `**[download the signed, notarized, auto-updating build](https://jonyardley.github.io/SharePad/)** — free 7-day trial, one-time purchase.`

- [ ] **Step 2: docs/index.html (three CTA buttons at lines 339, 362, 545)**

Replace each `<a class="btn btn-primary" href="https://yardley31.gumroad.com/l/sharepad">…</a>` with a download-first pair (keep surrounding markup/classes intact; reuse the existing DMG link already present on the page for the download href):

```html
<a class="btn btn-primary" href="https://jonyardley.github.io/SharePad/SharePad.dmg">
  Download — free 7-day trial
</a>
<a class="btn" href="<live Payment Link>">Buy a licence</a>
```

Also update any "Buy on Gumroad"-style copy near those buttons to mention the 7-day trial and one-time purchase. Search the file for `gumroad` afterwards — zero matches allowed.

- [ ] **Step 3: specs/release-runbook.md line 96**

Replace the Gumroad storefront sentence with: the storefront is the gh-pages landing page (free trial download) plus the Stripe Payment Link; key issuance is the `worker/` Cloudflare Worker (`specs/licensing.md`).

- [ ] **Step 4: Verify zero references and commit**

Run: `grep -ri gumroad README.md docs/ specs/ Sources/`
Expected: no matches.

```bash
git add README.md docs/index.html specs/release-runbook.md
git commit -m "Replace Gumroad with trial download + Stripe checkout"
```

---

## Task 14: Docs, lint, review gate

**Files:**
- Modify: `DESIGN.md`, `CLAUDE.md`, `specs/licensing.md`

- [ ] **Step 1: Update DESIGN.md**

Add to the module map (§8): `Licensing/ — EntitlementClock + LicenseValidator (pure); trial gate state lives in AppModel; worker/ holds the Stripe key-issuance worker.` Update the monetisation note (§12.5 area) to: GPLv3 + 7-day trial soft gate + Stripe Managed Payments one-time purchase, per `specs/licensing.md` v2.

- [ ] **Step 2: Update CLAUDE.md**

In Project Structure add `worker/ # Cloudflare Worker: licence key issuance (Stripe)`. In gotchas add one line: licence keys are Ed25519 signatures of the normalized buyer email — the app never talks to a server; `LicenseValidatorTests.testProductionKeyIsConfigured` guards the embedded public key.

- [ ] **Step 3: Update specs/licensing.md status line**

Change `Status: **approved 2026-06-12**` to `Status: **implemented <date>**` and tick off resolved open questions (price, worker domain, SMP availability).

- [ ] **Step 4: Full check**

Run: `just fmt && just lint && just test && cd worker && npm test`
Expected: all clean/green.

- [ ] **Step 5: Commit + review**

```bash
git add DESIGN.md CLAUDE.md specs/licensing.md
git commit -m "Update design docs for trial + Stripe licensing"
```

Then per CLAUDE.md: run `superpowers:requesting-code-review` on the branch diff before any merge ("comment-policy violations are Blockers, not Nits"), then `superpowers:receiving-code-review` to work the findings.

---

## Task 15: Manual verification checklist (the part that counts)

No capture-pipeline code changed, but the overlay draws inside the share window — verify on the iPad per CLAUDE.md.

- [ ] Fresh install (delete the app container/defaults: `defaults delete com.jonyardley.sharepad`): popover shows "Trial — 7 days left"; everything works normally.
- [ ] Backdate trial (`defaults write com.jonyardley.sharepad firstLaunchDate -date "2026-05-01T00:00:00Z"`, relaunch): popover shows trial-ended copy; share window opens; overlay appears after the session limit (use a temporary short `sessionLimit` for the timed check, then re-verify the real 20-min constant compiles in).
- [ ] Overlay is visible **in Zoom and a browser meeting** as shared content (that's the nudge working); restart clears it; quitting mid-overlay doesn't wedge anything.
- [ ] Activate with a real test-mode-purchased key: row disappears, overlay never returns, survives relaunch.
- [ ] Capture regression pass: connect/disconnect, sleep/wake, Zoom + browser share — unchanged from the standard checklist.

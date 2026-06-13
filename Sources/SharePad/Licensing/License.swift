import Foundation

enum License {
    // Must match the worker's ED25519_PRIVATE_KEY secret (specs/licensing.md §3).
    // LicenseValidatorTests.testProductionKeyMatchesWorkerSignature pins this to a
    // real worker-minted key so a stale/mispaired value can't ship again.
    static let publicKeyBase64 = "9xFKltZpv1X31mIOJpZIzxaNyZRdp6iQhEZZlEdORUY="

    // Buy points at the live first-party storefront (storefront-agnostic, so swapping
    // processor needs no app release); recover points at the deployed licence-key worker.
    static var buyURL: URL? {
        configuredURL("https://buy.sharepad.co")
    }

    static var recoverURL: URL? {
        configuredURL("https://sharepad-licenses.jonyardley.workers.dev/recover")
    }

    private static func configuredURL(_ string: String) -> URL? {
        guard !string.contains("example.invalid") else { return nil }
        return URL(string: string)
    }
}

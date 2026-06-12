import Foundation

enum License {
    // Must match the worker's ED25519_PRIVATE_KEY secret (specs/licensing.md §3).
    static let publicKeyBase64 = "H5WnE78kLWBzUUh9akQ9tTD3/EPZwJLFl7HkxhDDrvQ="

    // FIXME(specs/licensing.md §8): placeholder URLs — replace with the live
    // Stripe Payment Link and deployed worker hostname before release.
    static var buyURL: URL? {
        URL(string: "https://example.invalid/buy")
    }

    static var recoverURL: URL? {
        URL(string: "https://example.invalid/recover")
    }
}

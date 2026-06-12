import Foundation

enum License {
    /// Ed25519 public key matching the worker's ED25519_PRIVATE_KEY secret.
    static let publicKeyBase64 = "H5WnE78kLWBzUUh9akQ9tTD3/EPZwJLFl7HkxhDDrvQ="

    // FIXME(specs/licensing.md §8): placeholder URLs — replace with the live
    // Stripe Payment Link and deployed worker hostname before release.
    static let buyURLString = "https://example.invalid/buy"
    static let recoverURLString = "https://example.invalid/recover"

    static var buyURL: URL? {
        URL(string: buyURLString)
    }

    static var recoverURL: URL? {
        URL(string: recoverURLString)
    }
}

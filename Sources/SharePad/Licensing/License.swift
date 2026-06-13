import Foundation

enum License {
    // Must match the worker's ED25519_PRIVATE_KEY secret (specs/licensing.md §3).
    static let publicKeyBase64 = "H5WnE78kLWBzUUh9akQ9tTD3/EPZwJLFl7HkxhDDrvQ="

    // Buy points at the live first-party storefront (storefront-agnostic, so swapping
    // processor needs no app release). recoverURL stays a placeholder until the
    // licence-key worker is deployed — FIXME(specs/licensing.md §8).
    static var buyURL: URL? {
        configuredURL("https://buy.sharepad.co")
    }

    static var recoverURL: URL? {
        configuredURL("https://example.invalid/recover")
    }

    private static func configuredURL(_ string: String) -> URL? {
        guard !string.contains("example.invalid") else { return nil }
        return URL(string: string)
    }
}

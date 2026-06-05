import AppKit

enum Purchase {
    /// Placeholder storefront URL — set the real one before launch (licensing.md §5).
    private static let checkoutURL = "https://sharepad.onfastspring.com/sharepad"

    static func openCheckout() {
        guard let url = URL(string: checkoutURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

import AppKit
import SwiftUI

// A MenuBarExtra (.window) popover dismisses the moment focus leaves it, so a
// `.sheet` presented from it can't hold keyboard focus — text fields can't be
// edited and the form vanishes. Licence entry therefore lives in a real, focusable
// window (same approach as the About panel), independent of the popover.
@MainActor
enum LicenseWindow {
    private static var window: NSWindow?

    static func present(model: AppModel) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Enter your SharePad licence"
        win.isReleasedWhenClosed = false
        win.contentViewController = NSHostingController(
            rootView: LicenseEntryView(model: model, onClose: { win.close() })
        )
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

struct LicenseEntryView: View {
    let model: AppModel
    let onClose: () -> Void
    @State private var email = ""
    @State private var key = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Text("A one-time licence. Works offline — no account, no sign-in.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Email used at purchase", text: $email)
            TextField("Licence key", text: $key)
            if failed {
                Text("That key doesn't match this email — check both and try again.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                if License.recoverURL != nil {
                    Button("Lost your key?") { model.openRecoverPage() }
                        .buttonStyle(.link)
                }
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Activate") {
                    if model.enterLicense(email: email, key: key) {
                        onClose()
                    } else {
                        failed = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(email.isEmpty || key.isEmpty)
            }
        }
        .onChange(of: email) { failed = false }
        .onChange(of: key) { failed = false }
        .padding()
        .frame(width: 340)
    }
}

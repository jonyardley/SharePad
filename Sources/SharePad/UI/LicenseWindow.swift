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
        let win = window ?? makeWindow()
        // A reused window must never reopen on a stale success screen or a
        // still-pending auto-close task left over from a prior visit.
        win.contentViewController = NSHostingController(
            rootView: LicenseEntryView(model: model, onClose: { win.close() })
        )
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Enter your SharePad licence"
        win.isReleasedWhenClosed = false
        return win
    }
}

struct LicenseEntryView: View {
    let model: AppModel
    let onClose: () -> Void
    @State private var email = ""
    @State private var key = ""
    @State private var failed = false
    @State private var activated = false

    var body: some View {
        Group {
            if activated {
                activatedView
            } else {
                form
            }
        }
        .padding()
        .frame(width: 340)
    }

    private var form: some View {
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
                        activated = true
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
    }

    private var activatedView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Label("Licence activated", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("Thanks for buying SharePad — the pause is gone for good.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(4))
            onClose()
        }
    }
}

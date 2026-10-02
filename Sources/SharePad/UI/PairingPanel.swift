import AppKit
import SwiftUI

// A window, not the popover: the popover closes the moment focus leaves it, and the
// user is about to pick up the iPad (specs/wireless-product.md §6, Flow).
@MainActor
enum PairingPanel {
    private static var window: NSWindow?
    private static let closer = Closer()

    static func present(model: AppModel) {
        model.pairIPad()
        let win = window ?? makeWindow()
        closer.model = model
        win.contentViewController = NSHostingController(
            rootView: PairingPanelView(model: model, onClose: { win.close() })
        )
        // The QR is a live pairing code: keep it out of any call before it is first
        // drawn, rather than waiting for WindowSharing's next sweep.
        win.sharingType = .none
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        WindowSharing.excludeAuxiliaryWindows()
    }

    private static func makeWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Pair an iPad"
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.delegate = closer
        return win
    }

    private final class Closer: NSObject, NSWindowDelegate {
        weak var model: AppModel?

        func windowWillClose(_: Notification) {
            MainActor.assumeIsolated { model?.closePairing() }
        }
    }
}

struct PairingPanelView: View {
    let model: AppModel
    let onClose: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(model.pairingPanel(now: context.date))
        }
        .padding(Theme.Spacing.section)
        .frame(width: 320)
    }

    private func content(_ panel: PairingPanelContent) -> some View {
        VStack(spacing: Theme.Spacing.section) {
            if let link = panel.link {
                QRCodeView(text: link.absoluteString)
                Text("Open SharePad on your iPad and scan this code.")
                    .multilineTextAlignment(.center)
                Text("No iPad app yet? Scanning this with the Camera app takes you to it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let code = panel.code {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let countdown = panel.countdown {
                Text(countdown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(panel.status)
                .font(panel.closesAutomatically ? .headline : .body)
            if panel.offersNewCode {
                Button("Show a new code") { model.pairIPad() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: panel.closesAutomatically) {
            guard panel.closesAutomatically else { return }
            try? await Task.sleep(for: PairingPanelContent.closeDelay)
            onClose()
        }
    }
}

private struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = QRCode.image(for: text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: Theme.Pairing.qrSide, height: Theme.Pairing.qrSide)
                .padding(Theme.Spacing.row)
                .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        } else {
            Text("Couldn’t draw the code. Type it on your iPad instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

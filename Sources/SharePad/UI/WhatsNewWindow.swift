import AppKit
import SwiftUI

@MainActor
enum WhatsNewWindow {
    static let windowID = NSUserInterfaceItemIdentifier("SharePad.whatsNewWindow")

    private static var window: WhatsNewPanel?

    static func present(model: AppModel, pairing: (any PairingOffering)?) {
        guard window == nil else { return }
        pairing?.requestNewOffer()
        let win = WhatsNewPanel()
        var handedOffToPairing = false
        win.onClose = {
            if !handedOffToPairing { pairing?.endOffer() }
            model.markWhatsNewSeen()
            window = nil
        }
        let hosting = NSHostingController(
            rootView: WhatsNewView(
                pairing: pairing,
                onDismiss: { [weak win] in win?.close() },
                onPair: { [weak win] in
                    handedOffToPairing = true
                    pairing?.openPairingWindow()
                    win?.close()
                }
            )
        )
        win.contentViewController = hosting
        win.setContentSize(hosting.view.fittingSize)
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

private final class WhatsNewPanel: NSWindow {
    var onClose: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: WhatsNewView.width, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "What's New in SharePad"
        identifier = WhatsNewWindow.windowID
        isReleasedWhenClosed = false
        // Set before it is ordered in: the sharing guard sweeps on becoming key, and a
        // window shown while another app is active may never become key.
        sharingType = .none
    }

    override func cancelOperation(_: Any?) {
        close()
    }

    override func close() {
        let onClose = onClose
        self.onClose = nil
        onClose?()
        super.close()
    }
}

struct WhatsNewView: View {
    let pairing: (any PairingOffering)?
    let onDismiss: () -> Void
    let onPair: () -> Void

    static let width: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            VStack(alignment: .leading, spacing: Theme.Spacing.row) {
                Text("Draw without the cable")
                    .font(.title2.bold())
                Text("""
                Your iPad can now share over Wi-Fi with the free SharePad app from \
                the App Store. Pair once, then open it and draw.
                """)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let pairing {
                PairingCodeBlock(pairing: pairing)
            } else {
                Text("To pair, click the SharePad icon in the menu bar, then Pair an iPad…")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("The cable still works as before.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                if let pairing, !pairing.display(at: .now).isPaired {
                    Button("Not Now", action: onDismiss)
                        .keyboardShortcut(.cancelAction)
                    Button("Pair an iPad…", action: onPair)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: onDismiss)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Theme.Spacing.window)
        .frame(width: Self.width)
    }
}

private struct PairingCodeBlock: View {
    let pairing: any PairingOffering

    var body: some View {
        HStack(spacing: Theme.Spacing.section) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                code(pairing.display(at: context.date))
            }
            .frame(width: Self.codeSide, height: Self.codeSide)
            Text("Scan with your iPad's camera to get the iPad app and pair in one go.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let codeSide: CGFloat = 132

    @ViewBuilder
    private func code(_ display: PairingCodeDisplay) -> some View {
        switch display {
        case .waiting:
            ProgressView()
        case let .live(url):
            QRCodeView(url: url)
        case let .pairing(iPad):
            VStack(spacing: Theme.Spacing.row) {
                ProgressView()
                Text("Pairing with \(iPad)…")
                    .multilineTextAlignment(.center)
            }
        case let .paired(iPad):
            Label("Paired with \(iPad)", systemImage: "checkmark.circle.fill")
                .multilineTextAlignment(.center)
        case .expired:
            Button("Show New Code") { pairing.requestNewOffer() }
        }
    }
}

private struct QRCodeView: View {
    let url: URL
    @State private var image: CGImage?

    var body: some View {
        // An empty Group never appears, so its `.task` would never run.
        ZStack {
            Color.clear
            if let image {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .padding(Theme.Spacing.row)
                    // Cameras read a QR as dark modules on light, so it keeps a white
                    // ground in dark mode too.
                    .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        }
        .task(id: url) { image = QRCodeImage.make(for: url) }
    }
}

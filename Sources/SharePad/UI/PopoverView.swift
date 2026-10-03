import AppKit
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    let updater: SoftwareUpdating

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            header

            shareLostBanner

            thumbnail

            statusText
                .foregroundStyle(.secondary)

            if let hint = statusHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            devicePicker

            stateAction

            Button(model.isWindowVisible ? "Hide Window" : "Show Window") {
                model.toggleWindow()
            }
            .disabled(!model.isConnected)

            if model.isWindowHotkeyActive {
                Text("Show or hide from anywhere: \(GlobalHotkey.WindowToggle.display)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if model.isWirelessAvailable {
                WirelessSectionView(model: model)
                Divider()
            }

            Toggle("Show window on connect", isOn: Binding(
                get: { model.autoShowOnConnect },
                set: { model.setAutoShow($0) }
            ))
            Toggle("Keep window on top", isOn: Binding(
                get: { model.keepOnTop },
                set: { model.setKeepOnTop($0) }
            ))
            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            if model.launchAtLoginFailed {
                Text("""
                Couldn't change Launch at login. \
                Set it in System Settings › General › Login Items.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Toggle("Send crash reports", isOn: Binding(
                get: { model.diagnosticsEnabled },
                set: { model.setDiagnosticsEnabled($0) }
            ))
            Text("Crashes, hangs and errors only. Never what's on your iPad, or your licence.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            licenseSection

            Button("Check for Updates…") { updater.checkForUpdates() }

            Button("Quit SharePad") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 260)
        .onAppear { model.popoverDidAppear() }
        .onDisappear { model.popoverDidDisappear() }
    }

    @ViewBuilder private var licenseSection: some View {
        switch model.entitlement {
        case .licensed:
            EmptyView()
        case let .trial(daysLeft):
            licenseRow(status: "Free trial: \(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
        case .trialExpired:
            trialExpiredRow
        }
    }

    @ViewBuilder private var trialExpiredRow: some View {
        if model.isTrialOverlayShown {
            licenseRow(status: "Sharing paused. Enter your licence key to resume.")
        } else if let endsAt = model.sessionEndsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                licenseRow(status: "Trial ended. Sharing pauses in "
                    + SessionCountdown.remainingText(until: endsAt, now: context.date) + ".")
            }
        } else {
            licenseRow(
                status: "Trial ended. Sharing pauses after up to "
                    + "\(model.sessionLimitMinutes) minutes."
            )
        }
    }

    private func licenseRow(status: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                if License.buyURL != nil {
                    Button("Buy a Licence") { model.openBuyPage() }
                }
                Button("Enter Licence…") { LicenseWindow.present(model: model) }
            }
            Divider()
        }
    }

    private var header: some View {
        HStack {
            Text("SharePad")
                .font(.headline)
            Spacer()
            Button {
                AboutPanel.present()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("About SharePad")
        }
    }

    @ViewBuilder private var shareLostBanner: some View {
        if let notice = model.shareLostNotice {
            HStack(spacing: Theme.Spacing.row) {
                Image(systemName: notice.symbol)
                    .foregroundStyle(.secondary)
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.dismissShareLost()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dismiss")
            }
            .padding(Theme.Spacing.row)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if model.isSharing {
            PreviewView(layer: model.thumbnailLayer)
                .frame(maxWidth: .infinity)
                .frame(height: 146)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))
        }
    }

    @ViewBuilder private var devicePicker: some View {
        if model.sourceOptions.count > 1 {
            Picker("Source", selection: Binding(
                get: { model.selectedSourceID },
                set: { model.selectSource(id: $0) }
            )) {
                ForEach(model.sourceOptions) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder private var stateAction: some View {
        switch model.state {
        case .permissionDenied:
            Button("Open System Settings") { model.openCameraSettings() }
        case .localNetworkDenied:
            Button("Open System Settings") { model.openLocalNetworkSettings() }
        case .failed(.usb):
            Button("Try Again") { model.retry() }
        default:
            EmptyView()
        }
    }

    private var statusText: Text {
        switch model.state {
        case .checkingPermission: Text("Requesting camera access…")
        case .permissionDenied: Text("Camera access is off")
        case .permissionRestricted: Text("Camera access is blocked")
        case .localNetworkDenied: Text("Local network access is off")
        case .noDevice: Text("No iPad connected")
        case .starting(.usb): Text("Connecting…")
        case .starting(.wireless): Text("Connecting to \(wirelessName) over Wi-Fi…")
        case .live(.usb): Text(model.currentDeviceName ?? "iPad")
        case .live(.wireless):
            Text(model.wirelessStatus.isReconnecting
                ? "Reconnecting to \(wirelessName)…"
                : "\(wirelessName) · Wi-Fi")
        case .failed(.usb): Text("Couldn't connect to your iPad")
        case .failed(.wireless): Text("Couldn't connect to your iPad over Wi-Fi")
        }
    }

    private var wirelessName: String {
        model.wirelessStatus.peer?.name ?? "iPad"
    }

    // A connected-but-locked or not-yet-trusted iPad shows up to discovery but never
    // starts a session, so it sits in .starting looking stuck (the hint also flashes
    // briefly on a healthy connect). The app can't tell "locked" from "still trusting".
    private var statusHint: String? {
        switch model.state {
        case .noDevice where model.wirelessStatus.pairingStoreFailed:
            "Couldn’t read paired iPads from the Keychain. The cable still works."
        case .noDevice where model.wirelessStatus.listenerFailed:
            "Wi-Fi sharing couldn't start. SharePad will keep trying. The cable still works."
        case .noDevice: "Plug your iPad in with its cable to begin."
        case .starting(.usb): "Unlock your iPad and tap Trust if it asks."
        case .failed(.usb): "Unlock it, check the cable, then try again."
        case .permissionDenied:
            """
            SharePad sees your iPad through camera access. \
            Turn it on in Privacy & Security › Camera.
            """
        case .permissionRestricted:
            "SharePad needs it to see your iPad. Ask whoever manages this Mac."
        case .localNetworkDenied: "Turn SharePad on under Local Network to share over Wi-Fi."
        case .live(.wireless) where model.isCameraAccessDenied:
            "Sharing over the cable needs camera access."
        default: nil
        }
    }
}

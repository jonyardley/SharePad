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

            Button(model.isWindowVisible ? "Hide window" : "Show window") {
                model.toggleWindow()
            }
            .disabled(!model.isConnected)

            if model.isWindowHotkeyActive {
                Text("Toggle from anywhere: \(GlobalHotkey.WindowToggle.display)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            wirelessSection

            Toggle("Auto-show on connect", isOn: Binding(
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
                Text("Couldn't change the login item — open System Settings › Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Send anonymous crash reports", isOn: Binding(
                get: { model.diagnosticsEnabled },
                set: { model.setDiagnosticsEnabled($0) }
            ))
            Text("Off by default. Crash and error diagnostics only, never your content or licence.")
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
            licenseRow(status: "Free trial — \(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
        case .trialExpired:
            trialExpiredRow
        }
    }

    @ViewBuilder private var trialExpiredRow: some View {
        if model.isTrialOverlayShown {
            licenseRow(status: "Sharing paused — enter your licence to resume")
        } else if let endsAt = model.sessionEndsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                licenseRow(status: "Free trial ended — sharing pauses in "
                    + SessionCountdown.remainingText(until: endsAt, now: context.date))
            }
        } else {
            licenseRow(
                status: "Free trial ended — sharing pauses after \(model.sessionLimitMinutes) min"
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
                    Button("Buy a licence") { model.openBuyPage() }
                }
                Button("Enter licence…") { LicenseWindow.present(model: model) }
            }
            Divider()
        }
    }

    @ViewBuilder private var wirelessSection: some View {
        if model.isWirelessAvailable {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                wirelessRows(model.wirelessSection(now: context.date))
            }
            Divider()
        }
    }

    private func wirelessRows(_ section: WirelessSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Text("Wireless")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if section.showsIntro {
                Text(WirelessSection.intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(section.rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(row.name)
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if row.offersPairAgain {
                        Button("Pair again…") { PairingPanel.present(model: model) }
                            .buttonStyle(.link)
                    }
                    Button("Forget") { model.forgetIPad(id: row.id) }
                        .buttonStyle(.link)
                }
            }
            Button("Pair an iPad…") { PairingPanel.present(model: model) }
            if section.showsAllowToggle {
                Toggle("Allow wireless iPads", isOn: Binding(
                    get: { model.allowWireless },
                    set: { model.setAllowWireless($0) }
                ))
            }
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
        if model.shareLostSignal {
            HStack(spacing: Theme.Spacing.row) {
                Image(systemName: "cable.connector.slash")
                    .foregroundStyle(.secondary)
                Text("iPad disconnected")
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
            Button("Retry") { model.retry() }
        default:
            EmptyView()
        }
    }

    private var statusText: Text {
        switch model.state {
        case .checkingPermission: Text("Requesting camera access…")
        case .permissionDenied: Text("Camera access denied.")
        case .permissionRestricted: Text("Camera access is blocked by a device policy.")
        case .localNetworkDenied: Text("Local network access is off.")
        case .noDevice: Text("No iPad connected")
        case .starting(.usb): Text("Connecting…")
        case .starting(.wireless): Text("Connecting to \(wirelessName) over Wi-Fi…")
        case .live(.usb): Text(model.currentDeviceName ?? "iPad")
        case .live(.wireless):
            Text(model.wirelessStatus.isReconnecting
                ? "Reconnecting to \(wirelessName)…"
                : "\(wirelessName) · Wi-Fi")
        case .failed(.usb): Text("Couldn't start the iPad feed.")
        case .failed(.wireless): Text("Couldn't show the Wi-Fi feed.")
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
            "Wi-Fi sharing couldn't start; SharePad keeps retrying. The cable still works."
        case .noDevice: "Plug your iPad in with its cable to begin."
        case .starting(.usb): "Unlock your iPad and tap Trust if it asks."
        case .failed(.usb): "Check your iPad is unlocked and connected, then Retry."
        case .localNetworkDenied: "Turn SharePad on under Local Network to share over Wi-Fi."
        case .live(.wireless) where model.isCameraAccessDenied:
            "Sharing over the cable needs camera access."
        default: nil
        }
    }
}

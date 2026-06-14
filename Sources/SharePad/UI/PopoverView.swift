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
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("iPad disconnected — your share stopped.")
                    .font(.caption)
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
        if model.isLive {
            PreviewView(layer: model.thumbnailLayer)
                .frame(maxWidth: .infinity)
                .frame(height: 146)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))
        }
    }

    @ViewBuilder private var devicePicker: some View {
        if model.devices.count > 1 {
            Picker("Source", selection: Binding(
                get: { model.currentDeviceID ?? "" },
                set: { model.selectDevice(id: $0) }
            )) {
                ForEach(model.devices) { device in
                    Text(device.name).tag(device.id)
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
        case .failed:
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
        case .noDevice: Text("No iPad connected")
        case .starting: Text("Connecting…")
        case .live: Text(model.currentDeviceName ?? "iPad")
        case .failed: Text("Couldn't start the iPad feed.")
        }
    }
}

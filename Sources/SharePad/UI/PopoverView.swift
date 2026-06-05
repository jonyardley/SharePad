import AppKit
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @State private var showingLicense = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            header

            if model.isEntitled {
                thumbnail

                statusText
                    .foregroundStyle(.secondary)

                devicePicker

                stateAction

                Button(model.isWindowVisible ? "Hide window" : "Show window") {
                    model.toggleWindow()
                }
                .disabled(!model.isConnected)

                trialBanner
            } else {
                expiredSection
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

            Button("Quit SharePad") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 260)
        .onAppear { model.popoverDidAppear() }
        .onDisappear { model.popoverDidDisappear() }
        .sheet(isPresented: $showingLicense) { LicenseEntryView() }
    }

    @ViewBuilder private var trialBanner: some View {
        if case let .trial(days) = model.licenseState {
            Text("Trial — \(days) day\(days == 1 ? "" : "s") left")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var expiredSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Text(model.currentDeviceName ?? "No iPad connected")
                .foregroundStyle(.secondary)
            Text("Your trial has ended.")
                .font(.callout)
            Button("Buy SharePad") { model.openPurchasePage() }
            Button("Enter license key…") { showingLicense = true }
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
        case .noDevice: Text("No iPad connected")
        case .starting: Text("Connecting…")
        case .live: Text(model.currentDeviceName ?? "iPad")
        case .failed: Text("Couldn't start the iPad feed.")
        }
    }
}

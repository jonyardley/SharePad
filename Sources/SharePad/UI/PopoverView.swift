import AppKit
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Text("SharePad")
                .font(.headline)
            statusText
                .foregroundStyle(.secondary)

            stateAction

            Button(model.isWindowVisible ? "Hide window" : "Show window") {
                model.toggleWindow()
            }
            .disabled(!model.isConnected)

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

            Divider()

            Button("Quit SharePad") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 260)
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

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

    private var statusText: Text {
        switch model.permission {
        case .denied, .restricted:
            Text("Camera access denied — enable it in System Settings.")
        case .notDetermined:
            Text("Requesting camera access…")
        default:
            if let name = model.currentDeviceName {
                Text(name)
            } else {
                Text("No iPad connected")
            }
        }
    }
}

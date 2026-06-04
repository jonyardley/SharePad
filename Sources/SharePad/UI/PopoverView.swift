import AppKit
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading) {
            Text("SharePad")
                .font(.headline)
            statusText
                .foregroundStyle(.secondary)

            Divider()

            Button("Quit SharePad") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 240)
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

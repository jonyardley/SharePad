import AppKit
import SwiftUI

struct PopoverView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("SharePad")
                .font(.headline)
            Text("No iPad connected")
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
}

import SwiftUI

struct SettingsSheet: View {
    let model: PadModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Paired Macs") {
                    if model.isDevelopmentBuild {
                        Text("Development build: streams to any SharePad Mac on this Wi-Fi.")
                    } else {
                        Text("No Mac paired yet.")
                    }
                }
                Section {
                    Text(verbatim: "SharePad for Mac: sharepad.co")
                    Text(
                        "Your drawing goes only to your Mac, over your Wi-Fi. Nothing is collected."
                    )
                    .foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Version", value: model.appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

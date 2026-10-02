import SwiftUI

struct SettingsSheet: View {
    let model: PadModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Paired Macs") {
                    if model.pairings.macs.isEmpty {
                        Text("No Mac paired yet.")
                    }
                    ForEach(model.pairings.macs, id: \.peerID) { mac in
                        HStack {
                            Text(mac.peerName)
                            Spacer()
                            Button("Forget This Mac", role: .destructive) {
                                model.pairings.forget(id: mac.peerID)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button(model.pairings.pairButtonTitle) {
                        model.showPairing()
                    }
                }
                if model.pairings.storeFailed {
                    Section {
                        Text("This iPad couldn’t read or save its paired Macs.")
                            .foregroundStyle(.secondary)
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

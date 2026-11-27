import SwiftUI

struct SettingsSheet: View {
    let model: PadModel
    @Environment(\.dismiss) private var dismiss

    private static let aboutFooter = "Works with SharePad for Mac, from sharepad.co. "
        + "Your drawing goes only to your Mac, over your Wi-Fi. Nothing is collected."

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
                    .disabled(!model.pairings.screen.canStartPairing)
                }
                if let note = model.pairings.storeNote {
                    Section {
                        Text(verbatim: note)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    LinkRow(title: "Help", address: "https://sharepad.co/#support")
                    LinkRow(title: "Privacy", address: "https://sharepad.co/privacy.html")
                    LabeledContent("Version", value: model.appVersion)
                } header: {
                    Text("About")
                } footer: {
                    Text(Self.aboutFooter)
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

private struct LinkRow: View {
    let title: LocalizedStringKey
    let address: String

    var body: some View {
        if let url = URL(string: address) {
            Link(destination: url) {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }
}

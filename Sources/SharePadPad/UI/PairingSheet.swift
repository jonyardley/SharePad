import SwiftUI

struct PairingSheet: View {
    @Bindable var model: PadModel
    @State private var isScanning = false
    @State private var isTyping = false
    @State private var cameraUnavailable = false

    var body: some View {
        let screen = model.pairings.screen
        NavigationStack {
            Form {
                if screen.showsMacAppNote {
                    Section {
                        Text(verbatim: PairingScreenContent.macAppNote)
                    }
                }
                Section("Pair with your Mac") {
                    ForEach(Array(PairingScreenContent.steps.enumerated()), id: \.offset) { item in
                        Text("\(item.offset + 1). \(item.element)")
                    }
                }
                if !screen.isPaired {
                    entry(working: screen.isWorking)
                }
                if let status = screen.status {
                    Section {
                        HStack(spacing: Theme.Spacing.row) {
                            if screen.isWorking { ProgressView() }
                            Text(status)
                                .font(screen.isPaired ? .headline : .body)
                        }
                    }
                }
            }
            .navigationTitle("Pair with your Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if screen.isWorking {
                        Button("Cancel") { model.pairings.cancel() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(screen.isPaired ? "Done" : "Close") { model.isPairingShown = false }
                }
            }
        }
    }

    private func entry(working: Bool) -> some View {
        Section {
            if isScanning {
                QRScannerView(
                    onCode: { text in
                        let accepted = model.pairings.pairWithScannedCode(text)
                        if accepted { isScanning = false }
                        return accepted
                    },
                    onUnavailable: {
                        isScanning = false
                        cameraUnavailable = true
                    }
                )
                .frame(height: Theme.Pairing.scannerHeight)
                .listRowInsets(EdgeInsets())
            } else {
                Button("Scan code") {
                    cameraUnavailable = false
                    isScanning = true
                }
                .disabled(working)
            }
            if cameraUnavailable {
                Text("The camera is off for SharePad. Type the code instead.")
                    .foregroundStyle(.secondary)
            }
            if isTyping {
                TextField("Code from your Mac", text: Binding(
                    get: { model.pairings.typedCode },
                    set: { model.pairings.setTypedCode($0) }
                ))
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { model.pairings.pairWithTypedCode() }
                Button("Pair") { model.pairings.pairWithTypedCode() }
                    .disabled(!model.pairings.isTypedCodeComplete || working)
            } else {
                Button("Type the code instead") { isTyping = true }
            }
        }
    }
}

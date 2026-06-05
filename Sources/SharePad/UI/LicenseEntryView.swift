import SwiftUI

struct LicenseEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var key = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Text("Enter your license")
                .font(.headline)
            TextField("Name", text: $name)
            TextField("License key", text: $key)
            if invalid {
                Text("That key doesn't match — check the name and key from your receipt.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Activate") {
                    Task {
                        if await model.enterLicense(name: name, key: key) {
                            dismiss()
                        } else {
                            invalid = true
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || key.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

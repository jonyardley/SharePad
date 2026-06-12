import SwiftUI

struct LicenseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var key = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Text("Enter your licence")
                .font(.headline)
            TextField("Email used at purchase", text: $email)
            TextField("Licence key", text: $key)
            if failed {
                Text("That key doesn't match this email.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Lost your key?") { model.openRecoverPage() }
                    .buttonStyle(.link)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Activate") {
                    if model.enterLicense(email: email, key: key) {
                        dismiss()
                    } else {
                        failed = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(email.isEmpty || key.isEmpty)
            }
        }
        .padding()
        .frame(width: 340)
    }
}

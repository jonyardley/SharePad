import SwiftUI

struct TrialOverlayView: View {
    var onBuy: (() -> Void)?
    var onEnterLicense: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.section) {
            Image(systemName: "hourglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Your free trial has ended")
                .font(.title2.bold())
            Text("Add your licence to resume sharing. Works offline, no account, no more pauses.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.section) {
                if let onBuy {
                    Button("Buy a licence", action: onBuy)
                }
                Button("Enter licence", action: onEnterLicense)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.overlayInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

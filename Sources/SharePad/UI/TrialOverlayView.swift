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
            Text("Enter a licence key to carry on sharing. It works offline and needs no account.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.section) {
                if let onBuy {
                    Button("Buy a Licence", action: onBuy)
                }
                Button("Enter Licence…", action: onEnterLicense)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.overlayInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

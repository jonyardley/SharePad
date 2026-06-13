import SwiftUI

struct TrialOverlayView: View {
    var buyURL: URL? = License.buyURL

    var body: some View {
        VStack(spacing: Theme.Spacing.section) {
            Image(systemName: "hourglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Your free trial has ended")
                .font(.title2.bold())
            Text("Buy a licence to keep sharing your iPad, interruption-free.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let buyURL {
                Link("Buy a licence", destination: buyURL)
                    .buttonStyle(.borderedProminent)
            }
            Text("Already purchased? Open SharePad in the menu bar to enter your licence.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
        }
        .padding(Theme.Spacing.overlayInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

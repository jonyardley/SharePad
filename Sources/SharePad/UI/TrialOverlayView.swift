import SwiftUI

struct TrialOverlayView: View {
    var buyURL: URL? = License.buyURL

    var body: some View {
        VStack(spacing: Theme.Spacing.section) {
            Image(systemName: "hourglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Free trial ended")
                .font(.title2.bold())
            Text("Restart SharePad to keep sharing, or buy a licence to remove this pause.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let buyURL {
                Link("Buy SharePad", destination: buyURL)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.overlayInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

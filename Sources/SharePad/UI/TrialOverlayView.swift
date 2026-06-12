import SwiftUI

struct TrialOverlayView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.row * 2) {
            Image(systemName: "hourglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Free trial ended")
                .font(.title2.bold())
            Text("Restart SharePad to keep sharing, or buy a licence to remove this pause.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let url = License.buyURL {
                Link("Buy SharePad", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.row * 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

import SwiftUI

enum SessionCountdown {
    // Ceil so a full "M:SS" is shown for the first second and the clock reads 0:00
    // only at the deadline, never a second early.
    static func remainingText(until endsAt: Date, now: Date) -> String {
        let remaining = max(0, endsAt.timeIntervalSince(now))
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// A corner watermark on the shared feed counting down to the trial pause. It lives in
// the share window's SwiftUI root (see ShareRootView) so it composites over the
// layer-backed preview, which a foreign NSHostingView subview wouldn't reliably do.
struct TrialCountdownWatermark: View {
    let endsAt: Date

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = SessionCountdown.remainingText(until: endsAt, now: context.date)
                    // Monospaced digits keep every "M:SS" the same width, so the pill
                    // doesn't reflow each second as proportional glyphs change size.
                    Label("Free trial — pauses in \(remaining)", systemImage: "hourglass")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.vertical, Theme.Spacing.row)
                        .padding(.horizontal, Theme.Spacing.section)
                        .background(.black.opacity(0.55), in: Capsule())
                }
            }
        }
        .padding(Theme.Spacing.section)
    }
}

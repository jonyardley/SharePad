import SwiftUI

struct WirelessSectionView: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            rows(model.wirelessSection(now: context.date))
        }
    }

    private func rows(_ section: WirelessSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Text("Wireless")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if section.showsIntro {
                Text(WirelessSection.intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(section.rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(row.name)
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if row.offersPairAgain {
                        Button("Pair again…") { PairingPanel.present(model: model) }
                            .buttonStyle(.link)
                    }
                    Button("Forget") { model.forgetIPad(id: row.id) }
                        .buttonStyle(.link)
                }
            }
            Button("Pair an iPad…") { PairingPanel.present(model: model) }
            if section.showsAllowToggle {
                Toggle("Allow wireless iPads", isOn: Binding(
                    get: { model.allowWireless },
                    set: { model.setAllowWireless($0) }
                ))
            }
        }
    }
}

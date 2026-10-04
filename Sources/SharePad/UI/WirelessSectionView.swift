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
                    rowMenu(row)
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

    private func rowMenu(_ row: WirelessSection.Row) -> some View {
        Menu {
            if row.offersPairAgain {
                Button("Pair Again…") { PairingPanel.present(model: model) }
                Divider()
            }
            Button("Forget \(row.name)…", role: .destructive) {
                if ForgetConfirmation.confirm(name: row.name) {
                    model.forgetIPad(id: row.id)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Options for \(row.name)")
    }
}

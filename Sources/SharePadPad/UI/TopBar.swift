import SwiftUI

struct TopBar: View {
    @Bindable var model: PadModel

    var body: some View {
        HStack(spacing: Theme.Spacing.bar) {
            ConnectionPillView(pill: model.pill) { model.pillAction($0) }
            Spacer()
            Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }
                .disabled(!model.canRedo)
            Button {
                model.isPaperMenuShown = true
            } label: {
                Label("Paper", systemImage: "chevron.down")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .popover(isPresented: $model.isPaperMenuShown) {
                PaperPicker(paper: model.paper) { model.setPaper($0) }
            }
            Button("Clear") { model.clear() }
            Button("Settings", systemImage: "gearshape") { model.isSettingsShown = true }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, Theme.Spacing.bar)
        .padding(.vertical, Theme.Spacing.row)
        .background(.bar)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.tight) {
            configuration.title
            configuration.icon
        }
    }
}

struct ConnectionPillView: View {
    let pill: ConnectionPill
    let onAction: (ConnectionPill.Action) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Circle()
                .fill(Theme.Status.colour(pill.tone))
                .frame(width: 8, height: 8)
            Text(pill.text)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            if let action = pill.action {
                Button(title(for: action)) { onAction(action) }
                    .font(.callout.weight(.semibold))
            }
        }
        .padding(.horizontal, Theme.Spacing.row)
        .padding(.vertical, Theme.Spacing.tight)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func title(for action: ConnectionPill.Action) -> String {
        switch action {
        case .openSettings: "Settings"
        case .retryCapture: "Try Again"
        case .pair: "Pair…"
        case .pairAgain: "Pair Again…"
        }
    }
}

struct PaperPicker: View {
    let paper: Paper
    let onChange: (Paper) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            Picker("Paper", selection: binding(\.style)) {
                ForEach(PaperStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Tone", selection: binding(\.tone)) {
                ForEach(PaperTone.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        .pickerStyle(.segmented)
        .padding(Theme.Spacing.bar)
        .frame(minWidth: 280)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Paper, Value>) -> Binding<Value> {
        Binding(
            get: { paper[keyPath: keyPath] },
            set: { value in
                var updated = paper
                updated[keyPath: keyPath] = value
                onChange(updated)
            }
        )
    }
}

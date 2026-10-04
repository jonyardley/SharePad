import SwiftUI
import UIKit

struct ExportPopover: View {
    let model: PadModel

    var body: some View {
        // An embedded activity controller can close the popover itself, which
        // SwiftUI does not report through the binding; the overlay must still clear.
        ZStack {
            content
        }
        .onDisappear { model.isExportShown = false }
    }

    @ViewBuilder private var content: some View {
        if let file = model.exportFile {
            ActivityView(file: file) { model.isExportShown = false }
                .frame(width: Theme.Export.shareSize.width, height: Theme.Export.shareSize.height)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    if format != ExportFormat.allCases.first {
                        Divider()
                    }
                    Button { model.export(as: format) } label: { FormatRow(format: format) }
                        .buttonStyle(.plain)
                }
                if model.exportFailed {
                    Divider()
                    Text("The drawing couldn’t be saved. Try again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(Theme.Spacing.bar)
                }
            }
            .frame(minWidth: 260, alignment: .leading)
        }
    }
}

private struct FormatRow: View {
    let format: ExportFormat

    var body: some View {
        HStack(spacing: Theme.Spacing.row) {
            VStack(alignment: .leading, spacing: 2) {
                Text(format.title)
                Text(format.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: format.systemImage)
                .font(.title3)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, Theme.Spacing.bar)
        .padding(.vertical, Theme.Spacing.row)
        .contentShape(Rectangle())
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let file: URL
    let onFinish: () -> Void

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

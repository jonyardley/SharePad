import SwiftUI
import UIKit

struct ExportPopover: View {
    let model: PadModel

    var body: some View {
        if let file = model.exportFile {
            ActivityView(file: file) { model.isExportShown = false }
                .frame(width: Theme.Export.shareSize.width, height: Theme.Export.shareSize.height)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.row) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button(format.title) { model.export(as: format) }
                }
                if model.exportFailed {
                    Text("The drawing couldn’t be saved. Try again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Theme.Spacing.bar)
            .frame(minWidth: 220, alignment: .leading)
        }
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

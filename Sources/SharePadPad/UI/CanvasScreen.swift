import PencilKit
import SwiftUI

struct CanvasScreen: View {
    @Bindable var model: PadModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
            ZStack {
                PaperBackground(paper: model.paper)
                CanvasHost(controller: model.canvas)
            }
            .ignoresSafeArea(edges: [.bottom, .horizontal])
        }
        .sheet(isPresented: $model.isSettingsShown) {
            SettingsSheet(model: model)
        }
    }
}

private struct CanvasHost: UIViewRepresentable {
    let controller: CanvasController

    func makeUIView(context _: Context) -> CanvasHostView {
        controller.hostView
    }

    func updateUIView(_: CanvasHostView, context _: Context) {}
}

struct PaperBackground: View {
    let paper: Paper

    var body: some View {
        Canvas { context, size in
            let marking = Theme.Paper.marking(paper.tone)
            let step = Theme.Paper.gridSpacing
            switch paper.style {
            case .plain:
                break
            case .grid:
                var lines = Path()
                for x in stride(from: step, to: size.width, by: step) {
                    lines.move(to: CGPoint(x: x, y: 0))
                    lines.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: step, to: size.height, by: step) {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(lines, with: .color(marking), lineWidth: Theme.Paper.lineWidth)
            case .dots:
                let diameter = Theme.Paper.dotDiameter
                var dots = Path()
                for x in stride(from: step, to: size.width, by: step) {
                    for y in stride(from: step, to: size.height, by: step) {
                        dots.addEllipse(in: CGRect(
                            x: x - diameter / 2,
                            y: y - diameter / 2,
                            width: diameter,
                            height: diameter
                        ))
                    }
                }
                context.fill(dots, with: .color(marking))
            }
        }
        .background(Theme.Paper.surface(paper.tone))
    }
}

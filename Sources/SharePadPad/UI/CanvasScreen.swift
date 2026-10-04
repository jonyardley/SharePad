import PencilKit
import SwiftUI

struct CanvasScreen: View {
    @Bindable var model: PadModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
            ZStack {
                PaperLayer(model: model)
                CanvasHost(controller: model.canvas)
            }
            .ignoresSafeArea(edges: [.bottom, .horizontal])
        }
        .sheet(isPresented: $model.isSettingsShown) {
            SettingsSheet(model: model)
        }
        .sheet(isPresented: $model.isPairingShown) {
            PairingSheet(model: model)
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

private struct PaperLayer: View {
    let model: PadModel

    var body: some View {
        PaperBackground(paper: model.paper, viewport: model.viewport)
    }
}

struct PaperBackground: View {
    let paper: Paper
    var viewport = Board.home

    var body: some View {
        Canvas { context, size in
            let marking = Theme.Paper.marking(paper.tone)
            let grid = PaperGrid(
                spacing: Theme.Paper.gridSpacing,
                minimumGap: Theme.Paper.minimumGap,
                viewport: viewport,
                size: size
            )
            switch paper.style {
            case .plain:
                break
            case .grid:
                var lines = Path()
                for x in grid.columns {
                    lines.move(to: CGPoint(x: x, y: 0))
                    lines.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in grid.rows {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(lines, with: .color(marking), lineWidth: Theme.Paper.lineWidth)
            case .dots:
                let diameter = Theme.Paper.dotDiameter
                var dots = Path()
                for x in grid.columns {
                    for y in grid.rows {
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

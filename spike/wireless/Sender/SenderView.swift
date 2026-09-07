import PencilKit
import SwiftUI

struct SenderView: View {
    @State private var sender = ScreenCaptureSender()
    private let launchedAt = Date()

    var body: some View {
        ZStack(alignment: .top) {
            DrawingCanvas()
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: 24) {
                controls
                Spacer()
                // The counter is the measurement instrument: film this and the Mac
                // window in one shot, then read the delta frame by frame
                // (specs/wireless.md, Measurement method).
                TimelineView(.animation) { context in
                    Text(counter(at: context.date))
                        .font(.system(size: 64, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.yellow.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(20)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(sender.isCapturing ? "Stop streaming" : "Start streaming") {
                if sender.isCapturing {
                    sender.stop()
                } else {
                    sender.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(sender.isCapturing ? .red : .accentColor)

            Text(sender.statusText)
                .font(.callout.weight(.medium))

            Text(String(
                format: "%.1f fps · %.0f kbps · %d sent · %d dropped",
                sender.framesPerSecond,
                sender.kilobitsPerSecond,
                sender.encodedFrames,
                sender.droppedFrames
            ))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            if let errorText = sender.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func counter(at date: Date) -> String {
        String(format: "%08.1f", date.timeIntervalSince(launchedAt) * 1000)
    }
}

struct DrawingCanvas: UIViewRepresentable {
    func makeUIView(context _: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 8)
        return canvas
    }

    func updateUIView(_: PKCanvasView, context _: Context) {}
}

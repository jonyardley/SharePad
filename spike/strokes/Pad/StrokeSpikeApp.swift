import SwiftUI

@main
struct StrokeSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            SpikeView()
        }
    }
}

struct SpikeView: View {
    @State private var status = "Starting"
    @State private var controller = CanvasController()

    var body: some View {
        ZStack(alignment: .top) {
            CanvasHost(controller: controller)
                .ignoresSafeArea()
            HStack(spacing: 12) {
                Button("Snapshot") { controller.snapshot() }
                    .buttonStyle(.borderedProminent)
                Button("New session") { controller.newSession() }
                    .buttonStyle(.bordered)
                Text(status)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
        .preferredColorScheme(.light)
        .onAppear { controller.onStatus = { status = $0 } }
    }
}

struct CanvasHost: UIViewControllerRepresentable {
    let controller: CanvasController

    func makeUIViewController(context _: Context) -> CanvasController {
        controller
    }

    func updateUIViewController(_: CanvasController, context _: Context) {}
}

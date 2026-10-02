import SwiftUI

@main
struct PadApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = PadModel()

    var body: some Scene {
        WindowGroup {
            CanvasScreen(model: model)
                .onOpenURL { model.open($0) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.sceneChanged(phase)
        }
    }
}

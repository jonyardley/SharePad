import CoreGraphics

@MainActor
protocol ShareWindowControlling {
    func show(size: CGSize)
    func hide()
    func updateSize(_ size: CGSize)
    func setKeepOnTop(_ enabled: Bool)
    func setTrialOverlay(_ visible: Bool)
}

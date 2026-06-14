import CoreGraphics
import Foundation

@MainActor
protocol ShareWindowControlling {
    func show(size: CGSize)
    func hide()
    func updateSize(_ size: CGSize)
    func setKeepOnTop(_ enabled: Bool)
    func setTrialOverlay(_ visible: Bool)
    func setTrialCountdown(endsAt: Date?)
    func setTrialActions(onBuy: (() -> Void)?, onEnterLicense: @escaping () -> Void)
}

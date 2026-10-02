import CoreGraphics
import Foundation
import QuartzCore

@MainActor
protocol ShareWindowControlling {
    func show(size: CGSize)
    func hide()
    func updateSize(_ size: CGSize)
    func setFeedLayer(_ layer: CALayer)
    func setKeepOnTop(_ enabled: Bool)
    func setTrialOverlay(_ visible: Bool)
    func setTrialCountdown(endsAt: Date?)
    func setTrialActions(onBuy: (() -> Void)?, onEnterLicense: @escaping () -> Void)
}

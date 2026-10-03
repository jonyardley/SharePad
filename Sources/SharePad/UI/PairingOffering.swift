import Foundation

@MainActor
protocol PairingOffering: AnyObject {
    func display(at now: Date) -> PairingCodeDisplay
    func requestNewOffer()
    func endOffer()
    // Takes over the live offer, so `endOffer` is not called on this path.
    func openPairingWindow()
}

@MainActor
final class ModelPairingOffer: PairingOffering {
    private let model: AppModel
    private var requestedAt: Date?

    init(model: AppModel) {
        self.model = model
    }

    func display(at now: Date) -> PairingCodeDisplay {
        PairingCodeDisplay(model.wirelessStatus.pairing, at: now, requestedAt: requestedAt)
    }

    func requestNewOffer() {
        requestedAt = .now
        model.pairIPad()
    }

    func endOffer() {
        guard !PairingPanel.isShown else { return }
        model.closePairing()
    }

    func openPairingWindow() {
        PairingPanel.present(model: model, mintingCode: !display(at: .now).hasLiveCode)
    }
}

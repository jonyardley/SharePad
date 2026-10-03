import Foundation

@MainActor
protocol PairingOffering: AnyObject {
    var progress: PairingProgress { get }
    func requestNewOffer()
    func endOffer()
    // Takes over the live offer, so `endOffer` is not called on this path.
    func openPairingWindow()
}

@MainActor
final class ModelPairingOffer: PairingOffering {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var progress: PairingProgress {
        model.wirelessStatus.pairing
    }

    func requestNewOffer() {
        model.pairIPad()
    }

    func endOffer() {
        model.closePairing()
    }

    func openPairingWindow() {
        let display = PairingCodeDisplay(progress, at: .now)
        let isLive = switch display {
        case .live, .pairing: true
        case .waiting, .paired, .expired: false
        }
        PairingPanel.present(model: model, mintingCode: !isLive)
    }
}

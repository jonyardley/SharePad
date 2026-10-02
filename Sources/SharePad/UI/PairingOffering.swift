import Foundation

struct PairingOffer: Equatable {
    let invitationURL: URL
    let expiresAt: Date

    enum Display: Equatable {
        case waiting
        case live(URL)
        case expired

        init(_ offer: PairingOffer?, at now: Date) {
            guard let offer else {
                self = .waiting
                return
            }
            self = now >= offer.expiresAt ? .expired : .live(offer.invitationURL)
        }
    }
}

@MainActor
protocol PairingOffering: AnyObject {
    var currentOffer: PairingOffer? { get }
    func requestNewOffer()
    func endOffer()
    // Takes over the live offer, so `endOffer` is not called on this path.
    func openPairingWindow()
}

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

// The seam the what's-new window pairs through; W2b supplies the conforming type (#170).
@MainActor
protocol PairingOffering: AnyObject {
    var currentOffer: PairingOffer? { get }
    func requestNewOffer()
    func endOffer()
    func openPairingWindow()
}

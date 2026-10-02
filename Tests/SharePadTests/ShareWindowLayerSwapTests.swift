import AVFoundation
@testable import SharePad
import XCTest

@MainActor
final class ShareWindowLayerSwapTests: XCTestCase {
    func testSwapWhileHiddenHostsTheNewLayerWhenShownAgain() throws {
        let name = "sharepad.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        let preferences = try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: name)))
        let preview = AVCaptureVideoPreviewLayer()
        let decoded = AVSampleBufferDisplayLayer()
        let controller = ShareWindowController(previewLayer: preview, preferences: preferences)
        addTeardownBlock { @MainActor in controller.hide() }

        controller.show(size: CGSize(width: 1280, height: 800))
        pump()
        XCTAssertNotNil(preview.superlayer)

        controller.hide()
        controller.setFeedLayer(decoded)
        controller.show(size: CGSize(width: 1280, height: 800))
        pump()

        XCTAssertNil(preview.superlayer)
        XCTAssertNotNil(decoded.superlayer)
        XCTAssertGreaterThan(decoded.frame.width, 0)
        XCTAssertEqual(decoded.frame, decoded.superlayer?.bounds)
    }

    func testSwapBeforeFirstShowHostsTheNewLayer() throws {
        let name = "sharepad.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        let preferences = try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: name)))
        let decoded = AVSampleBufferDisplayLayer()
        let controller = ShareWindowController(
            previewLayer: AVCaptureVideoPreviewLayer(),
            preferences: preferences
        )
        addTeardownBlock { @MainActor in controller.hide() }

        controller.setFeedLayer(decoded)
        controller.show(size: CGSize(width: 1280, height: 800))
        pump()

        XCTAssertNotNil(decoded.superlayer)
        XCTAssertGreaterThan(decoded.frame.width, 0)
    }

    func testAutoShowFromWirelessCreatesAVisibleWindowHostingTheDecodedLayer() throws {
        let name = "sharepad.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        let preferences = try Preferences(defaults: XCTUnwrap(UserDefaults(suiteName: name)))
        let capture = FakeCaptureController()
        let wireless = FakeWirelessFeed()
        let window = ShareWindowController(
            previewLayer: AVCaptureVideoPreviewLayer(),
            preferences: preferences
        )
        addTeardownBlock { @MainActor in window.hide() }
        let model = AppModel(
            preferences: preferences,
            capture: capture,
            wireless: wireless,
            window: window,
            sleep: { _ in }
        )
        let peer = WirelessPeer(id: UUID(), name: "iPad")

        model.applyWireless(WirelessStatus(localNetwork: .granted))
        model.applyWireless(WirelessStatus(peer: peer, localNetwork: .granted))
        model.applyWireless(WirelessStatus(peer: peer, isReceiving: true, localNetwork: .granted))

        let atShow = try XCTUnwrap(NSApp.windows
            .first { $0.identifier == WindowSharing.shareWindowID })
        let content = try XCTUnwrap(atShow.contentView).bounds.size
        XCTAssertEqual(wireless.hostedLayer.bounds.size, content, "sized before any run-loop turn")
        XCTAssertGreaterThan(content.width, 1)
        pump()

        let shown = NSApp.windows.first { $0.identifier == WindowSharing.shareWindowID }
        XCTAssertEqual(shown?.isVisible, true)
        let layer = wireless.hostedLayer
        let parent = try XCTUnwrap(layer.superlayer)
        XCTAssertTrue(parent.sublayers?.last === layer)
        XCTAssertEqual(layer.frame, parent.bounds)
        XCTAssertGreaterThan(layer.bounds.width, 1)
        XCTAssertFalse(layer.isHidden)
        XCTAssertEqual(layer.opacity, 1)
        let chain = ShareWindowController.layerChain(from: layer, upTo: shown?.contentView?.layer)
        XCTAssertTrue(chain.hasPrefix("CALayer["), chain)
        XCTAssertFalse(chain.contains("hidden=true"), chain)
    }

    private func pump() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    }
}

import Foundation

struct StreamingRules: Equatable {
    // Long enough to ride out a Wi-Fi blip without stopping ReplayKit, whose restart
    // may ask the user for consent again (specs/wireless-product.md §11, item 2).
    static let captureHold: TimeInterval = 10

    enum Scene: Equatable {
        case active
        case inactive
        case background
    }

    enum Capture: Equatable {
        case idle
        case starting
        case running
        case stopping
    }

    enum Event: Equatable {
        case scene(Scene)
        case linkUp(Bool)
        case captureStarted
        case captureFailed
        case captureStopped
        case holdElapsed(Int)
        case retryCapture
    }

    enum Effect: Equatable {
        case startLink
        case stopLink
        case startCapture
        case stopCapture
        case scheduleHold(Int, after: TimeInterval)
    }

    private(set) var isForeground = false
    private(set) var isLinkRunning = false
    private(set) var isLinkUp = false
    private(set) var capture = Capture.idle
    private(set) var captureDeclined = false
    private var holdID = 0
    private var isHolding = false

    mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case let .scene(scene):
            sceneChanged(scene)
        case let .linkUp(isUp):
            linkChanged(isUp: isUp)
        case .captureStarted:
            captureStarted()
        case .captureFailed:
            captureFailed()
        case .captureStopped:
            captureStopped()
        case let .holdElapsed(id):
            holdElapsed(id)
        case .retryCapture:
            retryCapture()
        }
    }

    private mutating func sceneChanged(_ scene: Scene) -> [Effect] {
        switch scene {
        case .active:
            isForeground = true
            var effects: [Effect] = []
            if !isLinkRunning {
                isLinkRunning = true
                effects.append(.startLink)
            }
            return effects + startCaptureIfWanted()
        case .inactive:
            return []
        case .background:
            isForeground = false
            captureDeclined = false
            cancelHold()
            var effects: [Effect] = []
            if isLinkRunning {
                isLinkRunning = false
                isLinkUp = false
                effects.append(.stopLink)
            }
            return effects + stopCaptureIfRunning()
        }
    }

    private mutating func linkChanged(isUp: Bool) -> [Effect] {
        guard isLinkRunning else { return [] }
        isLinkUp = isUp
        if isUp {
            cancelHold()
            return startCaptureIfWanted()
        }
        guard capture == .running || capture == .starting, !isHolding else { return [] }
        isHolding = true
        holdID += 1
        return [.scheduleHold(holdID, after: Self.captureHold)]
    }

    private mutating func captureStarted() -> [Effect] {
        switch capture {
        case .starting:
            capture = .running
            return []
        case .stopping:
            return [.stopCapture]
        case .idle where !isForeground || !isLinkUp:
            capture = .stopping
            return [.stopCapture]
        case .idle, .running:
            return []
        }
    }

    private mutating func captureFailed() -> [Effect] {
        let wasStarting = capture == .starting
        capture = .idle
        if wasStarting { captureDeclined = true }
        return []
    }

    private mutating func captureStopped() -> [Effect] {
        guard capture == .stopping || capture == .running else { return [] }
        capture = .idle
        return startCaptureIfWanted()
    }

    private mutating func holdElapsed(_ id: Int) -> [Effect] {
        guard isHolding, id == holdID else { return [] }
        isHolding = false
        guard !isLinkUp else { return [] }
        return stopCaptureIfRunning()
    }

    private mutating func retryCapture() -> [Effect] {
        captureDeclined = false
        return startCaptureIfWanted()
    }

    private mutating func startCaptureIfWanted() -> [Effect] {
        guard isForeground, isLinkUp, capture == .idle, !captureDeclined else { return [] }
        capture = .starting
        return [.startCapture]
    }

    private mutating func stopCaptureIfRunning() -> [Effect] {
        guard capture == .running || capture == .starting else { return [] }
        capture = .stopping
        return [.stopCapture]
    }

    private mutating func cancelHold() {
        guard isHolding else { return }
        isHolding = false
        holdID += 1
    }
}

import UIKit
import UIKit.UIGestureRecognizerSubclass

// Watches the canvas's touches without taking part: it never recognises, never
// cancels or delays them, so PencilKit draws exactly as it would without it.
// PencilKit only reports a stroke once the pen lifts, so this is the only live
// source of points (Apple forum threads 791907, 831523).
final class TouchTap: UIGestureRecognizer, UIGestureRecognizerDelegate {
    enum Event {
        case began(id: Int, touchType: String, time: TimeInterval)
        case moved(id: Int, points: [[Double]])
        case ended(id: Int, time: TimeInterval, cancelled: Bool)
    }

    private weak var canvas: UIView?
    private let emit: (Event) -> Void
    private var tracked: [ObjectIdentifier: Int] = [:]
    private var nextID = 0
    private var pencilSeen = false

    init(canvas: UIView, emit: @escaping (Event) -> Void) {
        self.canvas = canvas
        self.emit = emit
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if event.allTouches?.count ?? 0 > 1, !pencilSeen { return }
        for touch in touches {
            if touch.type == .pencil { pencilSeen = true }
            guard touch.type == .pencil || !pencilSeen else { continue }
            nextID += 1
            tracked[ObjectIdentifier(touch)] = nextID
            emit(.began(
                id: nextID,
                touchType: touch.type == .pencil ? "pencil" : "finger",
                time: touch.timestamp
            ))
            record(touch, event: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            record(touch, event: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, event: event, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, event: event, cancelled: true)
    }

    override func reset() {
        tracked.removeAll()
    }

    private func record(_ touch: UITouch, event: UIEvent) {
        guard let id = tracked[ObjectIdentifier(touch)],
              let canvas = canvas as? UIScrollView else { return }
        let zoom = canvas.zoomScale
        let samples = event.coalescedTouches(for: touch) ?? [touch]
        let points = samples.map { sample -> [Double] in
            let location = sample.preciseLocation(in: canvas)
            return [
                location.x / zoom,
                location.y / zoom,
                sample.timestamp,
                sample.force,
                sample.maximumPossibleForce,
                sample.azimuthAngle(in: canvas),
                sample.altitudeAngle,
            ]
        }
        emit(.moved(id: id, points: points))
    }

    private func finish(_ touches: Set<UITouch>, event: UIEvent, cancelled: Bool) {
        for touch in touches {
            guard let id = tracked[ObjectIdentifier(touch)] else { continue }
            if !cancelled { record(touch, event: event) }
            tracked[ObjectIdentifier(touch)] = nil
            emit(.ended(id: id, time: touch.timestamp, cancelled: cancelled))
        }
        if tracked.isEmpty { state = .failed }
    }
}

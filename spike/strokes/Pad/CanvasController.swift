import PencilKit
import UIKit

final class CanvasController: UIViewController, PKCanvasViewDelegate {
    var onStatus: ((String) -> Void)?

    private let canvas = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private var recorder = SessionRecorder()
    private lazy var tap = TouchTap(canvas: canvas) { [weak self] event in
        self?.handle(event)
    }

    private var strokesBegun = 0
    private var drawingChanges = 0
    private var snapshots = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .white
        canvas.drawingPolicy = .anyInput
        canvas.minimumZoomScale = 0.5
        canvas.maximumZoomScale = 4
        canvas.delegate = self
        canvas.addGestureRecognizer(tap)
        view.addSubview(canvas)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        toolPicker.addObserver(canvas)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        canvas.becomeFirstResponder()
        recorder.start(canvasSize: canvas.bounds.size, scale: traitCollection.displayScale)
        report()
    }

    func snapshot() {
        let rect = visibleRect
        let scale = traitCollection.displayScale
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = canvas.drawing.image(from: rect, scale: scale)
        }
        snapshots += 1
        recorder.snapshot(
            index: snapshots,
            png: image.pngData() ?? Data(),
            drawing: canvas.drawing,
            rect: rect,
            scale: scale
        )
        report()
    }

    func newSession() {
        canvas.drawing = PKDrawing()
        strokesBegun = 0
        drawingChanges = 0
        snapshots = 0
        recorder = SessionRecorder()
        recorder.start(canvasSize: canvas.bounds.size, scale: traitCollection.displayScale)
        report()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        drawingChanges += 1
        recorder.drawingChanged(
            canvasView.drawing,
            visible: visibleRect,
            zoom: canvasView.zoomScale
        )
        report()
    }

    private var visibleRect: CGRect {
        let zoom = canvas.zoomScale
        return CGRect(
            x: canvas.contentOffset.x / zoom,
            y: canvas.contentOffset.y / zoom,
            width: canvas.bounds.width / zoom,
            height: canvas.bounds.height / zoom
        )
    }

    private func handle(_ event: TouchTap.Event) {
        switch event {
        case let .began(id, touchType, time):
            strokesBegun += 1
            recorder.strokeBegan(id: id, tool: canvas.tool, touchType: touchType, time: time)
        case let .moved(id, points):
            recorder.points(id: id, points: points)
        case let .ended(id, time, cancelled):
            recorder.strokeEnded(id: id, time: time, cancelled: cancelled)
        }
        report()
    }

    private func report() {
        onStatus?(
            "\(recorder.fileName) · \(strokesBegun) strokes · \(drawingChanges) changes · \(snapshots) snaps"
        )
    }
}

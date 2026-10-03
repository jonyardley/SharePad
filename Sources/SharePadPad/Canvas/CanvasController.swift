import PencilKit
import UIKit

final class CanvasHostView: UIView {
    var onLayout: (() -> Void)?
    var onWindow: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindow?()
    }
}

@MainActor
final class CanvasController: NSObject {
    let hostView = CanvasHostView()

    var onDrawingChange: ((PKDrawing) -> Void)?
    var onUndoChange: ((_ canUndo: Bool, _ canRedo: Bool) -> Void)?
    var onLayoutChange: ((CanvasLayout) -> Void)?
    var onToolsUnlocated: ((Bool) -> Void)?
    var onFrameTick: (() -> Void)?

    private let canvasView = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private var displayLink: CADisplayLink?
    private var lastLayout: CanvasLayout?
    private var lastToolsUnknown: Bool?

    init(drawing: PKDrawing) {
        super.init()
        canvasView.drawing = drawing
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .default
        canvasView.isScrollEnabled = false
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.delegate = self
        canvasView.frame = hostView.bounds
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostView.addSubview(canvasView)
        hostView.onLayout = { [weak self] in self?.reportLayout() }
        hostView.onWindow = { [weak self] in self?.movedToWindow() }
        toolPicker.addObserver(canvasView)
        toolPicker.addObserver(self)
    }

    var drawing: PKDrawing {
        canvasView.drawing
    }

    func showToolPicker() {
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        canvasView.becomeFirstResponder()
    }

    func undo() {
        canvasView.undoManager?.undo()
        reportUndo()
    }

    func redo() {
        canvasView.undoManager?.redo()
        reportUndo()
    }

    func clear() {
        let previous = canvasView.drawing
        guard !previous.strokes.isEmpty else { return }
        replaceDrawing(with: PKDrawing())
    }

    func apply(tone: PaperTone) {
        let style: UIUserInterfaceStyle = tone == .dark ? .dark : .light
        canvasView.overrideUserInterfaceStyle = style
        toolPicker.colorUserInterfaceStyle = style
    }

    private func replaceDrawing(with drawing: PKDrawing) {
        let previous = canvasView.drawing
        canvasView.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.replaceDrawing(with: previous) }
        }
        canvasView.drawing = drawing
        reportUndo()
    }

    private func movedToWindow() {
        displayLink?.invalidate()
        displayLink = nil
        if hostView.window != nil {
            showToolPicker()
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        reportLayout()
    }

    // The palette can be dragged without any PKToolPickerObserver callback carrying
    // its position, so it is re-measured every display frame.
    @objc private func tick() {
        reportLayout()
        onFrameTick?()
    }

    private func reportLayout() {
        guard let window = hostView.window else { return }
        let obscured = toolPicker.frameObscured(in: hostView)
        let placement = ToolsPlacement.resolve(
            pickerVisible: toolPicker.isVisible,
            reported: obscured.isNull ? .null : hostView.convert(obscured, to: window),
            measured: PaletteLocator.paletteFrames(over: window),
            window: window.bounds
        )
        let layout = CanvasLayout(
            canvas: hostView.convert(hostView.bounds, to: window),
            window: window.bounds.size,
            obstructions: placement.obstructions
        )
        if placement.isUnknown != lastToolsUnknown {
            lastToolsUnknown = placement.isUnknown
            onToolsUnlocated?(placement.isUnknown)
        }
        if layout != lastLayout {
            lastLayout = layout
            onLayoutChange?(layout)
        }
    }

    private func reportUndo() {
        let manager = canvasView.undoManager
        onUndoChange?(manager?.canUndo ?? false, manager?.canRedo ?? false)
    }
}

#if DEBUG
    extension CanvasController {
        var canvasSize: CGSize {
            canvasView.bounds.size
        }

        var displayScale: CGFloat {
            hostView.traitCollection.displayScale
        }

        func drawCanvas(in context: CGContext, method: CanvasSnapshotMethod) {
            switch method {
            case .hierarchy:
                UIGraphicsPushContext(context)
                canvasView.drawHierarchy(in: canvasView.bounds, afterScreenUpdates: false)
                UIGraphicsPopContext()
            case .layer:
                canvasView.layer.render(in: context)
            }
        }
    }
#endif

extension CanvasController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        onDrawingChange?(canvasView.drawing)
        reportUndo()
    }
}

extension CanvasController: PKToolPickerObserver {
    func toolPickerFramesObscuredDidChange(_: PKToolPicker) {
        reportLayout()
    }

    func toolPickerVisibilityDidChange(_: PKToolPicker) {
        reportLayout()
    }
}

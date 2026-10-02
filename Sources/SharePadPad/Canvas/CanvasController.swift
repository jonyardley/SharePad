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

    private let canvasView = PKCanvasView()
    private let toolPicker = PKToolPicker()

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
        if hostView.window != nil {
            showToolPicker()
        }
        reportLayout()
    }

    private func reportLayout() {
        guard let window = hostView.window else { return }
        let obscured = toolPicker.frameObscured(in: hostView)
        let obstructions = obscured.isNull || obscured.isEmpty
            ? []
            : [hostView.convert(obscured, to: window)]
        onLayoutChange?(CanvasLayout(
            canvas: hostView.convert(hostView.bounds, to: window),
            window: window.bounds.size,
            obstructions: obstructions
        ))
    }

    private func reportUndo() {
        let manager = canvasView.undoManager
        onUndoChange?(manager?.canUndo ?? false, manager?.canRedo ?? false)
    }
}

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

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

    var onDrawingChange: (() -> Void)?
    var onLayoutChange: ((CanvasLayout) -> Void)?
    var onToolsUnlocated: ((Bool) -> Void)?
    var onFrameTick: (() -> Void)?
    var onViewportChange: ((Viewport) -> Void)?

    private let canvasView = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private var displayLink: CADisplayLink?
    private var lastLayout: CanvasLayout?
    private var lastToolsUnknown: Bool?
    private var pendingRestore: ((CGSize) -> Viewport)?
    private var laidOutSize: CGSize?

    init(drawing: PKDrawing, position: BoardPosition?) {
        pendingRestore = { size in
            position.map { Board.viewport(for: $0, in: size) } ?? Board.home
        }
        super.init()
        canvasView.drawing = drawing.transformed(using: Self.toBoard)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .default
        canvasView.isScrollEnabled = true
        canvasView.minimumZoomScale = Board.zoomRange.lowerBound
        canvasView.maximumZoomScale = Board.zoomRange.upperBound
        canvasView.showsHorizontalScrollIndicator = false
        canvasView.showsVerticalScrollIndicator = false
        canvasView.contentSize = Board.size
        canvasView.contentOffset = Board.home.offset
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.delegate = self
        canvasView.frame = hostView.bounds
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostView.addSubview(canvasView)
        hostView.onLayout = { [weak self] in
            self?.restorePosition()
            self?.reportLayout()
        }
        hostView.onWindow = { [weak self] in self?.movedToWindow() }
        toolPicker.addObserver(canvasView)
        toolPicker.addObserver(self)
    }

    private static let toBoard = CGAffineTransform(translationX: Board.origin.x, y: Board.origin.y)

    var drawing: PKDrawing {
        canvasView.drawing.transformed(using: Self.toBoard.inverted())
    }

    var hasStrokes: Bool {
        !canvasView.drawing.strokes.isEmpty
    }

    var viewport: Viewport {
        Viewport(offset: canvasView.contentOffset, zoom: canvasView.zoomScale)
    }

    var position: BoardPosition? {
        guard pendingRestore == nil, canvasView.bounds.size != .zero else { return nil }
        return Board.position(of: viewport, in: canvasView.bounds.size)
    }

    func fitDrawing() {
        let bounds = canvasView.drawing.bounds.offsetBy(dx: -Board.origin.x, dy: -Board.origin.y)
        show(Board.fit(bounds, in: canvasView.bounds.size))
    }

    func resetView() {
        show(Board.home)
    }

    func showToolPicker() {
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        canvasView.becomeFirstResponder()
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

    private func restorePosition() {
        let size = canvasView.bounds.size
        guard size != .zero, size != laidOutSize else { return }
        defer { laidOutSize = size }
        if let restore = pendingRestore {
            pendingRestore = nil
            show(restore(size))
        } else if let previous = laidOutSize {
            show(Board.viewport(for: Board.position(of: viewport, in: previous), in: size))
        }
    }

    // Not animated: the SwiftUI paper only hears the end state, so an animated
    // jump would slide the ink across a paper that has already moved.
    private func show(_ viewport: Viewport) {
        canvasView.zoomScale = viewport.zoom
        canvasView.contentSize = Board.size.applying(
            CGAffineTransform(scaleX: viewport.zoom, y: viewport.zoom)
        )
        canvasView.contentOffset = viewport.offset
        onViewportChange?(self.viewport)
    }

    private func replaceDrawing(with drawing: PKDrawing) {
        let previous = canvasView.drawing
        canvasView.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.replaceDrawing(with: previous) }
        }
        canvasView.drawing = drawing
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
                canvasView.drawHierarchy(
                    in: CGRect(origin: .zero, size: canvasView.bounds.size),
                    afterScreenUpdates: false
                )
                UIGraphicsPopContext()
            case .layer:
                context.translateBy(x: -canvasView.bounds.minX, y: -canvasView.bounds.minY)
                canvasView.layer.render(in: context)
            }
        }
    }
#endif

extension CanvasController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_: PKCanvasView) {
        onDrawingChange?()
    }

    func scrollViewDidScroll(_: UIScrollView) {
        onViewportChange?(viewport)
    }

    // Content size is in zoomed points, as in Apple's PencilKitDraw sample
    // (DrawingViewController.updateContentSizeForDrawing).
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let zoom = scrollView.zoomScale
        scrollView.contentSize = Board.size.applying(CGAffineTransform(scaleX: zoom, y: zoom))
        onViewportChange?(viewport)
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

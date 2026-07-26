import AppKit
import Observation
import SwiftUI

/// Interaction mode for the image view.
enum ImageTool: CaseIterable {
    case pan
    case select
}

/// Drives zoom, pan tool mode, and the crop selection on the current image.
/// Owned by the view; commands reach it via a focused value.
@Observable
final class ZoomController {
    /// Live magnification, where 1.0 == 100% (one image pixel per point).
    var magnification: CGFloat = 1

    /// Active tool. Switching away from Select clears any selection.
    var tool: ImageTool = .pan {
        didSet { if tool != .select { selection = nil } }
    }

    /// Current crop selection in image pixel coordinates (top-left origin), or nil.
    var selection: CGRect?

    /// True when there is a selection to crop.
    var canCrop: Bool { selection != nil }

    @ObservationIgnored weak var scrollView: ZoomScrollView?

    func zoomIn() { scrollView?.zoom(by: 1.25) }
    func zoomOut() { scrollView?.zoom(by: 1 / 1.25) }
    func zoomToFit() { scrollView?.zoomToFit() }
    func actualSize() { scrollView?.setZoom(1) }
}

/// A zoomable, pannable image view backed by AppKit's NSScrollView magnification,
/// with an optional rectangular crop selection.
struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    let controller: ZoomController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView()
        scrollView.controller = controller
        controller.scrollView = scrollView
        scrollView.setImage(image)
        context.coordinator.currentImage = image
        return scrollView
    }

    func updateNSView(_ scrollView: ZoomScrollView, context: Context) {
        scrollView.controller = controller
        controller.scrollView = scrollView
        if context.coordinator.currentImage !== image {
            context.coordinator.currentImage = image
            scrollView.setImage(image)
        }
        // Reflect tool/selection changes coming from SwiftUI (crop cleared it, tool switched, etc.).
        scrollView.syncToolState()
    }

    final class Coordinator {
        var currentImage: NSImage?
    }
}

/// Keeps the document centered when it is smaller than the viewport.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if rect.width > doc.frame.width {
            rect.origin.x = (doc.frame.width - rect.width) / 2
        }
        if rect.height > doc.frame.height {
            rect.origin.y = (doc.frame.height - rect.height) / 2
        }
        return rect
    }
}

/// NSScrollView subclass: scroll-to-zoom (centered at the cursor) and pinch-to-zoom.
final class ZoomScrollView: NSScrollView {
    weak var controller: ZoomController? {
        didSet { imageView.controller = controller }
    }

    private let imageView = ZoomImageView()
    private var pendingFit = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        contentView = CenteringClipView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.animates = false
        documentView = imageView

        allowsMagnification = true
        minMagnification = 0.02
        maxMagnification = 32
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        backgroundColor = .clear
        drawsBackground = false

        NotificationCenter.default.addObserver(
            self, selector: #selector(liveMagnifyEnded),
            name: NSScrollView.didEndLiveMagnifyNotification, object: self
        )
    }

    @objc private func liveMagnifyEnded() {
        controller?.magnification = magnification
    }

    /// Redraws the selection and refreshes the cursor after SwiftUI-side changes.
    func syncToolState() {
        imageView.needsDisplay = true
        window?.invalidateCursorRects(for: imageView)
    }

    // MARK: - Image

    func setImage(_ image: NSImage) {
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: Self.pixelSize(of: image))
        controller?.selection = nil
        pendingFit = true
        if bounds.width > 0, bounds.height > 0 {
            performFit()
        } else {
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        if pendingFit, bounds.width > 0, bounds.height > 0 {
            performFit()
        }
    }

    private func performFit() {
        pendingFit = false
        zoomToFit()
    }

    // MARK: - Zoom

    /// Fits the image within the viewport, never scaling a small image beyond 100%.
    func zoomToFit() {
        guard let doc = documentView, doc.bounds.width > 0, doc.bounds.height > 0 else { return }
        guard bounds.width > 0, bounds.height > 0 else { pendingFit = true; return }
        let fit = min(bounds.width / doc.bounds.width, bounds.height / doc.bounds.height)
        setZoom(min(fit, 1.0))
    }

    func setZoom(_ target: CGFloat, centeredAt point: NSPoint? = nil) {
        let clamped = min(max(target, minMagnification), maxMagnification)
        let center = point ?? NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        setMagnification(clamped, centeredAt: center)
        controller?.magnification = magnification
        imageView.needsDisplay = true
    }

    func zoom(by factor: CGFloat) {
        setZoom(magnification * factor)
    }

    // MARK: - Scroll to zoom (centered at the cursor)

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.004 : 0.03
        let factor = exp(delta * sensitivity)
        let cursor = contentView.convert(event.locationInWindow, from: nil)
        setZoom(magnification * factor, centeredAt: cursor)
    }

    static func pixelSize(of image: NSImage) -> NSSize {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSSize(width: cg.width, height: cg.height)
        }
        var size = NSSize.zero
        for rep in image.representations {
            size.width = max(size.width, CGFloat(rep.pixelsWide))
            size.height = max(size.height, CGFloat(rep.pixelsHigh))
        }
        return (size.width > 0 && size.height > 0) ? size : image.size
    }
}

/// The document view: grab-to-pan in Pan mode, and rectangular crop selection in Select mode.
final class ZoomImageView: NSImageView {
    weak var controller: ZoomController?

    private enum Drag {
        case pan
        case create(NSPoint)                 // anchor corner (view coords)
        case move(NSRect, NSPoint)           // starting selection rect + starting mouse
        case resize(ResizeAnchor, NSRect)    // anchor being dragged + starting rect
    }

    private enum ResizeAnchor { case tl, t, tr, l, r, bl, b, br }

    private var drag: Drag?
    private var lastPanPoint: NSPoint?

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }
    private var isSelecting: Bool { controller?.tool == .select }

    // MARK: - Coordinate conversion (view <-> image pixels, top-left origin)

    private func pixelRect(fromView v: NSRect) -> NSRect {
        NSRect(x: v.minX, y: bounds.height - v.maxY, width: v.width, height: v.height)
    }

    private func viewRect(fromPixel p: NSRect) -> NSRect {
        NSRect(x: p.minX, y: bounds.height - p.maxY, width: p.width, height: p.height)
    }

    private var selectionViewRect: NSRect? {
        controller?.selection.map { viewRect(fromPixel: $0) }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard isSelecting else {
            drag = .pan
            lastPanPoint = event.locationInWindow
            NSCursor.closedHand.set()
            return
        }

        if let rect = selectionViewRect {
            if let anchor = resizeAnchor(at: point, in: rect) {
                drag = .resize(anchor, rect)
            } else if rect.insetBy(dx: -1, dy: -1).contains(point) {
                drag = .move(rect, point)
            } else {
                drag = .create(point)
                setSelection(view: NSRect(origin: point, size: .zero))
            }
        } else {
            drag = .create(point)
            setSelection(view: NSRect(origin: point, size: .zero))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        switch drag {
        case .pan:
            panDrag(event)
        case .create(let anchor):
            let p = clampToBounds(convert(event.locationInWindow, from: nil))
            setSelection(view: normalizedRect(anchor, p))
        case .move(let startRect, let startPoint):
            let p = convert(event.locationInWindow, from: nil)
            setSelection(view: movedRect(startRect, by: NSPoint(x: p.x - startPoint.x, y: p.y - startPoint.y)))
        case .resize(let anchor, let startRect):
            let p = clampToBounds(convert(event.locationInWindow, from: nil))
            setSelection(view: resizedRect(startRect, anchor: anchor, to: p))
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case .pan = drag { NSCursor.arrow.set() }
        // Discard a zero-size selection left by a click without a drag.
        if let sel = controller?.selection, sel.width < 1 || sel.height < 1 {
            controller?.selection = nil
        }
        drag = nil
        lastPanPoint = nil
        needsDisplay = true
    }

    private func panDrag(_ event: NSEvent) {
        guard let last = lastPanPoint, let scrollView = enclosingScrollView else { return }
        let point = event.locationInWindow
        let dx = point.x - last.x
        let dy = point.y - last.y
        lastPanPoint = point
        var origin = scrollView.contentView.bounds.origin
        origin.x -= dx / magnification
        origin.y -= dy / magnification
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func setSelection(view rect: NSRect) {
        controller?.selection = pixelRect(fromView: rect)
        needsDisplay = true
    }

    // MARK: - Selection geometry (view coordinates)

    private func clampToBounds(_ p: NSPoint) -> NSPoint {
        NSPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func normalizedRect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func movedRect(_ rect: NSRect, by delta: NSPoint) -> NSRect {
        var r = rect.offsetBy(dx: delta.x, dy: delta.y)
        r.origin.x = min(max(r.origin.x, 0), bounds.width - r.width)
        r.origin.y = min(max(r.origin.y, 0), bounds.height - r.height)
        return r
    }

    private func resizedRect(_ start: NSRect, anchor: ResizeAnchor, to p: NSPoint) -> NSRect {
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        switch anchor {
        case .tl: minX = p.x; maxY = p.y
        case .t: maxY = p.y
        case .tr: maxX = p.x; maxY = p.y
        case .l: minX = p.x
        case .r: maxX = p.x
        case .bl: minX = p.x; minY = p.y
        case .b: minY = p.y
        case .br: maxX = p.x; minY = p.y
        }
        return NSRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    private func handlePoints(_ r: NSRect) -> [(ResizeAnchor, NSPoint)] {
        [
            (.tl, NSPoint(x: r.minX, y: r.maxY)), (.t, NSPoint(x: r.midX, y: r.maxY)), (.tr, NSPoint(x: r.maxX, y: r.maxY)),
            (.l, NSPoint(x: r.minX, y: r.midY)), (.r, NSPoint(x: r.maxX, y: r.midY)),
            (.bl, NSPoint(x: r.minX, y: r.minY)), (.b, NSPoint(x: r.midX, y: r.minY)), (.br, NSPoint(x: r.maxX, y: r.minY)),
        ]
    }

    private func resizeAnchor(at point: NSPoint, in rect: NSRect) -> ResizeAnchor? {
        let tolerance = 8 / magnification
        for (anchor, p) in handlePoints(rect) where abs(point.x - p.x) <= tolerance && abs(point.y - p.y) <= tolerance {
            return anchor
        }
        return nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isSelecting, let rect = selectionViewRect, rect.width > 0, rect.height > 0 else { return }

        let line = 1 / magnification

        // Dim everything outside the selection.
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: rect))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()

        // Dashed border.
        let border = NSBezierPath(rect: rect)
        border.lineWidth = line
        border.setLineDash([6 / magnification, 4 / magnification], count: 2, phase: 0)
        NSColor.white.setStroke()
        border.stroke()

        // Handles.
        let size = 8 / magnification
        for (_, p) in handlePoints(rect) {
            let handle = NSRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(rect: handle).fill()
            NSColor.systemGray.setStroke()
            let outline = NSBezierPath(rect: handle)
            outline.lineWidth = line
            outline.stroke()
        }
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isSelecting ? .crosshair : .openHand)
    }
}

// MARK: - Focused value plumbing

struct ZoomControllerKey: FocusedValueKey {
    typealias Value = ZoomController
}

extension FocusedValues {
    var zoomController: ZoomController? {
        get { self[ZoomControllerKey.self] }
        set { self[ZoomControllerKey.self] = newValue }
    }
}

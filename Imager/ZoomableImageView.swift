import AppKit
import Observation
import SwiftUI

/// Drives zoom on the current image. Owned by the view; commands reach it via a focused value.
@Observable
final class ZoomController {
    /// Live magnification, where 1.0 == 100% (one image pixel per point).
    var magnification: CGFloat = 1

    @ObservationIgnored weak var scrollView: ZoomScrollView?

    func zoomIn() { scrollView?.zoom(by: 1.25) }
    func zoomOut() { scrollView?.zoom(by: 1 / 1.25) }
    func zoomToFit() { scrollView?.zoomToFit() }
    func actualSize() { scrollView?.setZoom(1) }
}

/// A zoomable, pannable image view backed by AppKit's NSScrollView magnification.
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
        // Only reset when the image itself changes (not on unrelated state updates).
        if context.coordinator.currentImage !== image {
            context.coordinator.currentImage = image
            scrollView.setImage(image)
        }
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

/// NSScrollView subclass: scroll-to-zoom (centered at the cursor), drag-to-pan, pinch-to-zoom.
final class ZoomScrollView: NSScrollView {
    weak var controller: ZoomController?

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

    // MARK: - Image

    func setImage(_ image: NSImage) {
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: Self.pixelSize(of: image))
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
        var size = NSSize.zero
        for rep in image.representations {
            size.width = max(size.width, CGFloat(rep.pixelsWide))
            size.height = max(size.height, CGFloat(rep.pixelsHigh))
        }
        return (size.width > 0 && size.height > 0) ? size : image.size
    }
}

/// The document view. Handles grab-to-pan and shows a grab cursor.
final class ZoomImageView: NSImageView {
    private var lastPanPoint: NSPoint?

    override func mouseDown(with event: NSEvent) {
        lastPanPoint = event.locationInWindow
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastPanPoint,
              let scrollView = enclosingScrollView else { return }
        let point = event.locationInWindow
        let dx = point.x - last.x
        let dy = point.y - last.y
        lastPanPoint = point

        // Grab-scroll: content follows the cursor (non-flipped document coordinates).
        let magnification = scrollView.magnification
        var origin = scrollView.contentView.bounds.origin
        origin.x -= dx / magnification
        origin.y -= dy / magnification
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    override func mouseUp(with event: NSEvent) {
        lastPanPoint = nil
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
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

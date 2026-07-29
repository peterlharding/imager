import AppKit
import Testing
@testable import Imager

/// Covers how the image view responds to the viewport changing size, which is what
/// happens when a slideshow drops out of full screen or the window is resized.
@Suite("ZoomScrollView viewport changes", .serialized)
@MainActor
struct ZoomScrollViewTests {

    private func makeScrollView(width: CGFloat, height: CGFloat) -> ZoomScrollView {
        let view = ZoomScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// Where the clip view has been scrolled to. When the image is smaller than the
    /// viewport this should be centred, i.e. half the overhang on each side.
    private func originX(_ view: ZoomScrollView) -> CGFloat {
        view.contentView.bounds.origin.x
    }

    private func expectedCentredOriginX(viewport: CGFloat, image: CGFloat, magnification: CGFloat) -> CGFloat {
        (image - viewport / magnification) / 2
    }

    /// The reported bug: after a slideshow ends, the image sits off to one side with
    /// a gap on the left, because the viewport shrank without the centring being redone.
    @Test("Shrinking the viewport keeps a small image centred")
    func shrinkingViewportRecentresSmallImage() {
        let view = makeScrollView(width: 800, height: 600)
        view.setImage(TestSupport.solidImage(width: 200, height: 100))
        view.layoutSubtreeIfNeeded()

        #expect(abs(view.magnification - 1) < 0.001, "a small image is shown at 100%")
        #expect(abs(originX(view) - expectedCentredOriginX(viewport: 800, image: 200, magnification: 1)) < 1,
                "centred in the large viewport")

        // Collapse the viewport, as leaving full screen does.
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        view.layoutSubtreeIfNeeded()

        #expect(abs(originX(view) - expectedCentredOriginX(viewport: 400, image: 200, magnification: 1)) < 1,
                "still centred in the smaller viewport")
    }

    @Test("Growing the viewport keeps a small image centred")
    func growingViewportRecentresSmallImage() {
        let view = makeScrollView(width: 400, height: 300)
        view.setImage(TestSupport.solidImage(width: 200, height: 100))
        view.layoutSubtreeIfNeeded()

        view.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        view.layoutSubtreeIfNeeded()

        #expect(abs(originX(view) - expectedCentredOriginX(viewport: 900, image: 200, magnification: 1)) < 1)
    }

    /// A fitted image should stay fitted when the window changes size, rather than
    /// keeping a magnification chosen for a viewport that no longer exists.
    @Test("A fitted image re-fits when the viewport shrinks")
    func fittedImageRefitsOnShrink() {
        let view = makeScrollView(width: 800, height: 600)
        view.setImage(TestSupport.solidImage(width: 1600, height: 1200))
        view.layoutSubtreeIfNeeded()

        #expect(abs(view.magnification - 0.5) < 0.01, "fitted to the large viewport")

        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        view.layoutSubtreeIfNeeded()

        #expect(abs(view.magnification - 0.25) < 0.01, "re-fitted to the smaller viewport")
    }

    @Test("A fitted image re-fits when the viewport grows")
    func fittedImageRefitsOnGrow() {
        let view = makeScrollView(width: 400, height: 300)
        view.setImage(TestSupport.solidImage(width: 1600, height: 1200))
        view.layoutSubtreeIfNeeded()

        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.layoutSubtreeIfNeeded()

        #expect(abs(view.magnification - 0.5) < 0.01)
    }

    /// Resizing must not undo a zoom the user chose deliberately.
    @Test("A deliberate zoom survives a viewport change")
    func explicitZoomIsNotOverridden() {
        let view = makeScrollView(width: 800, height: 600)
        view.setImage(TestSupport.solidImage(width: 1600, height: 1200))
        view.layoutSubtreeIfNeeded()

        view.setZoom(2)
        #expect(abs(view.magnification - 2) < 0.01)

        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        view.layoutSubtreeIfNeeded()

        #expect(abs(view.magnification - 2) < 0.01, "the user's zoom is preserved")
    }

    /// The slideshow sequence: a windowed viewport, then full screen, then slides
    /// arriving one after another. Every slide should end up fitted.
    @Test("Each slide is fitted as a slideshow advances in a large viewport")
    func slideshowSequenceKeepsSlidesFitted() {
        let slide = { TestSupport.solidImage(width: 1200, height: 800) }

        let view = makeScrollView(width: 640, height: 400)
        view.setImage(slide())
        view.layoutSubtreeIfNeeded()
        #expect(abs(view.magnification - 0.5) < 0.01, "fitted to the window")

        // Entering full screen.
        view.frame = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        view.layoutSubtreeIfNeeded()
        #expect(abs(view.magnification - 1) < 0.01, "fit would be 1.4, but never scales past 100%")

        // Slides advancing.
        for _ in 0..<3 {
            view.setImage(slide())
            view.layoutSubtreeIfNeeded()
            #expect(abs(view.magnification - 1) < 0.01, "each slide stays fitted")
        }

        // Leaving full screen.
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        view.layoutSubtreeIfNeeded()
        #expect(abs(view.magnification - 0.5) < 0.01, "back to fitting the window")
    }

    /// A window resize does not necessarily mark the view as needing layout, so the
    /// re-fit cannot depend on a layout pass arriving. Entering full screen from a
    /// small window on a large display is where this shows: the viewport jumps a long
    /// way, and the image is left at a magnification chosen for the old size.
    @Test("Re-fits on a frame change even when no layout pass follows")
    func refitsOnFrameChangeWithoutLayoutPass() {
        let view = makeScrollView(width: 800, height: 600)
        view.setImage(TestSupport.solidImage(width: 2400, height: 1600))
        view.layoutSubtreeIfNeeded()

        let windowed = view.magnification
        #expect(abs(windowed - 1.0 / 3.0) < 0.01, "fitted to the small window")

        // Full screen on a wide display, with no explicit layout pass afterwards.
        view.setFrameSize(NSSize(width: 3840, height: 1560))

        let expected = min(3840.0 / 2400.0, 1560.0 / 1600.0)
        #expect(abs(view.magnification - expected) < 0.01, "re-fitted to the new viewport")
    }

    @Test("Actual size survives a viewport change")
    func actualSizeIsNotOverridden() {
        let view = makeScrollView(width: 800, height: 600)
        view.setImage(TestSupport.solidImage(width: 1600, height: 1200))
        view.layoutSubtreeIfNeeded()

        view.setZoom(1)

        view.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        view.layoutSubtreeIfNeeded()

        #expect(abs(view.magnification - 1) < 0.01)
    }
}

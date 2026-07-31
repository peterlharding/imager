import AppKit
import Testing
@testable import Imager

/// Covers the loupe's geometry, which is where the reasoning could go wrong.
///
/// The drawing itself is AppKit and needs a window, but the arithmetic is the risky part: the
/// relationship is inverse, so the further out the view is zoomed, the more the loupe magnifies.
@Suite("Loupe geometry")
struct LoupeTests {

    private func geometry(magnification: CGFloat, screenRadius: CGFloat = 70) -> LoupeGeometry {
        LoupeGeometry(magnification: magnification, screenRadius: screenRadius, targetZoom: 1)
    }

    @Test("At 100% the loupe neither magnifies nor resizes")
    func atActualSizeItIsNeutral() {
        let result = geometry(magnification: 1)

        #expect(result.contentScale == 1, "already one pixel per point")
        #expect(result.radius == 70, "and view coordinates already match screen points")
    }

    /// The case that matters: a large photo fitted to a window sits well below 100%, and that
    /// is exactly when you want the loupe.
    @Test("Zoomed out, the loupe magnifies by the inverse")
    func zoomedOutItMagnifies() {
        let result = geometry(magnification: 0.25)

        #expect(result.contentScale == 4, "a quarter-size view needs 4x to reach 1:1")
        #expect(result.radius == 280, "and 4x the view-space radius to stay 70 points on screen")
    }

    @Test("A 36 megapixel file fitted to a window magnifies a long way")
    func largePhotoFittedMagnifiesHeavily() {
        // 7360 wide shown across roughly 900 points.
        let result = geometry(magnification: 900.0 / 7360.0)

        #expect(result.contentScale > 8)
        #expect(result.contentScale < 9)
    }

    /// Past 100% the loupe shows *less* magnification than the view, which is right: it always
    /// shows one image pixel per point, whatever the view is doing.
    @Test("Zoomed in past 100%, the loupe scales down")
    func zoomedInItReduces() {
        let result = geometry(magnification: 2)

        #expect(result.contentScale == 0.5)
        #expect(result.radius == 35)
    }

    @Test("The ring stays the same thickness on screen")
    func ringWidthTracksMagnification() {
        #expect(geometry(magnification: 1).ringWidth == 2)
        #expect(geometry(magnification: 0.25).ringWidth == 8, "8 view units at quarter size is 2 on screen")
        #expect(geometry(magnification: 4).ringWidth == 0.5)
    }

    @Test("A zero magnification is treated as 1:1 rather than dividing by nothing")
    func zeroMagnificationIsSafe() {
        let result = geometry(magnification: 0)

        #expect(result.contentScale == 1)
        #expect(result.radius == 70)
        #expect(result.radius.isFinite)
    }

    @Test("A larger loupe scales its radius but not its magnification")
    func radiusIsIndependentOfScale() {
        let small = LoupeGeometry(magnification: 0.5, screenRadius: 40, targetZoom: 1)
        let large = LoupeGeometry(magnification: 0.5, screenRadius: 100, targetZoom: 1)

        #expect(small.contentScale == large.contentScale)
        #expect(large.radius == 200)
        #expect(small.radius == 80)
    }

    // MARK: - The size setting

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
    }

    @Test("Unset, the size falls back to the default")
    func unsetSizeUsesDefault() {
        #expect(LoupeSetting.diameter(from: makeDefaults()) == LoupeSetting.defaultDiameter)
    }

    @Test("A stored size is used")
    func storedSizeIsUsed() {
        let defaults = makeDefaults()
        defaults.set(220.0, forKey: LoupeSetting.diameterKey)

        #expect(LoupeSetting.diameter(from: defaults) == 220)
    }

    @Test("The size is clamped to the supported range", arguments: [
        (stored: 10.0, expected: LoupeSetting.minDiameter),
        (stored: 59.0, expected: LoupeSetting.minDiameter),
        (stored: 60.0, expected: 60.0),
        (stored: 250.0, expected: 250.0),
        (stored: 400.0, expected: 400.0),
        (stored: 5000.0, expected: LoupeSetting.maxDiameter),
        (stored: -80.0, expected: LoupeSetting.defaultDiameter),
    ])
    func sizeIsClamped(stored: Double, expected: CGFloat) {
        let defaults = makeDefaults()
        defaults.set(stored, forKey: LoupeSetting.diameterKey)

        #expect(LoupeSetting.diameter(from: defaults) == expected)
    }

    @Test("The controller reads the size from its defaults")
    @MainActor
    func controllerReadsTheSetting() {
        let defaults = makeDefaults()
        defaults.set(300.0, forKey: LoupeSetting.diameterKey)

        #expect(ZoomController(defaults: defaults).loupeDiameter == 300)
    }

    @Test("A wider loupe gives a wider circle but the same magnification")
    func sizeAffectsOnlyTheCircle() {
        let narrow = LoupeGeometry(magnification: 0.25, screenRadius: 60 / 2, targetZoom: 1)
        let wide = LoupeGeometry(magnification: 0.25, screenRadius: 400 / 2, targetZoom: 1)

        #expect(wide.radius > narrow.radius)
        #expect(wide.contentScale == narrow.contentScale, "size and magnification are independent")
    }

    @Test("Asking for 200% doubles the magnification")
    func targetZoomIsHonoured() {
        let oneToOne = LoupeGeometry(magnification: 0.25, screenRadius: 70, targetZoom: 1)
        let doubled = LoupeGeometry(magnification: 0.25, screenRadius: 70, targetZoom: 2)

        #expect(doubled.contentScale == oneToOne.contentScale * 2)
        #expect(doubled.radius == oneToOne.radius, "the circle is the same size either way")
    }
}

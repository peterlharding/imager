import AppKit
import Testing
@testable import Imager

/// Covers `ImageTransform`, which is pure pixel work and so can be checked exactly.
/// Right-angle rotations are meant to be lossless, which is what most of these assert.
@Suite("ImageTransform")
struct ImageTransformTests {

    /// A 2x2 with four distinct corners, so every orientation is distinguishable.
    ///   red   green
    ///   blue  white
    private func quadrants() -> NSImage {
        TestSupport.image(width: 2, height: 2, pixels: [.red, .green, .blue, .white])
    }

    // MARK: - Geometry

    @Test("A quarter turn swaps width and height")
    func quarterTurnSwapsDimensions() throws {
        let wide = TestSupport.solidImage(width: 4, height: 2)

        for degrees in [90.0, 270.0, -90.0] {
            let rotated = try #require(ImageTransform.rotated(wide, degreesClockwise: degrees))
            let size = TestSupport.size(rotated)
            #expect(size.width == 2, "width after \(degrees)°")
            #expect(size.height == 4, "height after \(degrees)°")
        }
    }

    @Test("A half turn keeps the dimensions")
    func halfTurnKeepsDimensions() throws {
        let wide = TestSupport.solidImage(width: 4, height: 2)
        let rotated = try #require(ImageTransform.rotated(wide, degreesClockwise: 180))
        let size = TestSupport.size(rotated)
        #expect(size.width == 4)
        #expect(size.height == 2)
    }

    @Test("Rotating by zero returns the image untouched")
    func zeroRotationIsIdentity() throws {
        let image = quadrants()
        let rotated = try #require(ImageTransform.rotated(image, degreesClockwise: 0))
        #expect(rotated === image, "a no-op rotation should not copy the image")
    }

    @Test("A fine angle grows the canvas to the rotated bounding box")
    func fineAngleGrowsCanvas() throws {
        let square = TestSupport.solidImage(width: 10, height: 10)
        let rotated = try #require(ImageTransform.rotated(square, degreesClockwise: 10))
        let size = TestSupport.size(rotated)
        #expect(size.width > 10, "canvas should grow to fit the rotated corners")
        #expect(size.height > 10)
    }

    // MARK: - Direction

    @Test("Rotating right moves the leading edge to the top")
    func rotateRightDirection() throws {
        // A horizontal strip: red on the left, green on the right.
        let strip = TestSupport.image(width: 2, height: 1, pixels: [.red, .green])
        let rotated = try #require(ImageTransform.rotated(strip, degreesClockwise: 90))

        #expect(TestSupport.size(rotated) == (width: 1, height: 2))
        #expect(TestSupport.pixel(rotated, x: 0, y: 0) == .red, "the left edge should end up on top")
        #expect(TestSupport.pixel(rotated, x: 0, y: 1) == .green)
    }

    @Test("Flipping horizontally swaps left and right")
    func flipHorizontalDirection() throws {
        let strip = TestSupport.image(width: 2, height: 1, pixels: [.red, .green])
        let flipped = try #require(ImageTransform.flipped(strip, horizontal: true))

        #expect(TestSupport.pixel(flipped, x: 0, y: 0) == .green)
        #expect(TestSupport.pixel(flipped, x: 1, y: 0) == .red)
    }

    @Test("Flipping vertically swaps top and bottom")
    func flipVerticalDirection() throws {
        let column = TestSupport.image(width: 1, height: 2, pixels: [.red, .green])
        let flipped = try #require(ImageTransform.flipped(column, horizontal: false))

        #expect(TestSupport.pixel(flipped, x: 0, y: 0) == .green)
        #expect(TestSupport.pixel(flipped, x: 0, y: 1) == .red)
    }

    // MARK: - Round trips

    @Test("Four quarter turns return the original pixels")
    func fourQuarterTurnsRoundTrip() throws {
        let original = quadrants()
        var image = original
        for _ in 0..<4 {
            image = try #require(ImageTransform.rotated(image, degreesClockwise: 90))
        }
        #expect(TestSupport.allPixels(image) == TestSupport.allPixels(original))
    }

    @Test("Flipping twice returns the original pixels", arguments: [true, false])
    func flippingTwiceRoundTrips(horizontal: Bool) throws {
        let original = quadrants()
        let once = try #require(ImageTransform.flipped(original, horizontal: horizontal))
        let twice = try #require(ImageTransform.flipped(once, horizontal: horizontal))
        #expect(TestSupport.allPixels(twice) == TestSupport.allPixels(original))
    }

    @Test("A half turn equals flipping both ways")
    func halfTurnEqualsBothFlips() throws {
        let original = quadrants()
        let rotated = try #require(ImageTransform.rotated(original, degreesClockwise: 180))
        let flippedHorizontally = try #require(ImageTransform.flipped(original, horizontal: true))
        let flippedBoth = try #require(ImageTransform.flipped(flippedHorizontally, horizontal: false))
        #expect(TestSupport.allPixels(rotated) == TestSupport.allPixels(flippedBoth))
    }

    @Test("Opposite quarter turns cancel out")
    func oppositeQuarterTurnsCancel() throws {
        let original = quadrants()
        let right = try #require(ImageTransform.rotated(original, degreesClockwise: 90))
        let back = try #require(ImageTransform.rotated(right, degreesClockwise: -90))
        #expect(TestSupport.allPixels(back) == TestSupport.allPixels(original))
    }
}

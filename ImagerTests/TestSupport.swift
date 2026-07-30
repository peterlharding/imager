import AppKit
import Foundation

/// Helpers shared by the test suites: building images with known pixels, reading
/// those pixels back, and staging real files on disk for the code paths that
/// genuinely need a URL.
enum TestSupport {

    /// An RGBA pixel, compared exactly. Transforms here are pixel-exact at right
    /// angles, so there is no tolerance to allow for.
    struct Pixel: Equatable, CustomStringConvertible {
        let r: UInt8, g: UInt8, b: UInt8, a: UInt8

        var description: String { "rgba(\(r), \(g), \(b), \(a))" }

        static let red = Pixel(r: 255, g: 0, b: 0, a: 255)
        static let green = Pixel(r: 0, g: 255, b: 0, a: 255)
        static let blue = Pixel(r: 0, g: 0, b: 255, a: 255)
        static let white = Pixel(r: 255, g: 255, b: 255, a: 255)
    }

    /// Builds an image from a row-major grid of pixels, first row at the top.
    static func image(width: Int, height: Int, pixels: [Pixel]) -> NSImage {
        precondition(pixels.count == width * height, "pixel count must match the grid")

        var bytes = [UInt8]()
        bytes.reserveCapacity(pixels.count * 4)
        for pixel in pixels {
            bytes.append(contentsOf: [pixel.r, pixel.g, pixel.b, pixel.a])
        }

        let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cg = context.makeImage()!
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    /// A solid-colour image, for cases where the pixel values don't matter.
    static func solidImage(width: Int, height: Int, colour: Pixel = .red) -> NSImage {
        image(width: width, height: height, pixels: Array(repeating: colour, count: width * height))
    }

    /// Reads a pixel back, addressed from the top-left corner so it matches the
    /// grid passed to `image(width:height:pixels:)`.
    static func pixel(_ image: NSImage, x: Int, y: Int) -> Pixel {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let width = cg.width
        let height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let offset = (y * width + x) * 4
        return Pixel(r: bytes[offset], g: bytes[offset + 1], b: bytes[offset + 2], a: bytes[offset + 3])
    }

    /// Every pixel of an image, row-major from the top-left, for whole-image comparisons.
    /// Renders once and reads the whole buffer.
    ///
    /// It previously called `pixel(_:x:y:)` per pixel, each of which re-rendered the entire
    /// image - quadratic, and invisible while every test image was a few pixels across. A
    /// 1840x1228 RAW preview took it from milliseconds to minutes.
    static func allPixels(_ image: NSImage) -> [Pixel] {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let width = cg.width
        let height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        return stride(from: 0, to: bytes.count, by: 4).map { offset in
            Pixel(r: bytes[offset], g: bytes[offset + 1], b: bytes[offset + 2], a: bytes[offset + 3])
        }
    }

    /// A cheap stand-in for comparing whole images, for cases where the images are large and
    /// only "did this change" matters.
    static func fingerprint(_ image: NSImage) -> Int {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let width = cg.width
        let height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hasher = Hasher()
        hasher.combine(width)
        hasher.combine(height)
        // Every 997th byte: prime, so it does not fall into step with the row stride.
        for offset in stride(from: 0, to: bytes.count, by: 997) {
            hasher.combine(bytes[offset])
        }
        return hasher.finalize()
    }

    static func size(_ image: NSImage) -> (width: Int, height: Int) {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        return (cg.width, cg.height)
    }

    // MARK: - Files on disk

    /// A unique empty directory under the test host's temporary directory.
    /// Delete it with `remove(_:)` when the test is finished.
    static func makeTemporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ImagerTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes an image to `directory` as a PNG and returns its URL.
    @discardableResult
    static func writePNG(_ image: NSImage, named name: String, in directory: URL) -> URL {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
        let url = directory.appendingPathComponent(name)
        try! data.write(to: url)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

import AppKit
import CoreGraphics

/// Pixel-level image transforms (rotate, flip) producing new images.
enum ImageTransform {

    /// Rotates the image by the given angle in degrees (positive = clockwise).
    /// The canvas grows to the rotated bounding box; corners exposed by non-right-angle
    /// rotations are transparent.
    static func rotated(_ image: NSImage, degreesClockwise degrees: Double) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Core Graphics rotates counter-clockwise for positive angles, so negate.
        let radians = -degrees * .pi / 180
        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)

        // Right angles map the pixel grid exactly; compute their canvas directly to avoid
        // a one-pixel transparent margin from floating-point rounding.
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let newWidth: Int
        let newHeight: Int
        switch normalized {
        case 0:
            return image
        case 90, 270:
            newWidth = cg.height; newHeight = cg.width
        case 180:
            newWidth = cg.width; newHeight = cg.height
        default:
            let box = CGRect(x: 0, y: 0, width: width, height: height)
                .applying(CGAffineTransform(rotationAngle: radians))
            newWidth = Int(ceil(abs(box.width)))
            newHeight = Int(ceil(abs(box.height)))
        }

        guard newWidth > 0, newHeight > 0, let context = context(newWidth, newHeight) else { return nil }
        context.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
        context.rotate(by: radians)
        context.draw(cg, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        return context.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    /// Mirrors the image horizontally or vertically.
    static func flipped(_ image: NSImage, horizontal: Bool) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cg.width
        let height = cg.height
        guard let context = context(width, height) else { return nil }
        if horizontal {
            context.translateBy(x: CGFloat(width), y: 0)
            context.scaleBy(x: -1, y: 1)
        } else {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    private static func context(_ width: Int, _ height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

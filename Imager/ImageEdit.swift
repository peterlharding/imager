import AppKit
import CoreGraphics

/// One reversible edit applied to an image.
///
/// Edits are recorded rather than snapshotted: undo replays the surviving edits onto
/// the image as originally loaded, so a history step costs a few numbers instead of a
/// full-size copy of the image.
enum ImageEdit: Equatable {
    case crop(CGRect)
    case rotate(degreesClockwise: Double)
    case flip(horizontal: Bool)

    /// Name for the Undo/Redo menu items, e.g. "Undo Rotate".
    var actionName: String {
        switch self {
        case .crop: "Crop"
        case .rotate: "Rotate"
        case .flip(let horizontal): horizontal ? "Flip Horizontal" : "Flip Vertical"
        }
    }

    /// Applies this edit, returning nil when it cannot be carried out.
    func apply(to image: NSImage) -> NSImage? {
        switch self {
        case .crop(let rect): Self.cropped(image, to: rect)
        case .rotate(let degrees): ImageTransform.rotated(image, degreesClockwise: degrees)
        case .flip(let horizontal): ImageTransform.flipped(image, horizontal: horizontal)
        }
    }

    /// Crops to a rectangle in image pixel coordinates, clamped to the image bounds.
    private static func cropped(_ image: NSImage, to pixelRect: CGRect) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let full = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let rect = pixelRect.integral.intersection(full)
        guard rect.width >= 1, rect.height >= 1, let cropped = cg.cropping(to: rect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }
}

extension Array where Element == ImageEdit {
    /// Replays every edit in order. A step that cannot be applied is skipped rather
    /// than abandoning the rest of the history.
    func applied(to image: NSImage) -> NSImage {
        reduce(image) { $1.apply(to: $0) ?? $0 }
    }
}

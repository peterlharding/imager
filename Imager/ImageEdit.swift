import AppKit
import CoreGraphics

/// One reversible edit applied to an image.
///
/// Edits are recorded rather than snapshotted: undo replays the surviving edits onto
/// the image as originally loaded, so a history step costs a few numbers instead of a
/// full-size copy of the image.
enum ImageEdit: Equatable, Codable {
    case crop(CGRect)
    case rotate(degreesClockwise: Double)
    case flip(horizontal: Bool)
    case adjust(Adjustments)

    /// True for a tonal or colour adjustment, as opposed to a geometry change.
    var isAdjustment: Bool {
        if case .adjust = self { return true }
        return false
    }

    /// True for a crop, which is in pixel coordinates of one particular image and so
    /// cannot be carried across to another in a recipe.
    var isCrop: Bool {
        if case .crop = self { return true }
        return false
    }

    /// Name for the Undo/Redo menu items, e.g. "Undo Rotate".
    var actionName: String {
        switch self {
        case .crop: "Crop"
        case .rotate: "Rotate"
        case .flip(let horizontal): horizontal ? "Flip Horizontal" : "Flip Vertical"
        case .adjust: "Adjust"
        }
    }

    /// Applies this edit, returning nil when it cannot be carried out.
    func apply(to image: NSImage) -> NSImage? {
        switch self {
        case .crop(let rect): Self.cropped(image, to: rect)
        case .rotate(let degrees): ImageTransform.rotated(image, degreesClockwise: degrees)
        case .flip(let horizontal): ImageTransform.flipped(image, horizontal: horizontal)
        case .adjust(let adjustments): ImageAdjuster.apply(adjustments, to: image)
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
    /// Replays the history: every geometry edit in order, then a single adjustment.
    /// A step that cannot be applied is skipped rather than abandoning the rest.
    ///
    /// Only the last adjustment is applied, because adjustment values are absolute -
    /// a later one entirely supersedes an earlier one. That keeps any number of
    /// adjustment sessions to one filter pass however long the history grows.
    ///
    /// Geometry always runs first, so the result is the adjustment applied to the
    /// final cropped and rotated image. The per-pixel filters commute with geometry
    /// anyway; fixing the order matters for the highlight and shadow pass, which is
    /// spatial and would otherwise differ near a crop edge.
    func applied(to image: NSImage) -> NSImage {
        let geometry = lazy.filter { !$0.isAdjustment }
        let transformed = geometry.reduce(image) { $1.apply(to: $0) ?? $0 }
        guard let adjustment = last(where: { $0.isAdjustment }) else { return transformed }
        return adjustment.apply(to: transformed) ?? transformed
    }
}

import AppKit
import CoreImage

/// Tonal and colour adjustments applied to an image, as absolute values.
///
/// One value holds every slider rather than one edit per slider, so a drag records a
/// single undo step. Values are absolute, which is what lets a later adjustment
/// supersede an earlier one during replay.
struct Adjustments: Equatable, Codable {
    /// Stops of exposure. 0 leaves the image alone.
    var exposure: Double = 0

    /// Highlight recovery. 1 leaves highlights alone; lower pulls them down.
    var highlights: Double = 1

    /// Shadow lift. 0 leaves shadows alone; higher opens them up.
    var shadows: Double = 0

    /// 1 leaves contrast alone.
    var contrast: Double = 1

    /// 1 leaves saturation alone; 0 is greyscale.
    var saturation: Double = 1

    /// Saturation weighted towards less saturated colours. 0 leaves the image alone.
    var vibrance: Double = 0

    /// Hue rotation in degrees. 0 leaves hue alone.
    var hue: Double = 0

    static let neutral = Adjustments()

    var isNeutral: Bool { self == .neutral }

    /// Slider ranges, chosen narrower than the filters allow so the sliders stay usable.
    /// The filters accept exposure ±10 EV and contrast up to 4, which are not useful spans
    /// to drag across.
    static let exposureRange = -3.0...3.0
    static let highlightsRange = 0.3...1.0
    static let shadowsRange = -1.0...1.0
    static let contrastRange = 0.5...2.0
    static let saturationRange = 0.0...2.0
    static let vibranceRange = -1.0...1.0
    static let hueRange = -180.0...180.0

    /// Spelled out because declaring `init(from:)` below suppresses the memberwise
    /// initialiser Swift would otherwise synthesise. The defaults are the neutral values,
    /// and `neutralValuesAreTheDefaults` in the tests guards them against drifting apart
    /// from the property defaults above.
    init(
        exposure: Double = 0,
        highlights: Double = 1,
        shadows: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        vibrance: Double = 0,
        hue: Double = 0
    ) {
        self.exposure = exposure
        self.highlights = highlights
        self.shadows = shadows
        self.contrast = contrast
        self.saturation = saturation
        self.vibrance = vibrance
        self.hue = hue
    }

    /// Decodes tolerantly, defaulting anything absent to neutral.
    ///
    /// Without this, adding a slider would make every recipe saved before it fail to
    /// load. With it, an older recipe simply has the new adjustment at neutral.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let neutral = Adjustments.neutral
        exposure = try container.decodeIfPresent(Double.self, forKey: .exposure) ?? neutral.exposure
        highlights = try container.decodeIfPresent(Double.self, forKey: .highlights) ?? neutral.highlights
        shadows = try container.decodeIfPresent(Double.self, forKey: .shadows) ?? neutral.shadows
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? neutral.contrast
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? neutral.saturation
        vibrance = try container.decodeIfPresent(Double.self, forKey: .vibrance) ?? neutral.vibrance
        hue = try container.decodeIfPresent(Double.self, forKey: .hue) ?? neutral.hue
    }
}

/// Renders `Adjustments` onto an image with Core Image.
enum ImageAdjuster {

    /// Shared because creating a `CIContext` is expensive.
    ///
    /// Works in a linear colour space: adjusting exposure on gamma-encoded sRGB gives
    /// visibly wrong midtones and bands quickly.
    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])

    /// `CIHighlightShadowAdjust`'s own default, confirmed to take effect: with a
    /// gradient, highlight 0.3 / shadow 1.0 at this radius moves 16 → 47 and 242 → 226.
    private static let highlightShadowRadius = 0.0

    /// Applies the adjustments, returning the image unchanged when there is nothing to do.
    static func apply(_ adjustments: Adjustments, to image: NSImage) -> NSImage? {
        guard !adjustments.isNeutral else { return image }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        var ciImage = CIImage(cgImage: cg)
        let extent = ciImage.extent

        if adjustments.exposure != 0 {
            ciImage = ciImage.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: adjustments.exposure,
            ])
        }

        if adjustments.highlights != 1 || adjustments.shadows != 0 {
            ciImage = ciImage.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": adjustments.highlights,
                "inputShadowAmount": adjustments.shadows,
                "inputRadius": highlightShadowRadius,
            ])
        }

        if adjustments.contrast != 1 || adjustments.saturation != 1 {
            ciImage = ciImage.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: adjustments.contrast,
                kCIInputSaturationKey: adjustments.saturation,
            ])
        }

        if adjustments.vibrance != 0 {
            ciImage = ciImage.applyingFilter("CIVibrance", parameters: [
                "inputAmount": adjustments.vibrance,
            ])
        }

        if adjustments.hue != 0 {
            ciImage = ciImage.applyingFilter("CIHueAdjust", parameters: [
                kCIInputAngleKey: adjustments.hue * .pi / 180,
            ])
        }

        // Rendered from the original extent: a filter that grows its extent must not
        // change the size of the image on screen.
        guard let output = context.createCGImage(ciImage, from: extent) else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
    }
}

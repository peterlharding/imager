import AppKit
import CoreImage
import UniformTypeIdentifiers

/// How a camera RAW file is developed from its sensor data.
///
/// Values are absolute — exposure in stops, temperature in kelvin — rather than offsets from
/// this file's defaults, so a set of settings means the same thing applied to another frame.
///
/// Unlike `Adjustments` there is no fixed neutral: a RAW file opens with whatever the decoder
/// read from the shot, which differs per file and per camera. "Neutral" is therefore
/// `RawDeveloper.defaults` for the file in hand, which is what Reset returns to.
struct RawSettings: Equatable, Codable {
    /// Stops of exposure applied during development.
    var exposure: Float = 0

    /// White balance, in kelvin.
    var temperature: Float = 5000

    /// White balance's green-magenta axis.
    var tint: Float = 0

    /// Overall rendering boost, 0 for a flat linear render, 1 for the decoder's default look.
    var boost: Float = 1

    /// How much of the boost is applied to shadows.
    var boostShadow: Float = 1

    /// Recovers detail from clipped highlights.
    ///
    /// Supported by neither every camera nor every system: the underlying property arrived in
    /// macOS 26, while Imager runs on 14 and later, so below 26 it is reported unsupported and
    /// left alone. Stored either way, so a recipe made on a newer system stays intact.
    var highlightRecovery = false

    static let exposureRange: ClosedRange<Float> = -4...4
    static let temperatureRange: ClosedRange<Float> = 2000...10000
    static let tintRange: ClosedRange<Float> = -150...150
    static let boostRange: ClosedRange<Float> = 0...1
}

/// Which RAW controls this particular file supports.
///
/// `CIRAWFilter` reports support per file because it varies by camera and decoder. Of the
/// controls exposed here only highlight recovery is gated; the others always apply.
struct RawSupport: Equatable {
    var highlightRecovery = false
}

/// Develops one RAW file, holding the decoder open.
///
/// The instance is the point. Measured on a 36 MP NEF, a fresh `CIRAWFilter` per render costs
/// 370-560 ms at full size and never better than 86 ms at any reduced scale, because that floor
/// is the decode itself. Reusing one instance costs 150 ms once and then about 7 ms per
/// parameter change at quarter scale. So one of these is held for as long as the file is open,
/// and `scaleFactor` is switched on it — which does not discard the cache.
final class RawDeveloper {

    let url: URL
    let defaults: RawSettings
    let support: RawSupport
    let nativeSize: CGSize

    private let filter: CIRAWFilter
    private let context: CIContext

    /// Scale used while a slider is being dragged. Full size is ~160 ms however warm the
    /// instance is, which is too slow to drag against; a quarter is about 7 ms.
    static let previewScale: Float = 0.25

    /// Nil when the file is not a RAW image, or the decoder cannot read it.
    init?(url: URL) {
        guard Self.isRawFile(url), let filter = CIRAWFilter(imageURL: url) else { return nil }

        self.url = url
        self.filter = filter
        self.nativeSize = filter.nativeSize
        self.context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])

        // Whatever the decoder made of the shot becomes this file's neutral.
        var recoveryEnabled = false
        var recoverySupported = false
        if #available(macOS 26.0, *) {
            recoveryEnabled = filter.isHighlightRecoveryEnabled
            recoverySupported = filter.isHighlightRecoverySupported
        }
        self.defaults = RawSettings(
            exposure: filter.exposure,
            temperature: filter.neutralTemperature,
            tint: filter.neutralTint,
            boost: filter.boostAmount,
            boostShadow: filter.boostShadowAmount,
            highlightRecovery: recoveryEnabled
        )
        self.support = RawSupport(highlightRecovery: recoverySupported)
    }

    static func isRawFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) ?? false
    }

    /// Develops the file, at a reduced scale while dragging and full size otherwise.
    func develop(_ settings: RawSettings, preview: Bool) -> NSImage? {
        filter.exposure = settings.exposure
        filter.neutralTemperature = settings.temperature
        filter.neutralTint = settings.tint
        filter.boostAmount = settings.boost
        filter.boostShadowAmount = settings.boostShadow
        if support.highlightRecovery, #available(macOS 26.0, *) {
            filter.isHighlightRecoveryEnabled = settings.highlightRecovery
        }
        filter.scaleFactor = preview ? Self.previewScale : 1

        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}

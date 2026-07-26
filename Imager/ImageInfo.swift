import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A single labeled metadata value, e.g. "Dimensions" -> "4032 × 3024 px".
struct InfoItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

/// A titled group of related metadata items, e.g. "Camera".
struct InfoSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [InfoItem]
}

/// Structured, display-ready metadata for an image file.
struct ImageInfo {
    var sections: [InfoSection]

    var isEmpty: Bool { sections.allSatisfy { $0.items.isEmpty } }
}

/// Reads image metadata from a file using ImageIO / Core Graphics.
enum ImageInfoExtractor {

    static func info(for url: URL) -> ImageInfo {
        var sections: [InfoSection] = []

        // --- File ---
        var file: [InfoItem] = [InfoItem(label: "Name", value: url.lastPathComponent)]
        if let bytes = fileSize(of: url) {
            file.append(InfoItem(label: "Size", value: byteString(bytes)))
        }

        let source = CGImageSourceCreateWithURL(url as CFURL, nil)

        if let source, let uti = CGImageSourceGetType(source) as String? {
            let type = UTType(uti)
            file.append(InfoItem(label: "Kind", value: type?.localizedDescription ?? uti))
        }
        sections.append(InfoSection(title: "File", items: file))

        guard let source,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return ImageInfo(sections: sections)
        }

        // --- Image ---
        var image: [InfoItem] = []
        if let w = int(props, kCGImagePropertyPixelWidth),
           let h = int(props, kCGImagePropertyPixelHeight) {
            image.append(InfoItem(label: "Dimensions", value: "\(w) × \(h) px"))
            let mp = Double(w * h) / 1_000_000
            image.append(InfoItem(label: "Megapixels", value: String(format: "%.1f MP", mp)))
        }
        if let model = props[kCGImagePropertyColorModel] as? String {
            image.append(InfoItem(label: "Color Model", value: model))
        }
        if let depth = int(props, kCGImagePropertyDepth) {
            image.append(InfoItem(label: "Bit Depth", value: "\(depth) bits/component"))
        }
        if let profile = props[kCGImagePropertyProfileName] as? String {
            image.append(InfoItem(label: "Color Profile", value: profile))
        }
        if let hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool {
            image.append(InfoItem(label: "Alpha", value: hasAlpha ? "Yes" : "No"))
        }
        if let dpi = num(props, kCGImagePropertyDPIWidth), dpi > 0 {
            image.append(InfoItem(label: "Resolution", value: "\(Int(dpi.rounded())) DPI"))
        }
        let frames = CGImageSourceGetCount(source)
        if frames > 1 {
            image.append(InfoItem(label: "Frames", value: "\(frames)"))
        }
        if !image.isEmpty {
            sections.append(InfoSection(title: "Image", items: image))
        }

        // --- Camera (TIFF + EXIF) ---
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        var camera: [InfoItem] = []
        if let make = tiff[kCGImagePropertyTIFFMake] as? String {
            camera.append(InfoItem(label: "Make", value: make))
        }
        if let cModel = tiff[kCGImagePropertyTIFFModel] as? String {
            camera.append(InfoItem(label: "Model", value: cModel))
        }
        if let lens = exif[kCGImagePropertyExifLensModel] as? String {
            camera.append(InfoItem(label: "Lens", value: lens))
        }
        if let focal = num(exif, kCGImagePropertyExifFocalLength) {
            camera.append(InfoItem(label: "Focal Length", value: String(format: "%g mm", focal)))
        }
        if let fnum = num(exif, kCGImagePropertyExifFNumber) {
            camera.append(InfoItem(label: "Aperture", value: String(format: "ƒ/%g", fnum)))
        }
        if let exposure = num(exif, kCGImagePropertyExifExposureTime) {
            camera.append(InfoItem(label: "Shutter", value: shutterString(exposure)))
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first {
            camera.append(InfoItem(label: "ISO", value: "ISO \(iso.intValue)"))
        }
        if let taken = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let pretty = exifDateString(taken) {
            camera.append(InfoItem(label: "Date Taken", value: pretty))
        }
        if !camera.isEmpty {
            sections.append(InfoSection(title: "Camera", items: camera))
        }

        // --- Location (GPS) ---
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = num(gps, kCGImagePropertyGPSLatitude),
           let lon = num(gps, kCGImagePropertyGPSLongitude) {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            var location = [
                InfoItem(label: "Latitude", value: String(format: "%.5f° %@", lat, latRef)),
                InfoItem(label: "Longitude", value: String(format: "%.5f° %@", lon, lonRef)),
            ]
            if let alt = num(gps, kCGImagePropertyGPSAltitude) {
                location.append(InfoItem(label: "Altitude", value: String(format: "%.0f m", alt)))
            }
            sections.append(InfoSection(title: "Location", items: location))
        }

        return ImageInfo(sections: sections)
    }

    // MARK: - Helpers

    private static func int(_ dict: [CFString: Any], _ key: CFString) -> Int? {
        (dict[key] as? NSNumber)?.intValue
    }

    private static func num(_ dict: [CFString: Any], _ key: CFString) -> Double? {
        (dict[key] as? NSNumber)?.doubleValue
    }

    private static func fileSize(of url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    private static func byteString(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func shutterString(_ seconds: Double) -> String {
        guard seconds > 0 else { return "-" }
        if seconds >= 1 { return String(format: "%gs", seconds) }
        return "1/\(Int((1 / seconds).rounded())) s"
    }

    private static let exifParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let displayDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static func exifDateString(_ raw: String) -> String? {
        guard let date = exifParser.date(from: raw) else { return nil }
        return displayDate.string(from: date)
    }
}

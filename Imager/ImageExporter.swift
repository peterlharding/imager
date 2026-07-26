import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Image file formats Imager can export to.
enum ImageFormat: CaseIterable, Identifiable {
    case png, jpeg, gif, tiff, heic

    var id: Self { self }

    var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .gif: "GIF"
        case .tiff: "TIFF"
        case .heic: "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .gif: "gif"
        case .tiff: "tiff"
        case .heic: "heic"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .gif: .gif
        case .tiff: .tiff
        case .heic: .heic
        }
    }
}

/// Saves an image to a user-chosen file via a save panel (which grants sandboxed write access).
enum ImageExporter {

    /// Presents a save panel restricted to `contentType` and writes the image.
    /// Returns an error message on failure, or nil on success or user cancel.
    static func run(image: NSImage, defaultName: String, contentType: UTType) -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultName
        panel.message = "Save a copy of the image"
        panel.prompt = "Save"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return write(image, to: url, as: contentType)
    }

    private static func write(_ image: NSImage, to url: URL, as type: UTType) -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return "Couldn't read the image data to save."
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil
        ) else {
            return "Couldn't create a \(type.localizedDescription ?? type.identifier) file."
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return "Couldn't write to \(url.lastPathComponent)."
        }
        return nil
    }
}

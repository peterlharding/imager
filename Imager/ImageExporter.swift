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

/// The outcome of presenting the save panel, distinguishing a completed write from
/// a user cancel so callers can tell whether edits have actually been persisted.
enum ExportResult {
    case saved
    case cancelled
    case failed(String)
}

/// Saves an image to a user-chosen file via a save panel (which grants sandboxed write access).
enum ImageExporter {

    /// Content types ImageIO can encode, which is far fewer than it can decode.
    /// Every camera RAW format is readable but not writable.
    static let writableTypes: Set<String> = Set(
        (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
    )

    static func canWrite(_ type: UTType) -> Bool {
        writableTypes.contains(type.identifier)
    }

    /// The format to save a copy in, given the source file's own format.
    ///
    /// Keeps the source format when it can be written, and falls back to PNG when it
    /// cannot. Without the fallback, Save As on a RAW file offers to write a format
    /// nothing can encode and fails every time.
    static func saveAsType(for sourceType: UTType?) -> UTType {
        guard let sourceType, canWrite(sourceType) else { return .png }
        return sourceType
    }

    /// Title for the Save As menu item, naming the format when it will not be the
    /// source's own. Without this the command silently writes a different format than
    /// the file it was invoked on, which is exactly the case for camera RAW.
    static func saveAsMenuTitle(for sourceType: UTType?) -> String {
        let target = saveAsType(for: sourceType)
        guard target != sourceType else { return "Save As…" }
        let name = target.preferredFilenameExtension?.uppercased() ?? "PNG"
        return "Save As \(name)…"
    }

    /// Presents a save panel restricted to `contentType` and writes the image.
    static func run(image: NSImage, defaultName: String, contentType: UTType) -> ExportResult {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultName
        panel.message = "Save a copy of the image"
        panel.prompt = "Save"

        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        if let error = write(image, to: url, as: contentType) { return .failed(error) }
        return .saved
    }

    /// Writes `image` to `url`, returning an error message on failure or nil on success.
    /// Shared with batch processing so both paths encode identically.
    static func write(_ image: NSImage, to url: URL, as type: UTType) -> String? {
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

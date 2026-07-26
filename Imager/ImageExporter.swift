import AppKit
import UniformTypeIdentifiers

/// Saves an image to a user-chosen file via a save panel (which grants sandboxed write access).
enum ImageExporter {

    /// Presents a save panel and writes the image. Returns an error message on failure,
    /// or nil on success or user cancel.
    static func run(image: NSImage, suggestedName: String) -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.message = "Save a copy of the image"
        panel.prompt = "Save"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return write(image, to: url)
    }

    private static func write(_ image: NSImage, to url: URL) -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return "Couldn't read the image data to export."
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        let fileType: NSBitmapImageRep.FileType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": fileType = .jpeg
        case "tif", "tiff": fileType = .tiff
        default: fileType = .png
        }
        guard let data = rep.representation(using: fileType, properties: [:]) else {
            return "Couldn't encode the image for export."
        }
        do {
            try data.write(to: url)
            return nil
        } catch {
            return "Couldn't write to \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

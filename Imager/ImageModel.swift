import AppKit
import Observation
import UniformTypeIdentifiers

/// Holds the currently displayed image and its source URL.
@Observable
final class ImageModel {
    var image: NSImage?
    var url: URL?
    var errorMessage: String?

    /// Loads an image from a file URL, updating the published state.
    func load(from url: URL) {
        // Access is required when the URL comes from a security-scoped source
        // (e.g. drag-and-drop or a bookmark). Harmless for open-panel URLs.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let image = NSImage(contentsOf: url) else {
            self.errorMessage = "Couldn't read an image from \(url.lastPathComponent)."
            return
        }
        self.image = image
        self.url = url
        self.errorMessage = nil
    }
}

/// Presents a standard macOS open panel filtered to image files.
enum ImageOpener {
    static func run() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose an image to open"
        panel.prompt = "Open"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

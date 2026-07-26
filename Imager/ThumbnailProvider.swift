import AppKit
import QuickLookThumbnailing

/// Generates and caches thumbnails for image files using QuickLook.
actor ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private var cache: [URL: NSImage] = [:]

    /// Returns a cached thumbnail, or generates one. Returns nil if generation fails.
    func thumbnail(for url: URL, size: CGFloat = 80, scale: CGFloat = 2) async -> NSImage? {
        if let cached = cache[url] { return cached }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )

        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = rep.nsImage
        cache[url] = image
        return image
    }
}

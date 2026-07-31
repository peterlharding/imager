import AppKit
import QuickLookThumbnailing

/// Generates and caches thumbnails for image files using QuickLook.
///
/// Generation is driven by the rows the browser actually shows: `List` realizes only visible
/// rows, so opening a folder of two thousand images generates the twenty on screen rather than
/// all of them. QuickLook reads a RAW file's embedded preview rather than developing the sensor
/// data, which is why a NEF costs about the same as a JPEG.
actor ThumbnailProvider {
    static let shared = ThumbnailProvider()

    /// How many thumbnails to keep.
    ///
    /// Bounded because the cache outlives the folder that filled it: browsing several collections
    /// in one session would otherwise accumulate every thumbnail from all of them. Comfortably
    /// more than any window shows, so scrolling back over a folder is still free.
    private let capacity: Int

    private var cache: [URL: NSImage] = [:]

    /// Insertion order, oldest first. Eviction is first-in rather than least-recently-used: the
    /// access pattern is scrolling, so the oldest entry is the one scrolled away from.
    private var order: [URL] = []

    init(capacity: Int = 512) {
        self.capacity = max(capacity, 1)
    }

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
        store(image, for: url)
        return image
    }

    private func store(_ image: NSImage, for url: URL) {
        // Two rows can await the same file at once, so a second arrival is not a new entry.
        if cache.updateValue(image, forKey: url) == nil {
            order.append(url)
        }
        while order.count > capacity {
            cache.removeValue(forKey: order.removeFirst())
        }
    }

    /// How many thumbnails are held.
    var count: Int { cache.count }

    func isCached(_ url: URL) -> Bool { cache[url] != nil }
}

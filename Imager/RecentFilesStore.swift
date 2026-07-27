import Foundation
import Observation

/// Tracks recently opened image files, persisting access across launches via
/// app-scoped security-scoped bookmarks.
@Observable
final class RecentFilesStore {

    /// One remembered file: its resolved URL (for display) and the bookmark
    /// that grants sandboxed access to it.
    struct Item: Identifiable {
        let url: URL
        let bookmark: Data
        var id: String { url.path }
        var displayName: String { url.deletingPathExtension().lastPathComponent }
    }

    private(set) var items: [Item] = []

    /// How many recent files to remember. Persisted; changing it trims the list immediately.
    var maxCount: Int {
        didSet {
            let clamped = min(max(maxCount, Self.minCount), Self.maxCountLimit)
            if clamped != maxCount { maxCount = clamped; return }
            defaults.set(maxCount, forKey: Self.maxCountKey)
            trim()
        }
    }

    static let minCount = 1
    static let maxCountLimit = 50
    static let defaultCount = 10
    private static let maxCountKey = "recents.maxCount"

    private let defaultsKey = "recentFileBookmarks"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: Self.maxCountKey)
        self.maxCount = stored == 0 ? Self.defaultCount : min(max(stored, Self.minCount), Self.maxCountLimit)
        loadFromDefaults()
        trim()
    }

    /// Drops items beyond the current limit, keeping the most recent.
    private func trim() {
        if items.count > maxCount {
            items = Array(items.prefix(maxCount))
            persist()
        }
    }

    /// Records a freshly opened file at the top of the list. Must be called
    /// while the app holds access to `url` (e.g. during an open or a resolved
    /// security-scoped access window) so the bookmark can be created.
    func record(_ url: URL) {
        guard let bookmark = makeBookmark(for: url) else { return }
        var updated = items.filter { $0.url != url }
        updated.insert(Item(url: url, bookmark: bookmark), at: 0)
        if updated.count > maxCount {
            updated = Array(updated.prefix(maxCount))
        }
        items = updated
        persist()
    }

    /// Resolves an item's bookmark to a security-scoped URL, refreshing a stale
    /// bookmark and dropping the item if the file can no longer be found.
    /// The caller must balance `startAccessingSecurityScopedResource()` with a
    /// matching `stopAccessingSecurityScopedResource()`.
    func resolve(_ item: Item) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: item.bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            remove(item)
            return nil
        }
        if isStale, let refreshed = makeBookmark(for: url) {
            replace(item, with: Item(url: url, bookmark: refreshed))
        }
        return url
    }

    func clear() {
        items = []
        persist()
    }

    // MARK: - Mutation helpers

    private func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func replace(_ old: Item, with new: Item) {
        guard let index = items.firstIndex(where: { $0.id == old.id }) else { return }
        items[index] = new
        persist()
    }

    // MARK: - Bookmarks & persistence

    private func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func persist() {
        defaults.set(items.map(\.bookmark), forKey: defaultsKey)
    }

    private func loadFromDefaults() {
        guard let stored = defaults.array(forKey: defaultsKey) as? [Data] else { return }
        items = stored.compactMap { bookmark in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return nil
            }
            return Item(url: url, bookmark: bookmark)
        }
    }
}

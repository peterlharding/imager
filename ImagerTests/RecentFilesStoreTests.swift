import Foundation
import Testing
@testable import Imager

/// Covers the recent-files limit, which is user-facing through Settings ▸ General
/// and is the part of the store that works without security-scoped bookmarks.
@Suite("RecentFilesStore")
struct RecentFilesStoreTests {

    /// A store backed by a throwaway defaults suite, so nothing here touches the
    /// user's real recent-files list.
    private func makeStore() -> (store: RecentFilesStore, suiteName: String) {
        let suiteName = "ImagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (RecentFilesStore(defaults: defaults), suiteName)
    }

    private func removeSuite(_ name: String) {
        UserDefaults.standard.removePersistentDomain(forName: name)
    }

    @Test("A new store starts at the default limit")
    func defaultLimit() {
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }

        #expect(store.maxCount == RecentFilesStore.defaultCount)
        #expect(store.items.isEmpty)
    }

    @Test("The limit is clamped to the supported range", arguments: [
        (requested: 0, expected: RecentFilesStore.minCount),
        (requested: -5, expected: RecentFilesStore.minCount),
        (requested: 1, expected: 1),
        (requested: 25, expected: 25),
        (requested: 50, expected: 50),
        (requested: 51, expected: RecentFilesStore.maxCountLimit),
        (requested: 9_000, expected: RecentFilesStore.maxCountLimit),
    ])
    func limitIsClamped(requested: Int, expected: Int) {
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }

        store.maxCount = requested

        #expect(store.maxCount == expected)
    }

    @Test("The chosen limit survives a new store on the same defaults")
    func limitPersists() {
        let suiteName = "ImagerTests-\(UUID().uuidString)"
        defer { removeSuite(suiteName) }
        let defaults = UserDefaults(suiteName: suiteName)!

        RecentFilesStore(defaults: defaults).maxCount = 3

        #expect(RecentFilesStore(defaults: defaults).maxCount == 3)
    }

    @Test("An out-of-range stored value is brought back into range on load")
    func storedLimitIsClampedOnLoad() {
        let suiteName = "ImagerTests-\(UUID().uuidString)"
        defer { removeSuite(suiteName) }
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(9_000, forKey: "recents.maxCount")

        #expect(RecentFilesStore(defaults: defaults).maxCount == RecentFilesStore.maxCountLimit)
    }

    @Test("Clearing empties the list")
    func clearEmptiesTheList() {
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }

        store.clear()

        #expect(store.items.isEmpty)
    }
}

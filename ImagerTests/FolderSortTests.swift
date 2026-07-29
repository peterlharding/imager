import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers the order images appear in when browsing a folder, and that changing the
/// order re-sorts in place without losing the image on screen.
@Suite("Folder sort order", .serialized)
@MainActor
struct FolderSortTests {

    /// Writes three images chosen so name, size, and date orders all differ:
    ///
    /// | file        | name order | size       | modified |
    /// |-------------|-----------:|-----------:|---------:|
    /// | `photo2`    |          1 | largest    | oldest   |
    /// | `photo10`   |          2 | middle     | newest   |
    /// | `photo30`   |          3 | smallest   | middle   |
    ///
    /// `photo2` before `photo10` also checks the name sort is natural rather than
    /// lexicographic, which would put `photo10` first.
    private func makeFolder() -> URL {
        let directory = TestSupport.makeTemporaryDirectory()

        let files: [(name: String, side: Int, modified: Date)] = [
            ("photo2.png", 160, Date(timeIntervalSince1970: 1_000)),
            ("photo10.png", 80, Date(timeIntervalSince1970: 9_000)),
            ("photo30.png", 8, Date(timeIntervalSince1970: 5_000)),
        ]

        for file in files {
            // A noisy image so PNG compression can't collapse the size differences.
            let count: Int = file.side * file.side
            var pixels: [TestSupport.Pixel] = []
            pixels.reserveCapacity(count)
            for index in 0..<count {
                let r: UInt8 = UInt8(index % 251)
                let g: UInt8 = UInt8((index &* 7) % 251)
                let b: UInt8 = UInt8((index &* 13) % 251)
                pixels.append(TestSupport.Pixel(r: r, g: g, b: b, a: 255))
            }
            let image = TestSupport.image(width: file.side, height: file.side, pixels: pixels)
            let url = TestSupport.writePNG(image, named: file.name, in: directory)
            try? FileManager.default.setAttributes([.modificationDate: file.modified], ofItemAtPath: url.path)
        }

        return directory
    }

    private func names(_ urls: [URL]) -> [String] {
        urls.map(\.lastPathComponent)
    }

    private func makeModel(defaults: UserDefaults) -> ImageModel {
        ImageModel(recents: RecentFilesStore(defaults: defaults), defaults: defaults)
    }

    // MARK: - Ordering

    @Test("Name order is natural, not lexicographic")
    func nameOrderIsNatural() {
        let directory = makeFolder()
        defer { TestSupport.remove(directory) }

        let urls = ImageModel.imageURLs(in: directory, order: .name)

        #expect(names(urls) == ["photo2.png", "photo10.png", "photo30.png"])
    }

    @Test("Date order runs oldest first")
    func dateOrder() {
        let directory = makeFolder()
        defer { TestSupport.remove(directory) }

        let urls = ImageModel.imageURLs(in: directory, order: .dateModified)

        #expect(names(urls) == ["photo2.png", "photo30.png", "photo10.png"])
    }

    @Test("Size order runs smallest first")
    func sizeOrder() {
        let directory = makeFolder()
        defer { TestSupport.remove(directory) }

        let urls = ImageModel.imageURLs(in: directory, order: .size)

        #expect(names(urls) == ["photo30.png", "photo10.png", "photo2.png"])
    }

    @Test("Reversing flips the order", arguments: FolderSortOrder.allCases)
    func reversingFlipsTheOrder(order: FolderSortOrder) {
        let directory = makeFolder()
        defer { TestSupport.remove(directory) }

        let forward = ImageModel.imageURLs(in: directory, order: order)
        let backward = ImageModel.imageURLs(in: directory, order: order, reversed: true)

        #expect(backward == forward.reversed())
    }

    // MARK: - Applying it to a browsed folder

    @Test("Opening a folder uses the chosen order")
    func openFolderHonoursTheOrder() {
        let directory = makeFolder()
        defer { TestSupport.remove(directory) }
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!

        let model = makeModel(defaults: suite)
        model.sortOrder = .size
        model.openFolder(directory)

        #expect(names(model.folderImages) == ["photo30.png", "photo10.png", "photo2.png"])
    }

    /// Re-sorting is a presentation change, so it must not move the user off the
    /// image they were looking at, and must not raise the discard confirmation.
    @Test("Changing the order keeps the image on screen selected")
    func resortingKeepsTheCurrentImage() {
        let directory = makeFolder()
        defer { TestSupport.remove(directory) }
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!

        let model = makeModel(defaults: suite)
        model.openFolder(directory)
        model.select(2)
        let showing = model.url

        #expect(showing?.lastPathComponent == "photo30.png")

        model.sortOrder = .size

        #expect(model.selectionIndex == 0, "photo30 is smallest, so it moves to the front")
        #expect(model.url == showing, "and it is still the image being displayed")
        #expect(model.pendingDiscard == nil)
    }

    @Test("Reversing also keeps the image on screen selected")
    func reversingKeepsTheCurrentImage() {
        let directory = makeFolder()
        defer { TestSupport.remove(directory) }
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!

        let model = makeModel(defaults: suite)
        model.openFolder(directory)
        let showing = model.url

        model.sortReversed = true

        #expect(model.selectionIndex == 2)
        #expect(model.url == showing)
    }

    @Test("An unsaved edit survives a re-sort")
    func resortingDoesNotDisturbEdits() {
        let directory = makeFolder()
        defer { TestSupport.remove(directory) }
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!

        let model = makeModel(defaults: suite)
        model.openFolder(directory)
        model.rotate(byDegreesClockwise: 90)

        model.sortOrder = .dateModified

        #expect(model.hasUnsavedEdits, "re-ordering must not discard the edit")
        #expect(model.pendingDiscard == nil, "nor prompt about it")
        #expect(model.canUndo)
    }

    // MARK: - Persistence

    @Test("The chosen order is remembered")
    func orderPersists() {
        let suiteName = "ImagerTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let suite = UserDefaults(suiteName: suiteName)!

        makeModel(defaults: suite).sortOrder = .dateModified
        makeModel(defaults: suite).sortReversed = true

        let restored = makeModel(defaults: suite)
        #expect(restored.sortOrder == .dateModified)
        #expect(restored.sortReversed)
    }

    @Test("A new model defaults to name order, not reversed")
    func defaultsToName() {
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = makeModel(defaults: suite)

        #expect(model.sortOrder == FolderSortOrder.defaultOrder)
        #expect(model.sortOrder == .name)
        #expect(model.sortReversed == false)
    }
}

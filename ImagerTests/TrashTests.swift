import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers Move to Trash: what it removes, what it shows next, and what it refuses.
///
/// The trash operation is injected, so these tests delete their temporary files
/// outright rather than filling the real Trash on every run.
@Suite("Move to Trash", .serialized)
@MainActor
struct TrashTests {

    /// Records what was asked to be trashed, and removes it so the folder listing
    /// genuinely changes.
    private final class Recorder {
        private(set) var trashed: [URL] = []
        var failure: Error?

        func trash(_ url: URL) throws {
            if let failure { throw failure }
            trashed.append(url)
            try FileManager.default.removeItem(at: url)
        }

        var names: [String] { trashed.map(\.lastPathComponent) }
    }

    private struct Fixture {
        let model: ImageModel
        let recorder: Recorder
        let directory: URL
    }

    private func makeFixture(imageCount: Int) -> Fixture {
        let directory = TestSupport.makeTemporaryDirectory()
        for index in 1...max(imageCount, 1) {
            TestSupport.writePNG(
                TestSupport.solidImage(width: 4, height: 4),
                named: "image\(index).png",
                in: directory
            )
        }

        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let recorder = Recorder()
        let model = ImageModel(
            recents: RecentFilesStore(defaults: suite),
            defaults: suite,
            trashItem: { [recorder] url in try recorder.trash(url) }
        )
        return Fixture(model: model, recorder: recorder, directory: directory)
    }

    private func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

    // MARK: - What it refuses

    @Test("With nothing open there is nothing to trash")
    func nothingOpen() {
        let fixture = makeFixture(imageCount: 1)
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.model.canMoveToTrash == false)

        fixture.model.moveToTrash()
        #expect(fixture.recorder.trashed.isEmpty)
    }

    @Test("A pasted image has no file to trash")
    func pastedImageCannotBeTrashed() {
        let fixture = makeFixture(imageCount: 1)
        defer { TestSupport.remove(fixture.directory) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ImagerTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([TestSupport.solidImage(width: 4, height: 4)])

        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(recents: RecentFilesStore(defaults: suite), defaults: suite, pasteboard: pasteboard)
        model.paste()

        #expect(model.image != nil)
        #expect(model.canMoveToTrash == false)
    }

    // MARK: - Browsing a folder

    @Test("Trashing while browsing removes it and shows the next image")
    func trashingShowsTheNextImage() {
        let fixture = makeFixture(imageCount: 3)
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.openFolder(fixture.directory)

        #expect(names(fixture.model.folderImages) == ["image1.png", "image2.png", "image3.png"])

        fixture.model.moveToTrash()

        #expect(fixture.recorder.names == ["image1.png"])
        #expect(names(fixture.model.folderImages) == ["image2.png", "image3.png"])
        #expect(fixture.model.url?.lastPathComponent == "image2.png", "the next image took its place")
        #expect(fixture.model.selectionIndex == 0)
    }

    @Test("Trashing the last image falls back to the one before it")
    func trashingLastImageStepsBack() {
        let fixture = makeFixture(imageCount: 3)
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.openFolder(fixture.directory)
        fixture.model.select(2)

        fixture.model.moveToTrash()

        #expect(fixture.recorder.names == ["image3.png"])
        #expect(fixture.model.url?.lastPathComponent == "image2.png")
        #expect(fixture.model.selectionIndex == 1)
    }

    @Test("Trashing them all ends at the empty state")
    func trashingEverythingEmpties() {
        let fixture = makeFixture(imageCount: 2)
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.openFolder(fixture.directory)

        fixture.model.moveToTrash()
        fixture.model.moveToTrash()

        #expect(fixture.recorder.trashed.count == 2)
        #expect(fixture.model.image == nil)
        #expect(fixture.model.url == nil)
        #expect(fixture.model.folderImages.isEmpty)
    }

    @Test("Trashing a single open file ends at the empty state")
    func trashingSingleFileEmpties() {
        let fixture = makeFixture(imageCount: 1)
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.load(from: fixture.directory.appendingPathComponent("image1.png"))

        fixture.model.moveToTrash()

        #expect(fixture.recorder.names == ["image1.png"])
        #expect(fixture.model.image == nil)
    }

    // MARK: - Edits and failures

    /// Trashing the file means the edits to it are moot, so it must not stop to ask.
    @Test("An unsaved edit does not block trashing")
    func unsavedEditDoesNotBlockTrashing() {
        let fixture = makeFixture(imageCount: 2)
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.openFolder(fixture.directory)
        fixture.model.rotate(byDegreesClockwise: 90)
        #expect(fixture.model.hasUnsavedEdits)

        fixture.model.moveToTrash()

        #expect(fixture.recorder.names == ["image1.png"], "trashed without asking")
        #expect(fixture.model.pendingDiscard == nil)
        #expect(fixture.model.hasUnsavedEdits == false, "the new image starts clean")
    }

    @Test("A failure is reported and changes nothing")
    func failureIsReported() {
        let fixture = makeFixture(imageCount: 2)
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.openFolder(fixture.directory)
        fixture.recorder.failure = CocoaError(.fileWriteNoPermission)

        fixture.model.moveToTrash()

        #expect(fixture.model.errorMessage != nil)
        #expect(fixture.model.folderImages.count == 2, "the listing is untouched")
        #expect(fixture.model.url?.lastPathComponent == "image1.png", "still showing it")
    }
}

import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers the multi-step edit history: undo, redo, how it interacts with saving,
/// and that replaying the log reproduces the image exactly.
@Suite("Undo and redo", .serialized)
@MainActor
struct UndoRedoTests {

    private struct Fixture {
        let model: ImageModel
        let directory: URL
        let imageURL: URL
    }

    /// A model showing a 2x2 image with four distinct corners, so any transform is visible.
    ///   red   green
    ///   blue  white
    private func makeFixture() -> Fixture {
        let directory = TestSupport.makeTemporaryDirectory()
        let image = TestSupport.image(width: 2, height: 2, pixels: [.red, .green, .blue, .white])
        let url = TestSupport.writePNG(image, named: "quadrants.png", in: directory)

        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(recents: RecentFilesStore(defaults: suite), defaults: suite)
        model.load(from: url)

        return Fixture(model: model, directory: directory, imageURL: url)
    }

    // MARK: - Basics

    @Test("A freshly loaded image has nothing to undo or redo")
    func freshLoadHasNoHistory() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.model.canUndo == false)
        #expect(fixture.model.canRedo == false)
        #expect(fixture.model.edits.isEmpty)
    }

    @Test("Undoing with nothing to undo does nothing")
    func undoWithEmptyHistoryIsIgnored() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        let before = TestSupport.allPixels(fixture.model.image!)

        fixture.model.undo()

        #expect(TestSupport.allPixels(fixture.model.image!) == before)
        #expect(fixture.model.canRedo == false, "a no-op undo must not create redo history")
    }

    @Test("An edit can be undone, restoring the original pixels")
    func undoRestoresPixels() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        let original = TestSupport.allPixels(fixture.model.image!)

        fixture.model.rotate(byDegreesClockwise: 90)
        #expect(TestSupport.allPixels(fixture.model.image!) != original)
        #expect(fixture.model.canUndo)

        fixture.model.undo()

        #expect(TestSupport.allPixels(fixture.model.image!) == original)
        #expect(fixture.model.canUndo == false)
        #expect(fixture.model.canRedo)
    }

    @Test("An undone edit can be redone")
    func redoReappliesTheEdit() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        let rotated = TestSupport.allPixels(fixture.model.image!)

        fixture.model.undo()
        fixture.model.redo()

        #expect(TestSupport.allPixels(fixture.model.image!) == rotated)
        #expect(fixture.model.canRedo == false)
        #expect(fixture.model.canUndo)
    }

    // MARK: - Multiple steps

    /// The point of the feature: stepping back one edit at a time rather than
    /// only being able to discard everything with Revert.
    @Test("A stack of edits unwinds one step at a time")
    func multipleEditsUnwindIndividually() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        let original = TestSupport.allPixels(fixture.model.image!)

        fixture.model.rotate(byDegreesClockwise: 90)
        let afterRotate = TestSupport.allPixels(fixture.model.image!)
        fixture.model.flip(horizontal: true)
        let afterFlip = TestSupport.allPixels(fixture.model.image!)
        fixture.model.crop(to: CGRect(x: 0, y: 0, width: 1, height: 2))

        #expect(fixture.model.edits.count == 3)

        fixture.model.undo()
        #expect(TestSupport.allPixels(fixture.model.image!) == afterFlip, "back to the flip")

        fixture.model.undo()
        #expect(TestSupport.allPixels(fixture.model.image!) == afterRotate, "back to the rotate")

        fixture.model.undo()
        #expect(TestSupport.allPixels(fixture.model.image!) == original, "back to the original")
        #expect(fixture.model.canUndo == false)
    }

    @Test("Redoing walks the same path forwards")
    func redoWalksForwardAgain() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.flip(horizontal: true)
        let final = TestSupport.allPixels(fixture.model.image!)

        fixture.model.undo()
        fixture.model.undo()
        fixture.model.redo()
        fixture.model.redo()

        #expect(TestSupport.allPixels(fixture.model.image!) == final)
        #expect(fixture.model.edits.count == 2)
    }

    @Test("A new edit discards the redo history")
    func newEditClearsRedo() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.undo()
        #expect(fixture.model.canRedo)

        fixture.model.flip(horizontal: true)

        #expect(fixture.model.canRedo == false, "the abandoned branch must not be redoable")
        #expect(fixture.model.edits.count == 1)
    }

    @Test("Reverting discards the whole history")
    func revertClearsBothStacks() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        let original = TestSupport.allPixels(fixture.model.image!)

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.flip(horizontal: true)
        fixture.model.revert()

        #expect(fixture.model.canUndo == false)
        #expect(fixture.model.canRedo == false)
        #expect(fixture.model.hasUnsavedEdits == false)
        #expect(TestSupport.allPixels(fixture.model.image!) == original)
    }

    // MARK: - Menu titles

    @Test("The history names the action for the menu")
    func actionNamesFollowTheHistory() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.model.undoActionName == nil)

        fixture.model.rotate(byDegreesClockwise: 90)
        #expect(fixture.model.undoActionName == "Rotate")

        fixture.model.flip(horizontal: false)
        #expect(fixture.model.undoActionName == "Flip Vertical")

        fixture.model.undo()
        #expect(fixture.model.undoActionName == "Rotate")
        #expect(fixture.model.redoActionName == "Flip Vertical")
    }

    // MARK: - Interaction with saving

    /// The reason the unsaved flag is derived from the history rather than latched:
    /// undoing back to what was saved genuinely leaves nothing to save.
    @Test("Undoing back to the saved state clears the unsaved flag")
    func undoingToSavedStateClearsUnsaved() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.markEditsSaved()
        #expect(fixture.model.hasUnsavedEdits == false)

        fixture.model.flip(horizontal: true)
        #expect(fixture.model.hasUnsavedEdits, "a new edit is unsaved")

        fixture.model.undo()
        #expect(fixture.model.hasUnsavedEdits == false, "back at what was written out")
    }

    @Test("Redoing away from the saved state marks it unsaved again")
    func redoingAwayFromSavedStateSetsUnsaved() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.markEditsSaved()
        fixture.model.flip(horizontal: true)
        fixture.model.undo()
        #expect(fixture.model.hasUnsavedEdits == false)

        fixture.model.redo()

        #expect(fixture.model.hasUnsavedEdits)
    }

    @Test("Undoing back to an unedited image leaves nothing to revert")
    func undoingToOriginalClearsRevert() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        #expect(fixture.model.canRevert)

        fixture.model.undo()

        #expect(fixture.model.canRevert == false)
        #expect(fixture.model.hasUnsavedEdits == false)
    }

    @Test("Loading another image starts with a clean history")
    func loadingClearsHistory() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.markEditsSaved()
        fixture.model.load(from: fixture.imageURL)

        #expect(fixture.model.canUndo == false)
        #expect(fixture.model.canRedo == false)
        #expect(fixture.model.hasUnsavedEdits == false)
    }
}

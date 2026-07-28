import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers the unsaved-edit state machine added in 0.11.0: what counts as an unsaved
/// edit, what clears it, and which actions are held back behind a confirmation.
///
/// Serialized and main-actor bound because the model drives AppKit types.
@Suite("ImageModel edit state", .serialized)
@MainActor
struct ImageModelEditStateTests {

    /// A model with a real image loaded from a real file, plus the directory to clean up.
    /// Recents are pointed at a throwaway defaults suite so tests never touch the
    /// user's actual recent-files list.
    private struct Fixture {
        let model: ImageModel
        let directory: URL
        let imageURL: URL
    }

    private func makeFixture(imageCount: Int = 1) -> Fixture {
        let directory = TestSupport.makeTemporaryDirectory()
        var urls: [URL] = []
        for index in 0..<imageCount {
            let image = TestSupport.solidImage(width: 4, height: 4)
            urls.append(TestSupport.writePNG(image, named: "image\(index).png", in: directory))
        }

        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(recents: RecentFilesStore(defaults: suite))
        model.load(from: urls[0])

        return Fixture(model: model, directory: directory, imageURL: urls[0])
    }

    // MARK: - What marks edits unsaved

    @Test("A freshly loaded image has nothing to save and nothing to revert")
    func freshLoadIsClean() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.model.image != nil)
        #expect(fixture.model.url == fixture.imageURL)
        #expect(fixture.model.hasUnsavedEdits == false)
        #expect(fixture.model.canRevert == false)
    }

    @Test("Rotating marks the image as unsaved")
    func rotatingMarksUnsaved() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)

        #expect(fixture.model.hasUnsavedEdits)
        #expect(fixture.model.canRevert)
    }

    @Test("Flipping marks the image as unsaved")
    func flippingMarksUnsaved() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.flip(horizontal: true)

        #expect(fixture.model.hasUnsavedEdits)
    }

    @Test("Cropping marks the image as unsaved")
    func croppingMarksUnsaved() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.crop(to: CGRect(x: 0, y: 0, width: 2, height: 2))

        #expect(fixture.model.hasUnsavedEdits)
        #expect(TestSupport.size(fixture.model.image!) == (width: 2, height: 2))
    }

    // MARK: - What clears them

    @Test("Reverting clears both the unsaved flag and the ability to revert")
    func revertingClearsEverything() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.revert()

        #expect(fixture.model.hasUnsavedEdits == false)
        #expect(fixture.model.canRevert == false)
    }

    /// The distinction the 0.11.0 comment calls out: saving a copy settles the
    /// "you'll lose work" question without undoing the edit itself.
    @Test("Saving a copy clears the unsaved flag but leaves the edit revertable")
    func savingClearsUnsavedButKeepsRevert() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.markEditsSaved()

        #expect(fixture.model.hasUnsavedEdits == false)
        #expect(fixture.model.canRevert, "the image still differs from the original")
    }

    @Test("Saving again when nothing is pending is harmless")
    func savingWhenCleanIsNoOp() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.markEditsSaved()

        #expect(fixture.model.hasUnsavedEdits == false)
    }

    // MARK: - The confirmation gate

    @Test("Closing a clean image happens immediately, with no prompt")
    func closingCleanImageDoesNotPrompt() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.close()

        #expect(fixture.model.pendingDiscard == nil)
        #expect(fixture.model.image == nil)
    }

    @Test("Closing with unsaved edits asks before doing anything")
    func closingWithEditsPrompts() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.close()

        #expect(fixture.model.pendingDiscard != nil, "a confirmation should be showing")
        #expect(fixture.model.image != nil, "the close must not have happened yet")
        #expect(fixture.model.pendingDiscard?.fileName == fixture.imageURL.lastPathComponent)
    }

    @Test("Cancelling the prompt leaves the image and the edits alone")
    func cancellingKeepsEverything() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.close()
        fixture.model.resolveDiscard(confirmed: false)

        #expect(fixture.model.pendingDiscard == nil)
        #expect(fixture.model.image != nil)
        #expect(fixture.model.hasUnsavedEdits, "cancelling must not quietly mark them saved")
    }

    @Test("Confirming the prompt carries out the close")
    func confirmingPerformsTheClose() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.close()
        fixture.model.resolveDiscard(confirmed: true)

        #expect(fixture.model.pendingDiscard == nil)
        #expect(fixture.model.image == nil)
        #expect(fixture.model.hasUnsavedEdits == false)
    }

    @Test("Opening another file with unsaved edits asks first")
    func openingAnotherFilePrompts() {
        let fixture = makeFixture(imageCount: 2)
        defer { TestSupport.remove(fixture.directory) }

        let other = fixture.directory.appendingPathComponent("image1.png")
        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.load(from: other)

        #expect(fixture.model.pendingDiscard != nil)
        #expect(fixture.model.url == fixture.imageURL, "still showing the first image")

        fixture.model.resolveDiscard(confirmed: true)
        #expect(fixture.model.url == other, "the open runs once confirmed")
        #expect(fixture.model.hasUnsavedEdits == false, "the new image starts clean")
    }

    @Test("Saving a copy first means the next open goes through unchallenged")
    func savingThenOpeningDoesNotPrompt() {
        let fixture = makeFixture(imageCount: 2)
        defer { TestSupport.remove(fixture.directory) }

        let other = fixture.directory.appendingPathComponent("image1.png")
        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.markEditsSaved()
        fixture.model.load(from: other)

        #expect(fixture.model.pendingDiscard == nil)
        #expect(fixture.model.url == other)
    }

    @Test("A quit confirmation will not stack on top of one already showing")
    func quitDoesNotStackPrompts() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.close()
        #expect(fixture.model.pendingDiscard != nil)

        #expect(fixture.model.requestQuitConfirmation() == false, "quit is refused rather than stacked")

        // Clear the prompt directly: resolving it would call back into NSApp's
        // terminate reply, which has no pending terminate request in a test run.
        fixture.model.pendingDiscard = nil
    }

    // MARK: - Folder navigation

    @Test("Moving to the next image in a folder is gated by the same confirmation")
    func folderNavigationPrompts() {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        for index in 0..<2 {
            TestSupport.writePNG(TestSupport.solidImage(width: 4, height: 4), named: "image\(index).png", in: directory)
        }

        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(recents: RecentFilesStore(defaults: suite))
        model.openFolder(directory)

        #expect(model.folderImages.count == 2)
        #expect(model.canBrowse)
        #expect(model.selectionIndex == 0)

        model.rotate(byDegreesClockwise: 90)
        model.showNext()

        #expect(model.pendingDiscard != nil)
        #expect(model.selectionIndex == 0, "navigation waits for the answer")

        model.resolveDiscard(confirmed: true)
        #expect(model.selectionIndex == 1)
    }

    @Test("Selecting the image already showing does nothing at all")
    func reselectingCurrentImageIsIgnored() {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        for index in 0..<2 {
            TestSupport.writePNG(TestSupport.solidImage(width: 4, height: 4), named: "image\(index).png", in: directory)
        }

        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(recents: RecentFilesStore(defaults: suite))
        model.openFolder(directory)
        model.rotate(byDegreesClockwise: 90)

        model.select(0)

        #expect(model.pendingDiscard == nil, "reselecting the current image should not prompt")
        #expect(model.hasUnsavedEdits, "and should not discard the edit")
    }
}

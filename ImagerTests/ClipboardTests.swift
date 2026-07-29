import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers copying the current image to the clipboard and pasting one in.
///
/// Every test uses its own named pasteboard, so a run never touches the real
/// clipboard the user is working with.
@Suite("Clipboard", .serialized)
@MainActor
struct ClipboardTests {

    private struct Fixture {
        let model: ImageModel
        let pasteboard: NSPasteboard
        let directory: URL
        let imageURL: URL
    }

    private func makeFixture() -> Fixture {
        let directory = TestSupport.makeTemporaryDirectory()
        let url = TestSupport.writePNG(
            TestSupport.image(width: 2, height: 2, pixels: [.red, .green, .blue, .white]),
            named: "source.png",
            in: directory
        )

        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ImagerTests-\(UUID().uuidString)"))
        let model = ImageModel(recents: RecentFilesStore(defaults: suite), defaults: suite, pasteboard: pasteboard)

        return Fixture(model: model, pasteboard: pasteboard, directory: directory, imageURL: url)
    }

    private func putImageOnPasteboard(_ pasteboard: NSPasteboard, width: Int = 8, height: Int = 4) {
        pasteboard.clearContents()
        pasteboard.writeObjects([TestSupport.solidImage(width: width, height: height)])
    }

    // MARK: - Copy

    @Test("Copying with no image open does nothing")
    func copyWithNoImage() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.model.copyToPasteboard() == false)
        #expect(fixture.model.canPaste == false)
    }

    @Test("Copying puts the current image on the pasteboard")
    func copyPutsImageOnPasteboard() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.load(from: fixture.imageURL)

        #expect(fixture.model.copyToPasteboard())
        #expect(fixture.model.canPaste)
    }

    /// Copy takes what is on screen, not the file, so edits come along.
    @Test("Copying an edited image copies the edit")
    func copyIncludesEdits() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.load(from: fixture.imageURL)
        fixture.model.crop(to: CGRect(x: 0, y: 0, width: 1, height: 2))

        #expect(fixture.model.copyToPasteboard())

        let copied = fixture.pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
        let size = TestSupport.size(try! #require(copied))
        #expect(size == (width: 1, height: 2), "the cropped image was copied, not the original")
    }

    // MARK: - Paste

    @Test("Pasting shows the image from the clipboard")
    func pasteShowsTheImage() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        putImageOnPasteboard(fixture.pasteboard)

        fixture.model.paste()

        #expect(fixture.model.image != nil)
        #expect(TestSupport.size(fixture.model.image!) == (width: 8, height: 4))
        #expect(fixture.model.url == nil, "a pasted image has no file behind it")
        #expect(fixture.model.errorMessage == nil)
    }

    /// Nothing on disk corresponds to a pasted image, so it must count as unsaved
    /// straight away or closing would throw it away without asking.
    @Test("A pasted image counts as unsaved immediately")
    func pastedImageIsUnsaved() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        putImageOnPasteboard(fixture.pasteboard)

        fixture.model.paste()

        #expect(fixture.model.hasUnsavedEdits)
        #expect(fixture.model.canUndo == false, "but with no edit history of its own")
    }

    @Test("Closing a pasted image asks first")
    func closingPastedImagePrompts() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        putImageOnPasteboard(fixture.pasteboard)
        fixture.model.paste()

        fixture.model.close()

        #expect(fixture.model.pendingDiscard != nil)
        #expect(fixture.model.image != nil, "still on screen until answered")
    }

    @Test("Exporting a pasted image settles it")
    func exportingPastedImageClearsUnsaved() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        putImageOnPasteboard(fixture.pasteboard)
        fixture.model.paste()

        fixture.model.markEditsSaved()

        #expect(fixture.model.hasUnsavedEdits == false)
    }

    @Test("Reverting a pasted image leaves it unsaved")
    func revertingPastedImageStaysUnsaved() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        putImageOnPasteboard(fixture.pasteboard)
        fixture.model.paste()
        fixture.model.rotate(byDegreesClockwise: 90)

        fixture.model.revert()

        #expect(fixture.model.hasUnsavedEdits, "there is still no file holding this image")
    }

    @Test("Pasting with nothing on the clipboard reports it and changes nothing")
    func pasteWithEmptyClipboard() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.load(from: fixture.imageURL)
        let before = fixture.model.url
        fixture.pasteboard.clearContents()

        fixture.model.paste()

        #expect(fixture.model.errorMessage != nil)
        #expect(fixture.model.url == before, "the open image is untouched")
    }

    @Test("Pasting over unsaved edits asks first")
    func pasteOverUnsavedEditsPrompts() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.load(from: fixture.imageURL)
        fixture.model.rotate(byDegreesClockwise: 90)
        putImageOnPasteboard(fixture.pasteboard)

        fixture.model.paste()

        #expect(fixture.model.pendingDiscard != nil)
        #expect(fixture.model.url == fixture.imageURL, "the paste has not happened yet")

        fixture.model.resolveDiscard(confirmed: true)

        #expect(fixture.model.url == nil, "the paste runs once confirmed")
        #expect(TestSupport.size(fixture.model.image!) == (width: 8, height: 4))
    }

    @Test("Pasting clears any folder being browsed")
    func pasteClearsFolderBrowsing() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        TestSupport.writePNG(TestSupport.solidImage(width: 4, height: 4), named: "second.png", in: fixture.directory)
        fixture.model.openFolder(fixture.directory)
        #expect(fixture.model.canBrowse)

        putImageOnPasteboard(fixture.pasteboard)
        fixture.model.paste()

        #expect(fixture.model.canBrowse == false)
        #expect(fixture.model.folderImages.isEmpty)
    }

    // MARK: - Round trip

    @Test("An image survives a copy and paste")
    func copyPasteRoundTrip() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.load(from: fixture.imageURL)
        let original = TestSupport.allPixels(fixture.model.image!)

        fixture.model.copyToPasteboard()
        fixture.model.paste()

        #expect(TestSupport.allPixels(fixture.model.image!) == original)
        #expect(fixture.model.url == nil)
    }
}

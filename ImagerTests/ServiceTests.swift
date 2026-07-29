import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers the pasteboard reading behind the "Open in Imager" Finder service.
///
/// The service callback itself is driven by AppKit and needs a running app, but the
/// part that can get this wrong is pulling the file URL out of the pasteboard, and
/// that is plain logic.
@Suite("Open in Imager service")
struct ServiceTests {

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("ImagerTests-\(UUID().uuidString)"))
    }

    @Test("A file URL on the pasteboard is picked up")
    func readsAFileURL() {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let url = TestSupport.writePNG(TestSupport.solidImage(width: 2, height: 2), named: "a.png", in: directory)

        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])

        #expect(AppDelegate.fileURL(from: pasteboard) == url)
    }

    @Test("A folder URL is picked up, which is the case Finder cannot offer Open With for")
    func readsAFolderURL() {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }

        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([directory as NSURL])

        #expect(AppDelegate.fileURL(from: pasteboard)?.standardizedFileURL == directory.standardizedFileURL)
    }

    @Test("The first of several URLs is used")
    func readsTheFirstOfSeveral() {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let first = TestSupport.writePNG(TestSupport.solidImage(width: 2, height: 2), named: "1.png", in: directory)
        let second = TestSupport.writePNG(TestSupport.solidImage(width: 2, height: 2), named: "2.png", in: directory)

        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([first as NSURL, second as NSURL])

        #expect(AppDelegate.fileURL(from: pasteboard) == first)
    }

    @Test("An empty pasteboard yields nothing")
    func emptyPasteboardYieldsNil() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()

        #expect(AppDelegate.fileURL(from: pasteboard) == nil)
    }

    @Test("A pasteboard holding only text yields nothing")
    func textOnlyPasteboardYieldsNil() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("/not/a/pasteboard/url", forType: .string)

        #expect(AppDelegate.fileURL(from: pasteboard) == nil, "a plain string is not a file URL")
    }
}

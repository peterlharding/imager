import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers the list building behind File ▸ Edit With.
///
/// The filtering and sorting are tested against synthetic paths rather than whatever
/// happens to be installed, so the result does not depend on the machine.
@Suite("ExternalEditor")
struct ExternalEditorTests {

    private func app(_ name: String, in directory: String = "/Applications") -> URL {
        URL(fileURLWithPath: "\(directory)/\(name).app")
    }

    // MARK: - Naming

    @Test("An application's name drops the bundle extension")
    func nameDropsExtension() {
        #expect(ExternalEditor.name(of: app("GIMP")) == "GIMP")
        #expect(ExternalEditor.name(of: app("Pixelmator Pro")) == "Pixelmator Pro")
        #expect(ExternalEditor.name(of: app("darktable")) == "darktable")
    }

    // MARK: - Filtering

    /// Offering Imager as a way to edit an image already open in Imager is noise.
    @Test("Imager is left out of its own list")
    func excludesItself() {
        let candidates = [app("GIMP"), app("Imager"), app("Preview")]

        let result = ExternalEditor.excludingSelf(from: candidates, selfBundleName: "Imager.app")

        #expect(result.map(ExternalEditor.name) == ["GIMP", "Preview"])
    }

    /// Several copies of Imager are commonly registered at once: a build directory, an
    /// exported copy, one in Applications. All of them should be dropped.
    @Test("Every copy of Imager is left out, wherever it lives")
    func excludesEveryCopyOfItself() {
        let candidates = [
            app("GIMP"),
            app("Imager", in: "/Applications"),
            app("Imager", in: "/Users/someone/Downloads"),
            app("Imager", in: "/Users/someone/Library/Developer/Xcode/DerivedData/Imager-abc/Build/Products/Debug"),
            app("Preview", in: "/System/Applications"),
        ]

        let result = ExternalEditor.excludingSelf(from: candidates, selfBundleName: "Imager.app")

        #expect(result.map(ExternalEditor.name) == ["GIMP", "Preview"])
    }

    @Test("An app that merely starts with the same name is kept")
    func keepsSimilarlyNamedApps() {
        let candidates = [app("ImagerPro"), app("Imager")]

        let result = ExternalEditor.excludingSelf(from: candidates, selfBundleName: "Imager.app")

        #expect(result.map(ExternalEditor.name) == ["ImagerPro"])
    }

    // MARK: - Ordering

    @Test("Applications are listed by name, case-insensitively")
    func sortsByName() {
        let candidates = [app("Preview"), app("darktable"), app("GIMP"), app("Affinity Photo")]

        let result = ExternalEditor.sorted(candidates)

        #expect(result.map(ExternalEditor.name) == ["Affinity Photo", "darktable", "GIMP", "Preview"])
    }

    @Test("Sorting is stable regardless of where an app is installed")
    func sortsIgnoringLocation() {
        let candidates = [
            app("Preview", in: "/System/Applications"),
            app("GIMP", in: "/Applications"),
        ]

        #expect(ExternalEditor.sorted(candidates).map(ExternalEditor.name) == ["GIMP", "Preview"])
    }

    // MARK: - Editor role

    @Test("An Editor declaration for the type counts")
    func editorRoleRecognised() {
        let types: [[String: Any]] = [
            ["CFBundleTypeRole": "Editor", "LSItemContentTypes": ["public.png"]],
        ]

        #expect(ExternalEditor.declaresEditorRole(documentTypes: types, for: .png))
    }

    @Test("A Viewer declaration does not count")
    func viewerRoleNotAnEditor() {
        let types: [[String: Any]] = [
            ["CFBundleTypeRole": "Viewer", "LSItemContentTypes": ["public.image"]],
        ]

        #expect(ExternalEditor.declaresEditorRole(documentTypes: types, for: .png) == false)
    }

    @Test("An Editor declaration for a broader type counts, via conformance")
    func editorRoleMatchesThroughConformance() {
        let types: [[String: Any]] = [
            ["CFBundleTypeRole": "Editor", "LSItemContentTypes": ["public.image"]],
        ]

        #expect(ExternalEditor.declaresEditorRole(documentTypes: types, for: .png), "PNG conforms to public.image")
    }

    @Test("An Editor declaration for an unrelated type does not count")
    func editorRoleForAnotherTypeIgnored() {
        let types: [[String: Any]] = [
            ["CFBundleTypeRole": "Editor", "LSItemContentTypes": ["com.adobe.pdf"]],
        ]

        #expect(ExternalEditor.declaresEditorRole(documentTypes: types, for: .png) == false)
    }

    @Test("Missing or malformed declarations are treated as not an editor")
    func malformedDeclarationsAreSafe() {
        #expect(ExternalEditor.declaresEditorRole(documentTypes: [], for: .png) == false)
        #expect(ExternalEditor.declaresEditorRole(documentTypes: [[:]], for: .png) == false)
        #expect(ExternalEditor.declaresEditorRole(
            documentTypes: [["CFBundleTypeRole": "Editor"]], for: .png
        ) == false)
    }

    /// The reason the non-editors are kept and offered rather than dropped: darktable
    /// declares Viewer for every image type despite being an editor.
    @Test("Splitting keeps the non-editors instead of discarding them")
    func splitKeepsEverything() {
        let apps = [app("GIMP"), app("darktable"), app("WhatsApp")]

        let split = ExternalEditor.split(apps, for: .png)

        #expect(split.editors.count + split.others.count == apps.count, "nothing is lost")
    }

    @Test("With no known type, everything goes in the second group")
    func splitWithoutATypeOffersEverything() {
        let apps = [app("GIMP"), app("darktable")]

        let split = ExternalEditor.split(apps, for: nil)

        #expect(split.editors.isEmpty)
        #expect(split.others.count == 2)
    }

    // MARK: - Against the real system

    /// A light check that the LaunchServices query works at all. Preview ships with
    /// macOS, so an image should always have at least one editor available.
    @Test("A real image has at least one application offered, and it is not Imager")
    func realQueryReturnsSomething() {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let url = TestSupport.writePNG(TestSupport.solidImage(width: 4, height: 4), named: "a.png", in: directory)

        let apps = ExternalEditor.applications(forOpening: url)

        #expect(!apps.isEmpty)
        #expect(!apps.contains { $0.lastPathComponent == Bundle.main.bundleURL.lastPathComponent })
    }
}

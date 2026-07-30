import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Imager

/// Covers the parts of batch processing that carry the risk: the naming that must never
/// overwrite anything, the destination rule that keeps originals out of reach, and the
/// per-file work. All headless - no runner, no sheet.
@Suite("Batch processing")
struct BatchTests {

    private func makeFolder(imageCount: Int = 3) -> URL {
        let directory = TestSupport.makeTemporaryDirectory()
        for index in 1...max(imageCount, 1) {
            TestSupport.writePNG(
                TestSupport.image(width: 4, height: 2, pixels: Array(repeating: .red, count: 8)),
                named: "photo\(index).png",
                in: directory
            )
        }
        return directory
    }

    // MARK: - Naming

    @Test("An unused name is used as it is")
    func unusedNameIsPlain() {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }

        let url = BatchProcessor.availableURL(in: directory, baseName: "photo", fileExtension: "png")

        #expect(url.lastPathComponent == "photo.png")
    }

    /// The property that matters most: a batch must never destroy a file it did not create.
    @Test("A taken name is numbered from 01 rather than overwritten")
    func collisionsAreNumbered() throws {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }

        let first = BatchProcessor.availableURL(in: directory, baseName: "photo", fileExtension: "png")
        try Data("original".utf8).write(to: first)

        let second = BatchProcessor.availableURL(in: directory, baseName: "photo", fileExtension: "png")
        #expect(second.lastPathComponent == "photo-01.png")
        try Data("second".utf8).write(to: second)

        let third = BatchProcessor.availableURL(in: directory, baseName: "photo", fileExtension: "png")
        #expect(third.lastPathComponent == "photo-02.png")

        // And nothing clobbered what was already there.
        #expect(try String(data: Data(contentsOf: first), encoding: .utf8) == "original")
    }

    @Test("Numbering keeps two digits up to 99")
    func numberingIsTwoDigits() throws {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }

        try Data().write(to: directory.appendingPathComponent("photo.png"))
        for number in 1...9 {
            let url = BatchProcessor.availableURL(in: directory, baseName: "photo", fileExtension: "png")
            #expect(url.lastPathComponent == String(format: "photo-%02d.png", number))
            try Data().write(to: url)
        }
    }

    @Test("A different extension is a different file")
    func extensionParticipatesInTheName() throws {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        try Data().write(to: directory.appendingPathComponent("photo.png"))

        let jpeg = BatchProcessor.availableURL(in: directory, baseName: "photo", fileExtension: "jpg")

        #expect(jpeg.lastPathComponent == "photo.jpg", "the png does not block the jpg")
    }

    // MARK: - Destination

    /// Numbering would protect the originals, but refusing the source folder makes it
    /// structurally impossible to touch them.
    @Test("The source folder is refused as a destination")
    func sourceFolderRefused() {
        let source = TestSupport.makeTemporaryDirectory()
        let other = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(source); TestSupport.remove(other) }

        #expect(BatchProcessor.isValidDestination(other, sourceFolder: source))
        #expect(BatchProcessor.isValidDestination(source, sourceFolder: source) == false)
    }

    @Test("The same folder reached by a different path is still refused")
    func sourceFolderRefusedViaAnotherPath() {
        let source = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(source) }

        // Same directory, spelled with a redundant component.
        let awkward = source.appendingPathComponent("sub/..").standardizedFileURL

        #expect(BatchProcessor.isValidDestination(awkward, sourceFolder: source) == false)
    }

    // MARK: - Processing one file

    @Test("Processing writes a file into the destination")
    func processingWritesAFile() throws {
        let source = makeFolder(imageCount: 1)
        let destination = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(source); TestSupport.remove(destination) }

        let result = BatchProcessor.process(
            source: source.appendingPathComponent("photo1.png"),
            edits: [],
            format: .sameAsSource,
            destination: destination
        )

        let written = try #require(try? result.get())
        #expect(written.lastPathComponent == "photo1.png")
        #expect(FileManager.default.fileExists(atPath: written.path))
    }

    @Test("The edits are applied to what gets written")
    func editsAreApplied() throws {
        let source = makeFolder(imageCount: 1)
        let destination = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(source); TestSupport.remove(destination) }

        let result = BatchProcessor.process(
            source: source.appendingPathComponent("photo1.png"),
            edits: [.rotate(degreesClockwise: 90)],
            format: .sameAsSource,
            destination: destination
        )

        let written = try #require(try? result.get())
        let image = try #require(NSImage(contentsOf: written))
        #expect(TestSupport.size(image) == (width: 2, height: 4), "4x2 rotated is 2x4")
    }

    @Test("The originals are left untouched")
    func originalsUntouched() throws {
        let source = makeFolder(imageCount: 1)
        let destination = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(source); TestSupport.remove(destination) }
        let original = source.appendingPathComponent("photo1.png")
        let before = try Data(contentsOf: original)

        _ = BatchProcessor.process(
            source: original,
            edits: [.rotate(degreesClockwise: 90), .adjust(Adjustments(exposure: 1))],
            format: .fixed(.jpeg),
            destination: destination
        )

        #expect(try Data(contentsOf: original) == before)
    }

    @Test("A fixed format is used, and names the file accordingly")
    func fixedFormatIsUsed() throws {
        let source = makeFolder(imageCount: 1)
        let destination = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(source); TestSupport.remove(destination) }

        let result = BatchProcessor.process(
            source: source.appendingPathComponent("photo1.png"),
            edits: [],
            format: .fixed(.jpeg),
            destination: destination
        )

        let written = try #require(try? result.get())
        #expect(written.pathExtension == "jpg")
        #expect(NSImage(contentsOf: written) != nil, "and it really is an image")
    }

    @Test("An unreadable source is reported rather than crashing")
    func unreadableSourceReported() throws {
        let source = TestSupport.makeTemporaryDirectory()
        let destination = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(source); TestSupport.remove(destination) }
        let notAnImage = source.appendingPathComponent("notes.png")
        try Data("this is not a png".utf8).write(to: notAnImage)

        let result = BatchProcessor.process(
            source: notAnImage, edits: [], format: .sameAsSource, destination: destination
        )

        #expect(result == .failure(.unreadable))
    }

    @Test("Processing the same folder twice numbers the second run")
    func repeatedRunsDoNotOverwrite() throws {
        let source = makeFolder(imageCount: 2)
        let destination = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(source); TestSupport.remove(destination) }
        let sources = ImageModel.imageURLs(in: source)

        for _ in 0..<2 {
            for url in sources {
                _ = BatchProcessor.process(
                    source: url, edits: [], format: .sameAsSource, destination: destination
                )
            }
        }

        let written = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
        #expect(written == ["photo1-01.png", "photo1.png", "photo2-01.png", "photo2.png"])
    }

    // MARK: - Format resolution

    @Test("Same as source keeps a writable format", arguments: ["png", "jpg", "tiff", "heic"])
    func sameAsSourceKeepsWritableFormats(fileExtension: String) {
        let url = URL(fileURLWithPath: "/tmp/photo.\(fileExtension)")

        #expect(BatchFormat.sameAsSource.contentType(for: url) == UTType(filenameExtension: fileExtension))
    }

    /// Reuses the Save As fallback, so a folder of RAW files produces PNGs rather than
    /// failing on every one.
    @Test("Same as source falls back to PNG for camera RAW", arguments: ["nef", "cr2", "arw", "dng"])
    func sameAsSourceFallsBackForRaw(fileExtension: String) {
        let url = URL(fileURLWithPath: "/tmp/photo.\(fileExtension)")

        #expect(BatchFormat.sameAsSource.contentType(for: url) == .png)
    }

    /// The same image must not get a different name depending on which route wrote it:
    /// Export As produces .jpg, so batch must too, not preferredFilenameExtension's .jpeg.
    @Test("Extensions match the ones Export As uses")
    func extensionsMatchExportAs() {
        let png = URL(fileURLWithPath: "/tmp/photo.png")

        #expect(BatchFormat.fixed(.jpeg).fileExtension(for: png) == "jpg")
        #expect(BatchFormat.fixed(.tiff).fileExtension(for: png) == "tiff")
        for format in ImageFormat.allCases {
            #expect(BatchFormat.fixed(format).fileExtension(for: png) == format.fileExtension)
        }
    }

    @Test("Same as source keeps the extension the file already had")
    func sameAsSourceKeepsTheOriginalExtension() {
        #expect(BatchFormat.sameAsSource.fileExtension(for: URL(fileURLWithPath: "/tmp/a.jpg")) == "jpg")
        #expect(BatchFormat.sameAsSource.fileExtension(for: URL(fileURLWithPath: "/tmp/a.jpeg")) == "jpeg")
        #expect(BatchFormat.sameAsSource.fileExtension(for: URL(fileURLWithPath: "/tmp/a.nef")) == "png")
    }

    @Test("The offered formats are same-as-source plus every export format")
    func allCasesCoversTheExportFormats() {
        let cases = BatchFormat.allCases

        #expect(cases.first == .sameAsSource)
        #expect(cases.count == ImageFormat.allCases.count + 1)
        for format in ImageFormat.allCases {
            #expect(cases.contains(.fixed(format)))
        }
    }
}

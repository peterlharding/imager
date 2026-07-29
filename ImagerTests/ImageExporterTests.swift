import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Imager

/// Covers which formats can actually be written, and the Save As fallback that
/// keeps read-only formats such as camera RAW from offering a save that must fail.
@Suite("ImageExporter formats")
struct ImageExporterTests {

    @Test("The export formats on offer are all writable", arguments: ImageFormat.allCases)
    func offeredFormatsAreWritable(format: ImageFormat) {
        #expect(ImageExporter.canWrite(format.contentType))
    }

    @Test("Camera RAW is not writable", arguments: ["nef", "nrw", "cr2", "arw", "dng"])
    func rawIsNotWritable(fileExtension: String) {
        let type = UTType(filenameExtension: fileExtension)
        #expect(type != nil, "\(fileExtension) should be a known type")
        #expect(type.map { ImageExporter.canWrite($0) } == false)
    }

    /// The bug: Save As derived its format from the source extension, so a Nikon NEF
    /// asked ImageIO to write com.nikon.raw-image, which it cannot do.
    @Test("Save As falls back to PNG for read-only formats", arguments: ["nef", "cr2", "arw", "dng"])
    func saveAsFallsBackToPNGForRaw(fileExtension: String) {
        let source = UTType(filenameExtension: fileExtension)

        #expect(ImageExporter.saveAsType(for: source) == .png)
    }

    @Test("Save As keeps a writable source format", arguments: ["png", "jpg", "tiff", "gif", "heic"])
    func saveAsKeepsWritableFormats(fileExtension: String) {
        let source = UTType(filenameExtension: fileExtension)

        #expect(source != nil, "\(fileExtension) should be a known type")
        #expect(ImageExporter.saveAsType(for: source) == source)
    }

    @Test("An unknown source format falls back to PNG")
    func unknownSourceFallsBackToPNG() {
        #expect(ImageExporter.saveAsType(for: nil) == .png)
    }

    @Test("TIFF is both readable and writable")
    func tiffIsWritable() {
        #expect(ImageExporter.canWrite(.tiff))
        #expect(ImageFormat.allCases.contains { $0.contentType == .tiff })
    }
}

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Imager

/// Guards the export format table. A mismatch between an extension and its content
/// type would hand the save panel one format and write the file as another.
@Suite("ImageFormat")
struct ImageFormatTests {

    @Test("Every format offers all five choices")
    func allFormatsAreOffered() {
        #expect(ImageFormat.allCases.count == 5)
        #expect(Set(ImageFormat.allCases.map(\.displayName)).count == 5, "display names must be distinct")
        #expect(Set(ImageFormat.allCases.map(\.fileExtension)).count == 5, "extensions must be distinct")
    }

    @Test("A format's extension resolves back to its own content type", arguments: ImageFormat.allCases)
    func extensionMatchesContentType(format: ImageFormat) {
        #expect(UTType(filenameExtension: format.fileExtension) == format.contentType)
    }

    @Test("Every format's content type is a recognised image type", arguments: ImageFormat.allCases)
    func contentTypeIsAnImage(format: ImageFormat) {
        #expect(format.contentType.conforms(to: .image))
    }

    @Test("Extensions are lower case and carry no leading dot", arguments: ImageFormat.allCases)
    func extensionsAreClean(format: ImageFormat) {
        #expect(format.fileExtension == format.fileExtension.lowercased())
        #expect(!format.fileExtension.hasPrefix("."))
    }

    @Test("JPEG uses the short extension the save panel expects")
    func jpegUsesJpg() {
        #expect(ImageFormat.jpeg.fileExtension == "jpg")
    }
}

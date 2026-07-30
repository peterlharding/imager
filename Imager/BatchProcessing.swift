import AppKit
import UniformTypeIdentifiers

/// The output format for a batch: each image's own, or one format for all of them.
enum BatchFormat: Equatable, Hashable, Identifiable {
    /// Each image keeps its own format, falling back to PNG for anything that cannot be
    /// written - which is every camera RAW.
    case sameAsSource
    case fixed(ImageFormat)

    var id: String {
        switch self {
        case .sameAsSource: "same"
        case .fixed(let format): format.displayName
        }
    }

    var displayName: String {
        switch self {
        case .sameAsSource: "Same as original"
        case .fixed(let format): format.displayName
        }
    }

    static var allCases: [BatchFormat] {
        [.sameAsSource] + ImageFormat.allCases.map(BatchFormat.fixed)
    }

    /// The type to write `source` as.
    func contentType(for source: URL) -> UTType {
        switch self {
        case .sameAsSource:
            // Reuses the Save As rule, so a RAW source becomes PNG rather than failing.
            ImageExporter.saveAsType(for: UTType(filenameExtension: source.pathExtension))
        case .fixed(let format):
            format.contentType
        }
    }

    /// The extension to give the written file.
    ///
    /// Follows the rules already used elsewhere rather than `preferredFilenameExtension`,
    /// which would write `.jpeg` where Export As writes `.jpg` - the same image getting a
    /// different name depending on which route produced it.
    func fileExtension(for source: URL) -> String {
        switch self {
        case .sameAsSource:
            let sourceType = UTType(filenameExtension: source.pathExtension)
            let target = ImageExporter.saveAsType(for: sourceType)
            // A writable source keeps the extension it already had, so ".jpg" stays ".jpg".
            if target == sourceType, !source.pathExtension.isEmpty { return source.pathExtension }
            return target.preferredFilenameExtension ?? "png"
        case .fixed(let format):
            return format.fileExtension
        }
    }
}

/// Applies edits to one file and writes the result, with no UI and no shared state.
///
/// Deliberately a free function over values: it is the part of batch processing where the
/// bugs would be, and this way it can be exercised headlessly.
enum BatchProcessor {

    enum Failure: Error, Equatable {
        case unreadable
        case writeFailed(String)

        var message: String {
            switch self {
            case .unreadable: "Couldn't read the image."
            case .writeFailed(let detail): detail
            }
        }
    }

    /// Processes one image, returning the file written.
    static func process(
        source: URL,
        edits: [ImageEdit],
        format: BatchFormat,
        destination: URL
    ) -> Result<URL, Failure> {
        guard let image = NSImage(contentsOf: source) else { return .failure(.unreadable) }

        let result = edits.applied(to: image)
        let type = format.contentType(for: source)
        let target = availableURL(
            in: destination,
            baseName: source.deletingPathExtension().lastPathComponent,
            fileExtension: format.fileExtension(for: source)
        )

        if let error = ImageExporter.write(result, to: target, as: type) {
            return .failure(.writeFailed(error))
        }
        return .success(target)
    }

    // MARK: - Naming

    /// A URL in `directory` that nothing occupies yet.
    ///
    /// Collisions are numbered `name-01`, `name-02` and so on rather than replaced, so a
    /// batch can never destroy a file it did not create. Numbering rather than skipping,
    /// so a second run with a changed recipe visibly produces something.
    static func availableURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        let plain = directory.appendingPathComponent("\(baseName).\(fileExtension)")
        guard FileManager.default.fileExists(atPath: plain.path) else { return plain }

        for number in 1...9999 {
            let numbered = directory.appendingPathComponent(
                String(format: "%@-%02d.%@", baseName, number, fileExtension)
            )
            if !FileManager.default.fileExists(atPath: numbered.path) { return numbered }
        }
        // Absurdly unlikely; still better than overwriting or returning nothing.
        return directory.appendingPathComponent("\(baseName)-\(UUID().uuidString).\(fileExtension)")
    }

    // MARK: - Destination

    /// Whether `destination` is a safe place to write results from `sourceFolder`.
    ///
    /// The source folder is refused outright. Numbering would protect the originals, but
    /// refusing makes it structurally impossible to touch them rather than dependent on the
    /// naming being right.
    static func isValidDestination(_ destination: URL, sourceFolder: URL) -> Bool {
        destination.standardizedFileURL.resolvingSymlinksInPath()
            != sourceFolder.standardizedFileURL.resolvingSymlinksInPath()
    }
}

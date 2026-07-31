import Foundation
import ImageIO

/// A group of related frames - a burst, a bracket, several attempts at one shot - shown in the
/// browser as a single item.
///
/// Frames are stored as **filenames relative to the folder**, never absolute paths. That is what
/// lets a grouping survive the folder being moved or renamed, which is the whole reason stacks
/// live beside the photos rather than in Application Support.
struct ImageStack: Equatable, Codable {
    /// Every frame in the stack, in the order they were grouped. Always contains `pick`.
    var frames: [String]

    /// The frame shown when the stack is collapsed.
    var pick: String

    init(frames: [String], pick: String? = nil) {
        self.frames = frames
        self.pick = pick ?? frames.first ?? ""
    }

    var count: Int { frames.count }

    func contains(_ name: String) -> Bool { frames.contains(name) }
}

/// The stored document, versioned so its shape can change without stranding older files.
struct StacksDocument: Equatable, Codable {
    static let currentFormatVersion = 1

    var formatVersion = StacksDocument.currentFormatVersion
    var stacks: [ImageStack] = []
}

/// Reads and writes a folder's stacks, and works out which frames belong together.
enum Stacks {

    /// An app-owned directory rather than a feature-owned one, so future per-folder state has
    /// somewhere to go without breeding dot-directories, and so it cannot collide with another
    /// tool's `.stacks`.
    static let directoryName = ".imager"
    static let fileName = "stacks.json"

    // MARK: - Reconciling

    /// Drops what no longer exists and anything left too small to be a stack.
    ///
    /// Files get deleted and renamed in Finder, so a stored grouping is a claim about the folder
    /// rather than a fact about it, and has to be checked against what is actually present.
    static func reconcile(_ stacks: [ImageStack], against available: [String]) -> [ImageStack] {
        let present = Set(available)
        return stacks.compactMap { stack in
            let frames = stack.frames.filter(present.contains)
            // One frame is not a stack, and nor is none.
            guard frames.count >= 2 else { return nil }
            // A pick that has been deleted hands over to whatever is left.
            let pick = frames.contains(stack.pick) ? stack.pick : frames[0]
            return ImageStack(frames: frames, pick: pick)
        }
    }

    /// Removes any frame appearing in more than one stack, keeping its first appearance.
    ///
    /// Nothing in the app should produce overlapping stacks, but a hand-edited file could, and a
    /// frame in two stacks would appear twice in the browser.
    static func removingOverlaps(_ stacks: [ImageStack]) -> [ImageStack] {
        var seen = Set<String>()
        var result: [ImageStack] = []
        for stack in stacks {
            let frames = stack.frames.filter { seen.insert($0).inserted }
            guard frames.count >= 2 else { continue }
            let pick = frames.contains(stack.pick) ? stack.pick : frames[0]
            result.append(ImageStack(frames: frames, pick: pick))
        }
        return result
    }

    // MARK: - Auto-stacking

    /// Groups frames taken within `interval` of the one before them.
    ///
    /// Takes dates rather than URLs so the grouping can be exercised without EXIF: this is the
    /// part that decides what ends up stacked, and it should not need a camera to test.
    /// Frames with no date are never stacked - a missing date is not evidence of proximity.
    static func autoStack(
        dated frames: [(name: String, date: Date?)],
        within interval: TimeInterval
    ) -> [ImageStack] {
        let dated = frames.compactMap { frame in frame.date.map { (name: frame.name, date: $0) } }
            .sorted { $0.date < $1.date }
        guard dated.count >= 2, interval > 0 else { return [] }

        var stacks: [ImageStack] = []
        var current: [(name: String, date: Date)] = [dated[0]]

        for frame in dated.dropFirst() {
            // Measured against the previous frame, not the first of the group, so a long
            // continuous burst stays one stack.
            if frame.date.timeIntervalSince(current[current.count - 1].date) <= interval {
                current.append(frame)
            } else {
                if current.count >= 2 { stacks.append(ImageStack(frames: current.map(\.name))) }
                current = [frame]
            }
        }
        if current.count >= 2 { stacks.append(ImageStack(frames: current.map(\.name))) }
        return stacks
    }

    /// The moment a photograph was taken, from EXIF, or nil when the file does not say.
    static func captureDate(of url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let taken = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
              let moment = exifDateFormatter.date(from: taken) else {
            return nil
        }
        return moment.addingTimeInterval(subSecond(exif))
    }

    /// The fraction of a second EXIF records separately.
    ///
    /// `DateTimeOriginal` has whole-second resolution, and a burst is exactly the case that
    /// breaks on: several frames land in the same second and would look simultaneous. Cameras
    /// that shoot bursts write `SubsecTimeOriginal` alongside, so read it where it is there.
    private static func subSecond(_ exif: [CFString: Any]) -> TimeInterval {
        let raw = exif[kCGImagePropertyExifSubsecTimeOriginal]
        // Written as a string by most cameras, as a number by some.
        let digits: String
        switch raw {
        case let text as String: digits = text.trimmingCharacters(in: .whitespaces)
        case let number as NSNumber: digits = number.stringValue
        default: return 0
        }
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber),
              let fraction = Double("0." + digits) else { return 0 }
        return fraction
    }

    /// EXIF timestamps are "yyyy:MM:dd HH:mm:ss" in the camera's local time, with no zone.
    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Storage

    /// Where a folder's stacks live, when the folder can be written to.
    static func directory(besidePhotosIn folder: URL) -> URL {
        folder.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Where they live when it cannot - a camera card, a read-only mount, a network share.
    /// Keyed by the folder's path, so it is lost if the folder moves; that is the trade for
    /// being able to store anything at all.
    static func fallbackFile(for folder: URL) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let key = folder.standardizedFileURL.path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return support
            .appendingPathComponent("Imager/FolderState", isDirectory: true)
            .appendingPathComponent("\(key).json")
    }

    /// Loads a folder's stacks, reconciled against the files actually present.
    ///
    /// Prefers the copy beside the photos; falls back to Application Support for folders that
    /// could not be written to.
    static func load(for folder: URL, available: [String]) -> [ImageStack] {
        let candidates = [
            directory(besidePhotosIn: folder).appendingPathComponent(fileName),
            fallbackFile(for: folder),
        ]
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let document = try? JSONDecoder().decode(StacksDocument.self, from: data) else {
                continue
            }
            return removingOverlaps(reconcile(document.stacks, against: available))
        }
        return []
    }

    /// Result of saving, so the app can say where the stacks ended up.
    enum SaveOutcome: Equatable {
        case besidePhotos
        case applicationSupport
        case failed(String)
    }

    @discardableResult
    static func save(_ stacks: [ImageStack], for folder: URL) -> SaveOutcome {
        let document = StacksDocument(stacks: stacks)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(document) else {
            return .failed("Couldn't prepare the stacks for saving.")
        }

        let beside = directory(besidePhotosIn: folder)
        do {
            try FileManager.default.createDirectory(at: beside, withIntermediateDirectories: true)
            try data.write(to: beside.appendingPathComponent(fileName), options: .atomic)
            return .besidePhotos
        } catch {
            // Read-only volume, a card, a share: keep the grouping rather than lose it.
        }

        let fallback = fallbackFile(for: folder)
        do {
            try FileManager.default.createDirectory(
                at: fallback.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: fallback, options: .atomic)
            return .applicationSupport
        } catch {
            return .failed("Couldn't save the stacks. \(error.localizedDescription)")
        }
    }
}

import Foundation
import Testing
@testable import Imager

/// Covers the stack logic: reconciling a stored grouping against what is on disk, grouping
/// frames by capture time, and where the file ends up.
@Suite("Stacks")
struct StacksTests {

    private func date(_ secondsFromStart: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + secondsFromStart)
    }

    // MARK: - Reconciling

    /// A stored grouping is a claim about the folder, not a fact about it: files get deleted and
    /// renamed in Finder while Imager is not looking.
    @Test("A frame that no longer exists is dropped")
    func missingFrameDropped() {
        let stacks = [ImageStack(frames: ["a.jpg", "b.jpg", "c.jpg"], pick: "a.jpg")]

        let result = Stacks.reconcile(stacks, against: ["a.jpg", "c.jpg"])

        #expect(result.count == 1)
        #expect(result[0].frames == ["a.jpg", "c.jpg"])
        #expect(result[0].pick == "a.jpg")
    }

    @Test("A stack left with one frame stops being a stack")
    func stackOfOneDropped() {
        let stacks = [ImageStack(frames: ["a.jpg", "b.jpg"], pick: "a.jpg")]

        #expect(Stacks.reconcile(stacks, against: ["a.jpg"]).isEmpty)
    }

    @Test("A stack whose frames have all gone is dropped")
    func emptyStackDropped() {
        let stacks = [ImageStack(frames: ["a.jpg", "b.jpg"], pick: "a.jpg")]

        #expect(Stacks.reconcile(stacks, against: ["z.jpg"]).isEmpty)
    }

    @Test("A deleted pick hands over to a surviving frame")
    func deletedPickIsReplaced() {
        let stacks = [ImageStack(frames: ["a.jpg", "b.jpg", "c.jpg"], pick: "a.jpg")]

        let result = Stacks.reconcile(stacks, against: ["b.jpg", "c.jpg"])

        #expect(result[0].pick == "b.jpg")
        #expect(result[0].frames == ["b.jpg", "c.jpg"])
    }

    @Test("Untouched stacks come back unchanged")
    func intactStacksSurvive() {
        let stacks = [
            ImageStack(frames: ["a.jpg", "b.jpg"], pick: "b.jpg"),
            ImageStack(frames: ["c.jpg", "d.jpg", "e.jpg"], pick: "c.jpg"),
        ]

        let result = Stacks.reconcile(stacks, against: ["a.jpg", "b.jpg", "c.jpg", "d.jpg", "e.jpg"])

        #expect(result == stacks)
    }

    /// Nothing in the app produces these, but the file can be hand-edited, and a frame in two
    /// stacks would appear twice in the browser.
    @Test("A frame in two stacks is kept only by the first")
    func overlapsRemoved() {
        let stacks = [
            ImageStack(frames: ["a.jpg", "b.jpg"], pick: "a.jpg"),
            ImageStack(frames: ["b.jpg", "c.jpg", "d.jpg"], pick: "b.jpg"),
        ]

        let result = Stacks.removingOverlaps(stacks)

        #expect(result.count == 2)
        #expect(result[0].frames == ["a.jpg", "b.jpg"])
        #expect(result[1].frames == ["c.jpg", "d.jpg"], "b belongs to the first stack")
        #expect(result[1].pick == "c.jpg", "and its pick had to move")
    }

    @Test("Removing an overlap can leave too few frames to be a stack")
    func overlapCanDissolveAStack() {
        let stacks = [
            ImageStack(frames: ["a.jpg", "b.jpg"], pick: "a.jpg"),
            ImageStack(frames: ["b.jpg", "a.jpg"], pick: "b.jpg"),
        ]

        #expect(Stacks.removingOverlaps(stacks).count == 1)
    }

    // MARK: - Auto-stacking

    @Test("Frames taken close together are grouped")
    func closeFramesGrouped() {
        let frames: [(name: String, date: Date?)] = [
            ("burst1.nef", date(0)),
            ("burst2.nef", date(1)),
            ("burst3.nef", date(2)),
            ("later.nef", date(600)),
        ]

        let result = Stacks.autoStack(dated: frames, within: 3)

        #expect(result.count == 1)
        #expect(result[0].frames == ["burst1.nef", "burst2.nef", "burst3.nef"])
        #expect(result[0].pick == "burst1.nef", "the first frame leads by default")
    }

    /// Measured against the previous frame rather than the first of the group, so holding the
    /// shutter down stays one stack however long the burst runs.
    @Test("A long continuous burst stays one stack")
    func longBurstStaysOne() {
        let frames = (0..<20).map { (name: "f\($0).nef", date: Optional(date(Double($0) * 0.5))) }

        let result = Stacks.autoStack(dated: frames, within: 1)

        #expect(result.count == 1)
        #expect(result[0].count == 20, "even though the last is 9.5s after the first")
    }

    @Test("A gap larger than the interval starts a new stack")
    func gapSplitsStacks() {
        let frames: [(name: String, date: Date?)] = [
            ("a.nef", date(0)), ("b.nef", date(1)),
            ("c.nef", date(30)), ("d.nef", date(31)),
        ]

        let result = Stacks.autoStack(dated: frames, within: 2)

        #expect(result.count == 2)
        #expect(result[0].frames == ["a.nef", "b.nef"])
        #expect(result[1].frames == ["c.nef", "d.nef"])
    }

    @Test("A lone frame is not stacked")
    func loneFrameNotStacked() {
        let frames: [(name: String, date: Date?)] = [
            ("alone.nef", date(0)),
            ("pair1.nef", date(100)), ("pair2.nef", date(101)),
        ]

        let result = Stacks.autoStack(dated: frames, within: 2)

        #expect(result.count == 1)
        #expect(result[0].frames == ["pair1.nef", "pair2.nef"])
    }

    /// A missing date is not evidence that two frames belong together.
    @Test("Frames without a date are never stacked")
    func undatedFramesIgnored() {
        let frames: [(name: String, date: Date?)] = [
            ("scan1.png", nil), ("scan2.png", nil), ("shot.nef", date(0)),
        ]

        #expect(Stacks.autoStack(dated: frames, within: 60).isEmpty)
    }

    @Test("Frames are grouped by time, whatever order they arrive in")
    func orderIndependent() {
        let frames: [(name: String, date: Date?)] = [
            ("c.nef", date(2)), ("a.nef", date(0)), ("b.nef", date(1)),
        ]

        let result = Stacks.autoStack(dated: frames, within: 3)

        #expect(result[0].frames == ["a.nef", "b.nef", "c.nef"])
    }

    @Test("An interval of zero groups nothing")
    func zeroIntervalGroupsNothing() {
        let frames: [(name: String, date: Date?)] = [("a.nef", date(0)), ("b.nef", date(0))]

        #expect(Stacks.autoStack(dated: frames, within: 0).isEmpty)
    }

    @Test("Fewer than two frames cannot make a stack")
    func tooFewFrames() {
        #expect(Stacks.autoStack(dated: [], within: 5).isEmpty)
        #expect(Stacks.autoStack(dated: [("a.nef", date(0))], within: 5).isEmpty)
    }

    // MARK: - Reading the capture time

    @Test("The capture time comes from EXIF")
    func readsCaptureDate() throws {
        let folder = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(folder) }
        let url = TestSupport.writeJPEG(named: "shot.jpg", in: folder, taken: "2025:03:02 14:30:15")

        let taken = try #require(Stacks.captureDate(of: url))

        var components = DateComponents()
        components.year = 2025; components.month = 3; components.day = 2
        components.hour = 14; components.minute = 30; components.second = 15
        let expected = try #require(Calendar.current.date(from: components))
        #expect(abs(taken.timeIntervalSince(expected)) < 1)
    }

    /// EXIF records whole seconds, which is exactly what a burst breaks: without the fraction
    /// every frame in one second looks simultaneous.
    @Test("Frames within a second are told apart by the sub-second field")
    func readsSubSecond() throws {
        let folder = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(folder) }
        let first = TestSupport.writeJPEG(
            named: "a.jpg", in: folder, taken: "2025:03:02 14:30:15", subSecond: "20"
        )
        let second = TestSupport.writeJPEG(
            named: "b.jpg", in: folder, taken: "2025:03:02 14:30:15", subSecond: "80"
        )

        let one = try #require(Stacks.captureDate(of: first))
        let other = try #require(Stacks.captureDate(of: second))

        #expect(abs(other.timeIntervalSince(one) - 0.6) < 0.001)
    }

    @Test("A file with no capture time gives nothing")
    func noCaptureDate() {
        let folder = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(folder) }
        let url = TestSupport.writeJPEG(named: "scan.jpg", in: folder, taken: nil)

        #expect(Stacks.captureDate(of: url) == nil)
    }

    @Test("A file that is not an image gives nothing")
    func notAnImage() throws {
        let folder = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(folder) }
        let url = folder.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: url)

        #expect(Stacks.captureDate(of: url) == nil)
    }

    /// End to end over real files: EXIF written to disk, read back, and grouped. The pieces are
    /// covered separately above; this checks they add up to the answer a photographer expects,
    /// and that the thresholds offered in the sheet each mean something different.
    @Test("A shoot groups the way it was shot")
    func groupsARealShoot() {
        let folder = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(folder) }
        // A burst, a lone frame, a three-shot bracket, then two tries at one composition.
        let shoot: [(offset: Double, name: String)] = [
            (0.00, "shot-01.jpg"), (0.25, "shot-02.jpg"), (0.50, "shot-03.jpg"), (0.75, "shot-04.jpg"),
            (240, "shot-05.jpg"),
            (400, "shot-06.jpg"), (402, "shot-07.jpg"), (404, "shot-08.jpg"),
            (700, "shot-09.jpg"), (720, "shot-10.jpg"),
        ]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let start = Date(timeIntervalSince1970: 1_741_012_200)

        let dated = shoot.map { frame -> (name: String, date: Date?) in
            let moment = start.addingTimeInterval(frame.offset)
            let fraction = frame.offset - frame.offset.rounded(.down)
            let url = TestSupport.writeJPEG(
                named: frame.name,
                in: folder,
                taken: formatter.string(from: moment),
                subSecond: String(format: "%02d", Int((fraction * 100).rounded()))
            )
            return (frame.name, Stacks.captureDate(of: url))
        }

        #expect(dated.allSatisfy { $0.date != nil }, "every frame carries a capture time")

        let burstOnly = Stacks.autoStack(dated: dated, within: 0.5)
        #expect(burstOnly.count == 1)
        #expect(burstOnly[0].count == 4, "the burst, told apart only by the sub-second field")

        let withBracket = Stacks.autoStack(dated: dated, within: 2)
        #expect(withBracket.map(\.count) == [4, 3], "the burst and the bracket, not the lone frame")

        let withTries = Stacks.autoStack(dated: dated, within: 60)
        #expect(withTries.map(\.count) == [4, 3, 2])
        #expect(withTries[2].frames == ["shot-09.jpg", "shot-10.jpg"])
    }

    // MARK: - Storage

    @Test("Stacks are written beside the photos and read back")
    func savedBesidePhotos() {
        let folder = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(folder) }
        let stacks = [ImageStack(frames: ["a.jpg", "b.jpg"], pick: "b.jpg")]

        #expect(Stacks.save(stacks, for: folder) == .besidePhotos)

        let file = folder.appendingPathComponent(".imager/stacks.json")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(Stacks.load(for: folder, available: ["a.jpg", "b.jpg"]) == stacks)
    }

    /// The reason for storing filenames rather than paths: the grouping has to survive the
    /// folder being moved or renamed.
    @Test("A grouping survives the folder being renamed")
    func survivesFolderMove() throws {
        let original = TestSupport.makeTemporaryDirectory()
        let moved = original.deletingLastPathComponent()
            .appendingPathComponent("moved-\(UUID().uuidString)", isDirectory: true)
        defer { TestSupport.remove(moved); TestSupport.remove(original) }

        Stacks.save([ImageStack(frames: ["a.jpg", "b.jpg"], pick: "a.jpg")], for: original)
        try FileManager.default.moveItem(at: original, to: moved)

        let loaded = Stacks.load(for: moved, available: ["a.jpg", "b.jpg"])

        #expect(loaded.count == 1)
        #expect(loaded[0].frames == ["a.jpg", "b.jpg"])
    }

    @Test("Loading reconciles against what is present")
    func loadReconciles() {
        let folder = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(folder) }
        Stacks.save([ImageStack(frames: ["a.jpg", "b.jpg", "c.jpg"], pick: "a.jpg")], for: folder)

        let loaded = Stacks.load(for: folder, available: ["a.jpg", "c.jpg"])

        #expect(loaded[0].frames == ["a.jpg", "c.jpg"], "b has gone since it was written")
    }

    @Test("A folder with no stacks file yields nothing")
    func noFileYieldsNothing() {
        let folder = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(folder) }

        #expect(Stacks.load(for: folder, available: ["a.jpg"]).isEmpty)
    }

    @Test("An unreadable file yields nothing rather than failing")
    func unreadableFileYieldsNothing() throws {
        let folder = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(folder) }
        let directory = folder.appendingPathComponent(".imager", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("stacks.json"))

        #expect(Stacks.load(for: folder, available: ["a.jpg", "b.jpg"]).isEmpty)
    }

    @Test("The fallback location is keyed by the folder's path")
    func fallbackIsKeyedByPath() {
        let one = Stacks.fallbackFile(for: URL(fileURLWithPath: "/Photos/Wedding"))
        let other = Stacks.fallbackFile(for: URL(fileURLWithPath: "/Photos/Holiday"))

        #expect(one != other)
        #expect(one.pathExtension == "json")
        #expect(one.lastPathComponent.contains("Wedding"))
    }

    @Test("The stacks directory is hidden, so browsing never sees it")
    func directoryIsHidden() {
        let folder = URL(fileURLWithPath: "/Photos/Wedding")

        #expect(Stacks.directory(besidePhotosIn: folder).lastPathComponent.hasPrefix("."))
        #expect(Stacks.directoryName == ".imager", "named for the app, not the feature")
    }

    /// Hidden files are skipped when a folder is enumerated, so the directory cannot turn up as
    /// an image, in a slideshow, or in a batch.
    @Test("The stacks directory does not appear when the folder is listed")
    func directoryNotEnumerated() {
        let folder = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(folder) }
        TestSupport.writePNG(TestSupport.solidImage(width: 4, height: 4), named: "photo.png", in: folder)
        Stacks.save([ImageStack(frames: ["a.jpg", "b.jpg"], pick: "a.jpg")], for: folder)

        let listed = ImageModel.imageURLs(in: folder).map(\.lastPathComponent)

        #expect(listed == ["photo.png"])
    }
}

import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers tonal and colour adjustments: that they change the image, that a drag costs
/// one undo step, that only the last one applies, and how they sit against geometry.
@Suite("Adjustments", .serialized)
@MainActor
struct AdjustmentTests {

    private struct Fixture {
        let model: ImageModel
        let directory: URL
        let imageURL: URL
    }

    /// A mid-grey gradient gives every adjustment something to act on.
    private func makeFixture() -> Fixture {
        let directory = TestSupport.makeTemporaryDirectory()

        let width = 32, height = 8
        var pixels: [TestSupport.Pixel] = []
        pixels.reserveCapacity(width * height)
        for _ in 0..<height {
            for x in 0..<width {
                let value: UInt8 = UInt8(x * 255 / (width - 1))
                pixels.append(TestSupport.Pixel(r: value, g: UInt8(255 - Int(value)), b: 128, a: 255))
            }
        }
        let url = TestSupport.writePNG(
            TestSupport.image(width: width, height: height, pixels: pixels),
            named: "gradient.png",
            in: directory
        )

        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(recents: RecentFilesStore(defaults: suite), defaults: suite)
        model.load(from: url)

        return Fixture(model: model, directory: directory, imageURL: url)
    }

    // MARK: - The values themselves

    @Test("A new adjustment is neutral, and neutral changes nothing")
    func neutralIsNeutral() {
        let image = TestSupport.solidImage(width: 8, height: 4)

        #expect(Adjustments.neutral.isNeutral)
        #expect(ImageAdjuster.apply(.neutral, to: image) === image, "a no-op must not re-render")
    }

    /// Passed as whole `Adjustments` values rather than key paths, because a
    /// `WritableKeyPath` is not `Sendable` and cannot cross the test's isolation
    /// boundary - a warning today and an error under the Swift 6 language mode.
    @Test("Each adjustment changes the image", arguments: [
        ("exposure", Adjustments(exposure: 1.0)),
        ("highlights", Adjustments(highlights: 0.4)),
        ("shadows", Adjustments(shadows: 0.8)),
        ("contrast", Adjustments(contrast: 1.6)),
        ("saturation", Adjustments(saturation: 0.2)),
        ("vibrance", Adjustments(vibrance: 0.9)),
        ("hue", Adjustments(hue: 90)),
    ])
    func eachAdjustmentHasAnEffect(name: String, adjustments: Adjustments) throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        let before = TestSupport.allPixels(try #require(fixture.model.image))

        #expect(!adjustments.isNeutral, "\(name) must actually differ from neutral")
        fixture.model.setAdjustments(adjustments)

        let after = TestSupport.allPixels(try #require(fixture.model.image))
        #expect(after != before, "\(name) should visibly change the image")
    }

    @Test("The size of the image is untouched")
    func adjustingKeepsTheSize() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        let before = TestSupport.size(try #require(fixture.model.image))

        fixture.model.setAdjustments(Adjustments(exposure: 1.5, contrast: 1.4))

        #expect(TestSupport.size(try #require(fixture.model.image)) == before)
    }

    // MARK: - Undo steps

    @Test("A drag costs one undo step, not one per tick")
    func dragIsOneUndoStep() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        // First change of the drag, then a run of continuing ones.
        fixture.model.setAdjustments(Adjustments(exposure: 0.1))
        for step in 2...20 {
            fixture.model.setAdjustments(Adjustments(exposure: Double(step) / 10), continuingSession: true)
        }

        #expect(fixture.model.edits.count == 1, "twenty ticks, one edit")
        #expect(fixture.model.adjustments.exposure == 2.0, "holding the value the drag ended on")

        fixture.model.undo()
        #expect(fixture.model.adjustments.isNeutral, "one undo takes the whole drag back")
    }

    @Test("Separate drags are separate undo steps")
    func separateDragsAreSeparateSteps() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.setAdjustments(Adjustments(exposure: 1))
        fixture.model.setAdjustments(Adjustments(exposure: 1, contrast: 1.5))

        #expect(fixture.model.edits.count == 2)

        fixture.model.undo()

        #expect(fixture.model.adjustments.contrast == 1, "the contrast drag is undone")
        #expect(fixture.model.adjustments.exposure == 1, "the earlier exposure drag survives")
    }

    /// The rule that keeps replay to a single filter pass however long the history is.
    @Test("Only the last adjustment applies")
    func lastAdjustmentSupersedesEarlier() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.setAdjustments(Adjustments(exposure: 2, saturation: 0))
        fixture.model.setAdjustments(Adjustments(contrast: 1.5))
        let stacked = TestSupport.allPixels(try #require(fixture.model.image))

        // The same final adjustment reached in one step must give the same pixels.
        let fresh = makeFixture()
        defer { TestSupport.remove(fresh.directory) }
        fresh.model.setAdjustments(Adjustments(contrast: 1.5))

        #expect(TestSupport.allPixels(try #require(fresh.model.image)) == stacked)
    }

    // MARK: - Reset

    @Test("Reset returns the image to how it was")
    func resetRestoresTheImage() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        let original = TestSupport.allPixels(try #require(fixture.model.image))

        fixture.model.setAdjustments(Adjustments(exposure: 1.5, saturation: 0))
        #expect(TestSupport.allPixels(try #require(fixture.model.image)) != original)

        fixture.model.setAdjustments(.neutral)

        #expect(TestSupport.allPixels(try #require(fixture.model.image)) == original)
        #expect(fixture.model.adjustments.isNeutral)
    }

    @Test("A neutral adjustment on an untouched image is not recorded")
    func neutralOnUntouchedImageIsNotRecorded() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.setAdjustments(.neutral)

        #expect(fixture.model.edits.isEmpty, "an edit that changes nothing is not worth a history entry")
        #expect(fixture.model.hasUnsavedEdits == false)
    }

    // MARK: - Alongside geometry

    @Test("Adjusting after a crop keeps the crop")
    func adjustingAfterCropKeepsTheCrop() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.crop(to: CGRect(x: 0, y: 0, width: 16, height: 8))
        fixture.model.setAdjustments(Adjustments(exposure: 1))

        #expect(TestSupport.size(try #require(fixture.model.image)) == (width: 16, height: 8))
    }

    /// Geometry is replayed before the adjustment whatever order they were made in, so
    /// the two sequences must land on the same image.
    @Test("Crop then adjust matches adjust then crop")
    func geometryAlwaysRunsFirst() throws {
        let cropRect = CGRect(x: 0, y: 0, width: 16, height: 8)
        let adjustments = Adjustments(exposure: 1, contrast: 1.3)

        let first = makeFixture()
        defer { TestSupport.remove(first.directory) }
        first.model.crop(to: cropRect)
        first.model.setAdjustments(adjustments)

        let second = makeFixture()
        defer { TestSupport.remove(second.directory) }
        second.model.setAdjustments(adjustments)
        second.model.crop(to: cropRect)

        #expect(
            TestSupport.allPixels(try #require(first.model.image))
                == TestSupport.allPixels(try #require(second.model.image))
        )
    }

    @Test("Adjustments count as unsaved edits and can be reverted")
    func adjustmentsJoinTheEditHistory() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        let original = TestSupport.allPixels(try #require(fixture.model.image))

        fixture.model.setAdjustments(Adjustments(saturation: 0))

        #expect(fixture.model.hasUnsavedEdits)
        #expect(fixture.model.canRevert)
        #expect(fixture.model.undoActionName == "Adjust")

        fixture.model.revert()

        #expect(TestSupport.allPixels(try #require(fixture.model.image)) == original)
    }

    /// Adjustments are unsaved work like any other edit, so opening another image asks
    /// first and only clears them once that is confirmed.
    @Test("Opening another image asks about adjustments, then clears them")
    func adjustmentsAreClearedOnLoad() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.setAdjustments(Adjustments(exposure: 2))
        fixture.model.load(from: fixture.imageURL)

        #expect(fixture.model.pendingDiscard != nil, "an adjustment is unsaved work")
        #expect(fixture.model.adjustments.exposure == 2, "and is still in force until answered")

        fixture.model.resolveDiscard(confirmed: true)

        #expect(fixture.model.adjustments.isNeutral)
    }
}

import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers the slideshow's advance and stop rules. The timer is never started for
/// these: `advance()` is the whole step, so it can be driven directly and the
/// behaviour checked without waiting on real time.
@Suite("Slideshow", .serialized)
@MainActor
struct SlideshowTests {

    private struct Fixture {
        let model: ImageModel
        let slideshow: Slideshow
        let directory: URL
    }

    /// A model browsing a temporary folder of `imageCount` images, with the
    /// slideshow pointed at a throwaway defaults suite.
    private func makeFixture(imageCount: Int, defaults: UserDefaults? = nil) -> Fixture {
        let directory = TestSupport.makeTemporaryDirectory()
        for index in 0..<imageCount {
            TestSupport.writePNG(
                TestSupport.solidImage(width: 4, height: 4),
                named: "image\(index).png",
                in: directory
            )
        }

        let suite = defaults ?? UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(recents: RecentFilesStore(defaults: suite))
        model.openFolder(directory)

        return Fixture(model: model, slideshow: Slideshow(model: model, defaults: suite), directory: directory)
    }

    // MARK: - Starting and stopping

    @Test("A folder of several images can start a show")
    func canStartWithAFolder() {
        let fixture = makeFixture(imageCount: 3)
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.slideshow.canStart)
        #expect(fixture.slideshow.isRunning == false)
    }

    @Test("A single image is not a slideshow")
    func cannotStartWithOneImage() {
        let fixture = makeFixture(imageCount: 1)
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.slideshow.canStart == false)

        fixture.slideshow.start()
        #expect(fixture.slideshow.isRunning == false, "starting must be refused, not silently accepted")
    }

    @Test("Starting and stopping flips the running flag")
    func startAndStop() {
        let fixture = makeFixture(imageCount: 3)
        defer { TestSupport.remove(fixture.directory) }

        fixture.slideshow.start()
        #expect(fixture.slideshow.isRunning)

        fixture.slideshow.stop()
        #expect(fixture.slideshow.isRunning == false)
    }

    @Test("Toggling alternates between running and stopped")
    func toggleAlternates() {
        let fixture = makeFixture(imageCount: 3)
        defer { TestSupport.remove(fixture.directory) }

        fixture.slideshow.toggle()
        #expect(fixture.slideshow.isRunning)

        fixture.slideshow.toggle()
        #expect(fixture.slideshow.isRunning == false)
    }

    // MARK: - Advancing

    @Test("Advancing moves to the next image")
    func advanceMovesForward() {
        let fixture = makeFixture(imageCount: 3)
        defer { TestSupport.remove(fixture.directory) }

        fixture.slideshow.start()
        #expect(fixture.model.selectionIndex == 0)

        fixture.slideshow.advance()
        #expect(fixture.model.selectionIndex == 1)

        fixture.slideshow.advance()
        #expect(fixture.model.selectionIndex == 2)
    }

    @Test("Advancing does nothing while stopped")
    func advanceIgnoredWhileStopped() {
        let fixture = makeFixture(imageCount: 3)
        defer { TestSupport.remove(fixture.directory) }

        fixture.slideshow.advance()

        #expect(fixture.model.selectionIndex == 0, "a stopped show must not move the selection")
    }

    @Test("Reaching the end wraps around when repeat is on")
    func wrapsWhenLooping() {
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        suite.set(true, forKey: SlideshowSetting.loopKey)
        let fixture = makeFixture(imageCount: 2, defaults: suite)
        defer { TestSupport.remove(fixture.directory) }

        fixture.slideshow.start()
        fixture.slideshow.advance()
        #expect(fixture.model.selectionIndex == 1, "at the last image")

        fixture.slideshow.advance()
        #expect(fixture.model.selectionIndex == 0, "wrapped back to the first")
        #expect(fixture.slideshow.isRunning, "and kept running")
    }

    @Test("Reaching the end stops the show when repeat is off")
    func stopsAtEndWhenNotLooping() {
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        suite.set(false, forKey: SlideshowSetting.loopKey)
        let fixture = makeFixture(imageCount: 2, defaults: suite)
        defer { TestSupport.remove(fixture.directory) }

        fixture.slideshow.start()
        fixture.slideshow.advance()
        #expect(fixture.model.selectionIndex == 1)

        fixture.slideshow.advance()
        #expect(fixture.slideshow.isRunning == false, "stopped rather than wrapping")
        #expect(fixture.model.selectionIndex == 1, "and stayed on the last image")
    }

    // MARK: - Unsaved edits

    /// The rule that keeps the timer from colliding with the 0.11.0 discard
    /// confirmation: a show must never advance away from unsaved work.
    @Test("An unsaved edit stops the show instead of advancing")
    func unsavedEditStopsTheShow() {
        let fixture = makeFixture(imageCount: 3)
        defer { TestSupport.remove(fixture.directory) }

        fixture.slideshow.start()
        fixture.model.rotate(byDegreesClockwise: 90)

        fixture.slideshow.advance()

        #expect(fixture.slideshow.isRunning == false)
        #expect(fixture.model.selectionIndex == 0, "the edited image is still on screen")
        #expect(fixture.model.pendingDiscard == nil, "and no discard prompt was raised")
        #expect(fixture.model.hasUnsavedEdits, "the edit is intact")
    }

    @Test("Saving a copy lets the show carry on")
    func savingAllowsAdvancing() {
        let fixture = makeFixture(imageCount: 3)
        defer { TestSupport.remove(fixture.directory) }

        fixture.slideshow.start()
        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.markEditsSaved()

        fixture.slideshow.advance()

        #expect(fixture.slideshow.isRunning)
        #expect(fixture.model.selectionIndex == 1)
    }

    // MARK: - Preferences

    @Test("The interval falls back to the default when unset")
    func intervalDefaults() {
        let fixture = makeFixture(imageCount: 2)
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.slideshow.interval == SlideshowSetting.defaultInterval)
    }

    @Test("The interval is clamped to the supported range", arguments: [
        (stored: 0.5, expected: SlideshowSetting.minInterval),
        (stored: 1.0, expected: 1.0),
        (stored: 10.0, expected: 10.0),
        (stored: 60.0, expected: 60.0),
        (stored: 600.0, expected: SlideshowSetting.maxInterval),
    ])
    func intervalIsClamped(stored: Double, expected: Double) {
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        suite.set(stored, forKey: SlideshowSetting.intervalKey)
        let fixture = makeFixture(imageCount: 2, defaults: suite)
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.slideshow.interval == expected)
    }

    @Test("Repeat is on unless it has been turned off")
    func loopDefaultsOn() {
        let fixture = makeFixture(imageCount: 2)
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.slideshow.loops == SlideshowSetting.defaultLoop)
        #expect(fixture.slideshow.loops)
    }
}

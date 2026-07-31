import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers what stacks do to a folder once it is open: what the browser shows, what arrowing
/// through it steps past, and what survives a frame being trashed.
@Suite("Stack Browsing", .serialized)
@MainActor
struct StackBrowsingTests {

    private struct Fixture {
        let model: ImageModel
        let directory: URL
    }

    /// Six images, so a stack can hide some of them and leave others alone.
    private func makeFixture() -> Fixture {
        let directory = TestSupport.makeTemporaryDirectory()
        for index in 1...6 {
            TestSupport.writePNG(
                TestSupport.solidImage(width: 4, height: 4), named: "image\(index).png", in: directory
            )
        }
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(
            recents: RecentFilesStore(defaults: suite),
            defaults: suite,
            // Deleted rather than trashed, so the folder genuinely changes without filling
            // the real Trash on every run.
            trashItem: { try FileManager.default.removeItem(at: $0) }
        )
        return Fixture(model: model, directory: directory)
    }

    /// Writes a grouping to the folder before it is opened, which is the only route the model
    /// offers into having stacks that were not just auto-generated.
    private func openWithStack(_ fixture: Fixture, frames: [String], pick: String? = nil) {
        Stacks.save([ImageStack(frames: frames, pick: pick)], for: fixture.directory)
        fixture.model.openFolder(fixture.directory)
    }

    private func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

    private func showing(_ model: ImageModel) -> String? { model.url?.lastPathComponent }

    // MARK: - What the browser shows

    @Test("A collapsed stack shows only its pick")
    func collapsedShowsPick() {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png", "image4.png"], pick: "image3.png")

        #expect(names(fixture.model.visibleImages)
                == ["image1.png", "image3.png", "image5.png", "image6.png"])
        #expect(fixture.model.folderImages.count == 6, "the folder itself is unchanged")
    }

    @Test("Expanding a stack reveals its frames in place")
    func expandingReveals() throws {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png", "image4.png"], pick: "image3.png")
        let stack = try #require(fixture.model.stacks.first)

        fixture.model.toggleExpansion(of: stack)

        #expect(names(fixture.model.visibleImages) == (1...6).map { "image\($0).png" })
        #expect(fixture.model.isExpanded(stack))
    }

    @Test("A folder with no stacks shows everything")
    func noStacksShowsAll() {
        let fixture = makeFixture()
        fixture.model.openFolder(fixture.directory)

        #expect(fixture.model.visibleImages == fixture.model.folderImages)
        #expect(fixture.model.pickImages == fixture.model.folderImages)
    }

    /// Picks ignore expansion: what a slideshow or a batch runs on should not depend on which
    /// stacks happen to be open in the browser.
    @Test("Expanding a stack does not add frames to the picks")
    func expansionDoesNotAffectPicks() throws {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png"], pick: "image2.png")
        let stack = try #require(fixture.model.stacks.first)
        let before = fixture.model.pickImages

        fixture.model.toggleExpansion(of: stack)

        #expect(fixture.model.pickImages == before)
        #expect(names(before)
                == ["image1.png", "image2.png", "image4.png", "image5.png", "image6.png"])
    }

    // MARK: - Navigation

    @Test("Arrowing past a collapsed stack skips its hidden frames")
    func navigationSkipsHiddenFrames() {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png", "image4.png"], pick: "image2.png")

        #expect(showing(fixture.model) == "image1.png")
        fixture.model.showNext()
        #expect(showing(fixture.model) == "image2.png", "the pick")
        fixture.model.showNext()
        #expect(showing(fixture.model) == "image5.png", "3 and 4 are behind the pick")
    }

    @Test("Arrowing through an expanded stack visits every frame")
    func navigationEntersExpandedStack() throws {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png"], pick: "image2.png")
        fixture.model.toggleExpansion(of: try #require(fixture.model.stacks.first))

        fixture.model.showNext()
        fixture.model.showNext()

        #expect(showing(fixture.model) == "image3.png")
    }

    @Test("Arrowing back also steps over a collapsed stack")
    func navigationBackwardsSkips() {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png", "image4.png"], pick: "image4.png")
        fixture.model.select(fixture.model.folderImages[4])   // image5

        fixture.model.showPrevious()

        #expect(showing(fixture.model) == "image4.png", "the pick, not image3")
    }

    /// Otherwise the browser would highlight a row that is no longer there.
    @Test("Collapsing a stack moves the selection to its pick")
    func collapsingMovesSelection() throws {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png"], pick: "image2.png")
        let stack = try #require(fixture.model.stacks.first)
        fixture.model.toggleExpansion(of: stack)
        fixture.model.select(fixture.model.folderImages[2])   // image3, a hidden frame
        #expect(showing(fixture.model) == "image3.png")

        fixture.model.toggleExpansion(of: stack)

        #expect(showing(fixture.model) == "image2.png")
    }

    @Test("Collapsing leaves a selection that is still visible alone")
    func collapsingLeavesVisibleSelection() throws {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png"], pick: "image2.png")
        let stack = try #require(fixture.model.stacks.first)
        fixture.model.toggleExpansion(of: stack)
        fixture.model.select(fixture.model.folderImages[5])   // image6, outside the stack

        fixture.model.toggleExpansion(of: stack)

        #expect(showing(fixture.model) == "image6.png")
    }

    // MARK: - Changing a stack

    @Test("Setting the pick changes what the collapsed stack shows")
    func setPick() {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png"], pick: "image2.png")

        fixture.model.promoteToPick(fixture.model.folderImages[2])   // image3

        #expect(fixture.model.stacks[0].pick == "image3.png")
        #expect(names(fixture.model.visibleImages)
                == ["image1.png", "image3.png", "image4.png", "image5.png", "image6.png"])
    }

    /// Expansion is remembered by pick, so it has to follow the pick when that moves.
    @Test("Setting the pick of an expanded stack leaves it expanded")
    func setPickKeepsExpansion() throws {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png"], pick: "image2.png")
        fixture.model.toggleExpansion(of: try #require(fixture.model.stacks.first))

        fixture.model.promoteToPick(fixture.model.folderImages[2])

        #expect(fixture.model.isExpanded(fixture.model.stacks[0]))
        #expect(fixture.model.visibleImages.count == 6)
    }

    @Test("Unstacking puts every frame back in the browser")
    func unstack() {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png"], pick: "image2.png")

        fixture.model.unstack(fixture.model.folderImages[1])

        #expect(fixture.model.stacks.isEmpty)
        #expect(fixture.model.visibleImages.count == 6)
    }

    @Test("A change to the stacks is written to the folder")
    func changesArePersisted() {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png"], pick: "image2.png")

        fixture.model.promoteToPick(fixture.model.folderImages[2])

        let onDisk = Stacks.load(for: fixture.directory, available: (1...6).map { "image\($0).png" })
        #expect(onDisk.first?.pick == "image3.png")
    }

    @Test("Reopening a folder restores its stacks")
    func stacksSurviveReopen() {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png"], pick: "image2.png")

        fixture.model.close()
        fixture.model.openFolder(fixture.directory)

        #expect(fixture.model.stacks.count == 1)
        #expect(fixture.model.stacks[0].frames == ["image2.png", "image3.png"])
    }

    @Test("Closing a folder forgets its stacks")
    func closingClearsStacks() {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png"], pick: "image2.png")

        fixture.model.close()

        #expect(fixture.model.stacks.isEmpty)
        #expect(fixture.model.visibleImages.isEmpty)
    }

    // MARK: - Trashing a frame

    @Test("Trashing a pick hands the stack to a surviving frame")
    func trashingPickPromotes() {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png", "image4.png"], pick: "image2.png")
        fixture.model.select(fixture.model.folderImages[1])   // the pick

        fixture.model.moveToTrash()

        #expect(fixture.model.stacks.count == 1)
        #expect(fixture.model.stacks[0].pick == "image3.png")
        #expect(fixture.model.stacks[0].frames == ["image3.png", "image4.png"])
    }

    @Test("Trashing down to one frame dissolves the stack")
    func trashingDissolvesStack() {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png"], pick: "image2.png")
        fixture.model.select(fixture.model.folderImages[1])

        fixture.model.moveToTrash()

        #expect(fixture.model.stacks.isEmpty, "one frame is not a stack")
        #expect(names(fixture.model.visibleImages)
                == ["image1.png", "image3.png", "image4.png", "image5.png", "image6.png"])
    }

    @Test("The reduced stack is written back")
    func trashingPersists() {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image2.png", "image3.png", "image4.png"], pick: "image2.png")
        fixture.model.select(fixture.model.folderImages[1])

        fixture.model.moveToTrash()

        let onDisk = Stacks.load(
            for: fixture.directory, available: ["image1.png", "image3.png", "image4.png", "image5.png", "image6.png"]
        )
        #expect(onDisk.first?.frames == ["image3.png", "image4.png"])
    }

    /// Trashing shows whatever took the deleted file's place, which can be a frame behind a
    /// collapsed pick.
    @Test("Trashing never leaves a hidden frame on screen")
    func trashingKeepsSelectionVisible() throws {
        let fixture = makeFixture()
        openWithStack(fixture, frames: ["image3.png", "image4.png", "image5.png"], pick: "image3.png")
        fixture.model.select(fixture.model.folderImages[1])   // image2, outside the stack

        fixture.model.moveToTrash()

        let shown = try #require(fixture.model.url)
        #expect(fixture.model.visibleImages.contains(shown))
        #expect(shown.lastPathComponent == "image3.png", "the pick, not the frame behind it")
    }
}

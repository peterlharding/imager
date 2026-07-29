import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers recipes: what gets saved, what applying one does to the edit history, and that
/// stored recipes survive the adjustment set growing.
@Suite("Recipes", .serialized)
@MainActor
struct RecipeTests {

    private struct Fixture {
        let model: ImageModel
        let store: RecipeStore
        let directory: URL
        let imageURL: URL
    }

    /// The store writes to a temporary folder, never the user's real recipe collection.
    private func makeFixture() -> Fixture {
        let directory = TestSupport.makeTemporaryDirectory()
        let url = TestSupport.writePNG(
            TestSupport.image(width: 4, height: 2, pixels: Array(repeating: .red, count: 8)),
            named: "photo.png",
            in: directory
        )
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(recents: RecentFilesStore(defaults: suite), defaults: suite)
        model.load(from: url)

        let store = RecipeStore(directory: directory.appendingPathComponent("recipes", isDirectory: true))
        return Fixture(model: model, store: store, directory: directory, imageURL: url)
    }

    // MARK: - What a recipe holds

    @Test("Nothing to save on an untouched image")
    func nothingToSaveWhenUnedited() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.model.canSaveRecipe == false)
        #expect(fixture.model.recipeEdits.isEmpty)
    }

    /// A crop is in pixel coordinates of one particular image, so it cannot transfer.
    @Test("Crops are left out of a recipe")
    func cropsExcluded() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.crop(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        #expect(fixture.model.canSaveRecipe == false, "a crop alone is not worth a recipe")

        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.setAdjustments(Adjustments(exposure: 1))

        #expect(fixture.model.edits.count == 3)
        #expect(fixture.model.recipeEdits.count == 2, "the crop is dropped")
        #expect(fixture.model.recipeEdits.contains { $0.isCrop } == false)
    }

    // MARK: - Storage

    @Test("A saved recipe can be listed and read back")
    func saveAndReload() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.setAdjustments(Adjustments(exposure: 1.5, saturation: 0.5))

        #expect(fixture.store.save(name: "Warm and level", edits: fixture.model.recipeEdits))

        #expect(fixture.store.recipes.map(\.name) == ["Warm and level"])
        #expect(fixture.store.recipes[0].edits == fixture.model.recipeEdits)
        #expect(fixture.store.recipes[0].formatVersion == Recipe.currentFormatVersion)

        // A second store over the same folder must see it, i.e. it really is on disk.
        let reopened = RecipeStore(directory: fixture.directory.appendingPathComponent("recipes"))
        #expect(reopened.recipes.map(\.name) == ["Warm and level"])
    }

    @Test("Saving under an existing name replaces it")
    func savingReplaces() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.store.save(name: "Punchy", edits: [.adjust(Adjustments(contrast: 1.5))])
        fixture.store.save(name: "Punchy", edits: [.adjust(Adjustments(contrast: 1.9))])

        #expect(fixture.store.recipes.count == 1)
        #expect(fixture.store.recipes[0].edits == [.adjust(Adjustments(contrast: 1.9))])
    }

    @Test("Recipes are listed in name order")
    func listedInNameOrder() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        for name in ["Zesty", "autumn", "Bright 2", "Bright 10"] {
            fixture.store.save(name: name, edits: [.adjust(Adjustments(exposure: 1))])
        }

        #expect(fixture.store.recipes.map(\.name) == ["autumn", "Bright 2", "Bright 10", "Zesty"])
    }

    @Test("Deleting removes it")
    func deleting() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        fixture.store.save(name: "Temporary", edits: [.adjust(Adjustments(exposure: 1))])

        #expect(fixture.store.delete(fixture.store.recipes[0]))

        #expect(fixture.store.recipes.isEmpty)
    }

    @Test("An empty or blank name is refused")
    func blankNameRefused() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.store.save(name: "   ", edits: [.adjust(Adjustments(exposure: 1))]) == false)
        #expect(fixture.store.errorMessage != nil)
        #expect(fixture.store.recipes.isEmpty)
    }

    @Test("Saving nothing is refused")
    func emptyEditsRefused() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.store.save(name: "Empty", edits: []) == false)
        #expect(fixture.store.recipes.isEmpty)
    }

    /// A recipe's name becomes its filename, so characters a filename cannot hold have
    /// to be handled rather than allowed to make the save fail.
    @Test("Awkward names still save", arguments: [
        "Sunset / Beach", "Ratio 4:3", "100% punch", "..hidden", "with \"quotes\"",
    ])
    func awkwardNamesSave(name: String) {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        #expect(fixture.store.save(name: name, edits: [.adjust(Adjustments(exposure: 1))]))
        #expect(fixture.store.recipes.map(\.name) == [name], "the name is preserved, only the file is sanitised")
    }

    @Test("A filename never starts with a dot, which would hide it")
    func fileNameNeverHidden() {
        #expect(RecipeStore.fileName(for: "..hidden").hasPrefix(".") == false)
        #expect(RecipeStore.fileName(for: "/").hasPrefix(".") == false)
    }

    // MARK: - Applying

    @Test("Applying a recipe reproduces the same image")
    func applyingReproducesTheImage() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        fixture.model.rotate(byDegreesClockwise: 90)
        fixture.model.setAdjustments(Adjustments(exposure: 1, saturation: 0))
        let target = TestSupport.allPixels(try #require(fixture.model.image))
        fixture.store.save(name: "Look", edits: fixture.model.recipeEdits)

        // Start again from the file, then apply the recipe.
        fixture.model.revert()
        fixture.model.applyRecipe(try #require(fixture.store.recipes.first))

        #expect(TestSupport.allPixels(try #require(fixture.model.image)) == target)
    }

    /// Replacing rather than appending is what makes the result predictable.
    @Test("Applying replaces the existing orientation rather than compounding it")
    func applyingReplacesOrientation() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        fixture.store.save(name: "Quarter turn", edits: [.rotate(degreesClockwise: 90)])

        // Already rotated by hand; applying the recipe must not make it 180°.
        fixture.model.rotate(byDegreesClockwise: 90)
        let onceRotated = TestSupport.allPixels(try #require(fixture.model.image))

        fixture.model.applyRecipe(try #require(fixture.store.recipes.first))

        #expect(TestSupport.allPixels(try #require(fixture.model.image)) == onceRotated)
        #expect(fixture.model.edits == [.rotate(degreesClockwise: 90)])
    }

    @Test("Applying keeps a crop that was already made")
    func applyingKeepsCrops() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        fixture.store.save(name: "Bright", edits: [.adjust(Adjustments(exposure: 1))])

        fixture.model.crop(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        fixture.model.applyRecipe(try #require(fixture.store.recipes.first))

        #expect(TestSupport.size(try #require(fixture.model.image)) == (width: 2, height: 2), "still cropped")
        #expect(fixture.model.adjustments.exposure == 1)
    }

    @Test("Applying a recipe is a single undo step")
    func applyingIsOneUndoStep() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        let original = TestSupport.allPixels(try #require(fixture.model.image))
        fixture.store.save(name: "Several", edits: [
            .rotate(degreesClockwise: 90), .flip(horizontal: true), .adjust(Adjustments(exposure: 1)),
        ])

        fixture.model.applyRecipe(try #require(fixture.store.recipes.first))
        #expect(fixture.model.edits.count == 3, "three edits applied")
        #expect(fixture.model.undoActionName == "Apply “Several”")

        fixture.model.undo()

        #expect(TestSupport.allPixels(try #require(fixture.model.image)) == original, "one undo takes back all three")
        #expect(fixture.model.canUndo == false)
    }

    /// Reported after v0.20.0 was built: rotate by hand, apply a recipe that rotates the
    /// same way, and ⌘Z had to be pressed twice. The apply landed on a history identical
    /// to the one already in force, but still recorded an undo step, so the first ⌘Z
    /// restored a state indistinguishable from the current one.
    @Test("Applying a recipe that changes nothing costs no undo step")
    func applyingWithNoEffectIsNotUndoable() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        let original = TestSupport.allPixels(try #require(fixture.model.image))
        fixture.store.save(name: "Quarter turn", edits: [.rotate(degreesClockwise: 90)])

        fixture.model.rotate(byDegreesClockwise: 90)
        #expect(fixture.model.undoActionName == "Rotate")

        fixture.model.applyRecipe(try #require(fixture.store.recipes.first))

        #expect(fixture.model.undoActionName == "Rotate", "the apply added no step of its own")

        fixture.model.undo()

        #expect(
            TestSupport.allPixels(try #require(fixture.model.image)) == original,
            "a single undo returns to the unedited image"
        )
        #expect(fixture.model.canUndo == false)
    }

    @Test("Re-applying the same recipe twice costs one undo step")
    func reapplyingIsNotUndoableTwice() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        let original = TestSupport.allPixels(try #require(fixture.model.image))
        fixture.store.save(name: "Look", edits: [.adjust(Adjustments(exposure: 1))])
        let recipe = try #require(fixture.store.recipes.first)

        fixture.model.applyRecipe(recipe)
        fixture.model.applyRecipe(recipe)

        fixture.model.undo()

        #expect(TestSupport.allPixels(try #require(fixture.model.image)) == original)
        #expect(fixture.model.canUndo == false)
    }

    @Test("Setting the adjustments already in force costs no undo step")
    func settingSameAdjustmentsIsNotUndoable() {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }

        fixture.model.setAdjustments(Adjustments(exposure: 1))
        #expect(fixture.model.undoActionName == "Adjust")

        fixture.model.setAdjustments(Adjustments(exposure: 1))

        fixture.model.undo()
        #expect(fixture.model.adjustments.isNeutral, "one undo clears the adjustment")
        #expect(fixture.model.canUndo == false)
    }

    @Test("An applied recipe counts as unsaved work")
    func applyingCountsAsUnsaved() throws {
        let fixture = makeFixture()
        defer { TestSupport.remove(fixture.directory) }
        fixture.store.save(name: "Bright", edits: [.adjust(Adjustments(exposure: 1))])

        fixture.model.applyRecipe(try #require(fixture.store.recipes.first))

        #expect(fixture.model.hasUnsavedEdits)
        #expect(fixture.model.canRevert)
    }

    // MARK: - Format tolerance

    /// Adding a slider must not make every recipe saved before it unreadable.
    @Test("A recipe saved before an adjustment existed still loads")
    func olderRecipeStillLoads() throws {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Hand-written as an older version would have saved it: only two adjustments.
        let json = """
        {
          "formatVersion": 1,
          "name": "Old",
          "created": 0,
          "edits": [{"adjust":{"_0":{"exposure":1.5,"contrast":1.2}}}]
        }
        """
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("Old.json"))

        let store = RecipeStore(directory: directory)

        #expect(store.recipes.map(\.name) == ["Old"])
        let adjustments = try #require(store.recipes.first?.edits.compactMap { edit -> Adjustments? in
            if case .adjust(let value) = edit { return value }
            return nil
        }.first)
        #expect(adjustments.exposure == 1.5)
        #expect(adjustments.contrast == 1.2)
        #expect(adjustments.vibrance == 0, "an adjustment the file never held reads as neutral")
        #expect(adjustments.highlights == 1)
    }

    @Test("An unreadable file is skipped rather than hiding the others")
    func unreadableFileSkipped() throws {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let store = RecipeStore(directory: directory)
        store.save(name: "Good", edits: [.adjust(Adjustments(exposure: 1))])

        try "not json at all".data(using: .utf8)!
            .write(to: directory.appendingPathComponent("Broken.json"))
        store.reload()

        #expect(store.recipes.map(\.name) == ["Good"])
    }

    @Test("Neutral values are the initialiser's defaults")
    func neutralValuesAreTheDefaults() {
        #expect(Adjustments() == Adjustments.neutral)
        #expect(Adjustments.neutral.exposure == 0)
        #expect(Adjustments.neutral.highlights == 1)
        #expect(Adjustments.neutral.shadows == 0)
        #expect(Adjustments.neutral.contrast == 1)
        #expect(Adjustments.neutral.saturation == 1)
        #expect(Adjustments.neutral.vibrance == 0)
        #expect(Adjustments.neutral.hue == 0)
    }
}

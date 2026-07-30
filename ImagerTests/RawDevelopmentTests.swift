import AppKit
import Foundation
import Testing
@testable import Imager

/// Covers RAW development against a real file.
///
/// The RAW file is gitignored - a NEF is tens of megabytes - so these are skipped when it is
/// absent rather than failing a fresh clone. Behaviour varies by camera and decoder, so there
/// is no substitute for a real one: see `data/README.md`.
@Suite("RAW development")
struct RawDevelopmentTests {

    static let rawURL = URL(fileURLWithPath: "/Volumes/u/src/ai/imager/data/DSC_4927.NEF")
    static var hasRawFile: Bool { FileManager.default.fileExists(atPath: rawURL.path) }

    // MARK: - Detection, which needs no file

    @Test("RAW extensions are recognised", arguments: ["nef", "NEF", "cr2", "cr3", "arw", "dng", "raf"])
    func rawExtensionsRecognised(fileExtension: String) {
        let url = URL(fileURLWithPath: "/tmp/photo.\(fileExtension)")

        #expect(RawDeveloper.isRawFile(url))
    }

    @Test("Ordinary image formats are not RAW", arguments: ["png", "jpg", "jpeg", "tiff", "heic", "gif"])
    func ordinaryFormatsAreNotRaw(fileExtension: String) {
        let url = URL(fileURLWithPath: "/tmp/photo.\(fileExtension)")

        #expect(RawDeveloper.isRawFile(url) == false)
    }

    @Test("A non-RAW file gets no developer")
    func nonRawFileHasNoDeveloper() {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let png = TestSupport.writePNG(TestSupport.solidImage(width: 4, height: 4), named: "a.png", in: directory)

        #expect(RawDeveloper(url: png) == nil)
    }

    // MARK: - Against the real file

    @Test("The decoder opens the file and reports its native size", .enabled(if: hasRawFile))
    func opensTheFile() throws {
        let developer = try #require(RawDeveloper(url: Self.rawURL))

        #expect(developer.nativeSize.width > 0)
        #expect(developer.nativeSize.height > 0)
    }

    /// The point of storing the decoder's own reading: a RAW file has no fixed neutral, so
    /// Reset means going back to these rather than to zero.
    @Test("The file's defaults are the decoder's reading, not zeroes", .enabled(if: hasRawFile))
    func defaultsComeFromTheFile() throws {
        let developer = try #require(RawDeveloper(url: Self.rawURL))
        let defaults = developer.defaults

        #expect(defaults.temperature > 1000, "a real colour temperature in kelvin")
        #expect(defaults.temperature < 20000)
        #expect(defaults.boost >= 0 && defaults.boost <= 1)
        #expect(defaults.boostShadow >= 0 && defaults.boostShadow <= 1)
        #expect(defaults != RawSettings(), "the file's own reading, not the struct's placeholders")
    }

    @Test("Developing produces an image at full size", .enabled(if: hasRawFile))
    func developsAtFullSize() throws {
        let developer = try #require(RawDeveloper(url: Self.rawURL))

        let image = try #require(developer.develop(developer.defaults, preview: false))

        let size = TestSupport.size(image)
        #expect(size.width == Int(developer.nativeSize.width))
        #expect(size.height == Int(developer.nativeSize.height))
    }

    @Test("A preview develops smaller than full size", .enabled(if: hasRawFile))
    func previewIsSmaller() throws {
        let developer = try #require(RawDeveloper(url: Self.rawURL))

        let preview = try #require(developer.develop(developer.defaults, preview: true))

        #expect(TestSupport.size(preview).width < Int(developer.nativeSize.width))
    }

    @Test("Exposure changes the pixels", .enabled(if: hasRawFile))
    func exposureHasAnEffect() throws {
        let developer = try #require(RawDeveloper(url: Self.rawURL))
        let base = try #require(developer.develop(developer.defaults, preview: true))

        var brighter = developer.defaults
        brighter.exposure = developer.defaults.exposure + 1.5
        let lifted = try #require(developer.develop(brighter, preview: true))

        #expect(TestSupport.fingerprint(lifted) != TestSupport.fingerprint(base))
    }

    /// White balance is the thing that cannot be done properly after demosaicing.
    @Test("Temperature changes the pixels", .enabled(if: hasRawFile))
    func temperatureHasAnEffect() throws {
        let developer = try #require(RawDeveloper(url: Self.rawURL))
        let base = try #require(developer.develop(developer.defaults, preview: true))

        var warmer = developer.defaults
        warmer.temperature = developer.defaults.temperature + 2500
        let shifted = try #require(developer.develop(warmer, preview: true))

        #expect(TestSupport.fingerprint(shifted) != TestSupport.fingerprint(base))
    }

    @Test("Tint changes the pixels", .enabled(if: hasRawFile))
    func tintHasAnEffect() throws {
        let developer = try #require(RawDeveloper(url: Self.rawURL))
        let base = try #require(developer.develop(developer.defaults, preview: true))

        var tinted = developer.defaults
        tinted.tint = developer.defaults.tint + 40
        let shifted = try #require(developer.develop(tinted, preview: true))

        #expect(TestSupport.fingerprint(shifted) != TestSupport.fingerprint(base))
    }

    @Test("Boost changes the pixels", .enabled(if: hasRawFile))
    func boostHasAnEffect() throws {
        let developer = try #require(RawDeveloper(url: Self.rawURL))
        let base = try #require(developer.develop(developer.defaults, preview: true))

        var flat = developer.defaults
        flat.boost = 0
        let rendered = try #require(developer.develop(flat, preview: true))

        #expect(TestSupport.fingerprint(rendered) != TestSupport.fingerprint(base))
    }

    @Test("Developing the same settings twice gives the same pixels", .enabled(if: hasRawFile))
    func developingIsDeterministic() throws {
        let developer = try #require(RawDeveloper(url: Self.rawURL))

        let first = try #require(developer.develop(developer.defaults, preview: true))
        let second = try #require(developer.develop(developer.defaults, preview: true))

        #expect(TestSupport.fingerprint(first) == TestSupport.fingerprint(second))
    }

    // MARK: - In the model

    @MainActor
    private func makeModel() -> ImageModel {
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(recents: RecentFilesStore(defaults: suite), defaults: suite)
        model.load(from: Self.rawURL)
        return model
    }

    @Test("Opening a RAW file gives it development settings", .enabled(if: hasRawFile))
    @MainActor
    func openingRawGivesSettings() {
        let model = makeModel()

        #expect(model.isRaw)
        #expect(model.rawSettings != nil)
        #expect(model.rawSettings == model.rawDefaults, "as the decoder read the shot")
        #expect(model.hasUnsavedEdits == false, "opening it is not a change")
    }

    @Test("An ordinary image has no development settings", .enabled(if: hasRawFile))
    @MainActor
    func openingPngGivesNoSettings() {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let png = TestSupport.writePNG(TestSupport.solidImage(width: 4, height: 4), named: "a.png", in: directory)
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(recents: RecentFilesStore(defaults: suite), defaults: suite)
        model.load(from: png)

        #expect(model.isRaw == false)
        #expect(model.rawSettings == nil)
    }

    @Test("Developing counts as unsaved work", .enabled(if: hasRawFile))
    @MainActor
    func developingIsUnsavedWork() throws {
        let model = makeModel()
        var settings = try #require(model.rawSettings)
        settings.exposure += 1

        model.setRawSettings(settings)

        #expect(model.hasUnsavedEdits, "even with no edits in the history")
        #expect(model.edits.isEmpty)
    }

    /// The payoff from the snapshot-based undo: RAW settings ride along with the edit list,
    /// so development undoes like everything else without a second mechanism.
    @Test("Development undoes and redoes", .enabled(if: hasRawFile))
    @MainActor
    func developmentUndoesAndRedoes() throws {
        let model = makeModel()
        let original = try #require(model.rawSettings)
        var warmer = original
        warmer.temperature = original.temperature + 2000

        model.setRawSettings(warmer)
        #expect(model.rawSettings?.temperature == warmer.temperature)
        #expect(model.undoActionName == "Develop")

        model.undo()
        #expect(model.rawSettings == original)

        model.redo()
        #expect(model.rawSettings?.temperature == warmer.temperature)
    }

    @Test("A drag is one undo step", .enabled(if: hasRawFile))
    @MainActor
    func dragIsOneUndoStep() throws {
        let model = makeModel()
        let original = try #require(model.rawSettings)

        var settings = original
        settings.exposure = original.exposure + 0.1
        model.setRawSettings(settings, preview: true)
        for step in 2...10 {
            settings.exposure = original.exposure + Float(step) * 0.1
            model.setRawSettings(settings, continuingSession: true, preview: true)
        }
        model.commitRawDevelopment()

        model.undo()

        #expect(model.rawSettings == original, "ten ticks, one step")
        #expect(model.canUndo == false)
    }

    @Test("Reset returns to the decoder's own reading", .enabled(if: hasRawFile))
    @MainActor
    func resetReturnsToDefaults() throws {
        let model = makeModel()
        let defaults = try #require(model.rawDefaults)
        var settings = defaults
        settings.exposure += 2
        settings.temperature += 1500
        model.setRawSettings(settings)

        model.resetRawDevelopment()

        #expect(model.rawSettings == defaults, "not zeroes - what the decoder chose")
    }

    @Test("Reverting also returns the development", .enabled(if: hasRawFile))
    @MainActor
    func revertReturnsDevelopment() throws {
        let model = makeModel()
        let defaults = try #require(model.rawDefaults)
        var settings = defaults
        settings.exposure += 1
        model.setRawSettings(settings)
        model.rotate(byDegreesClockwise: 90)

        model.revert()

        #expect(model.rawSettings == defaults)
        #expect(model.edits.isEmpty)
    }

    // MARK: - Recipes

    @Test("A recipe carries development, and applying it develops", .enabled(if: hasRawFile))
    @MainActor
    func recipeCarriesDevelopment() throws {
        let model = makeModel()
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let store = RecipeStore(directory: directory)

        let defaults = try #require(model.rawDefaults)
        var settings = defaults
        settings.temperature = defaults.temperature + 2000
        model.setRawSettings(settings)

        #expect(model.recipeRawSettings != nil, "development differing from the file's own is worth saving")
        store.save(name: "Warmer", edits: model.recipeEdits, rawSettings: model.recipeRawSettings)

        model.resetRawDevelopment()
        model.applyRecipe(try #require(store.recipes.first))

        #expect(model.rawSettings?.temperature == settings.temperature)
    }

    /// Otherwise saving a recipe from an untouched RAW would pin every other shot to this
    /// one's white balance.
    @Test("An untouched RAW contributes no development to a recipe", .enabled(if: hasRawFile))
    @MainActor
    func untouchedRawSavesNoDevelopment() {
        let model = makeModel()

        #expect(model.recipeRawSettings == nil)
        #expect(model.canSaveRecipe == false)
    }

    @Test("Applying a RAW recipe to an ordinary image ignores the development", .enabled(if: hasRawFile))
    @MainActor
    func rawRecipeOnOrdinaryImageIgnoresDevelopment() throws {
        let directory = TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }
        let store = RecipeStore(directory: directory)
        store.save(
            name: "RAW look",
            edits: [.rotate(degreesClockwise: 90)],
            rawSettings: RawSettings(exposure: 1, temperature: 8000)
        )

        let png = TestSupport.writePNG(TestSupport.solidImage(width: 4, height: 2), named: "a.png", in: directory)
        let suite = UserDefaults(suiteName: "ImagerTests-\(UUID().uuidString)")!
        let model = ImageModel(recents: RecentFilesStore(defaults: suite), defaults: suite)
        model.load(from: png)

        model.applyRecipe(try #require(store.recipes.first))

        #expect(model.rawSettings == nil, "nothing to develop")
        #expect(model.edits == [.rotate(degreesClockwise: 90)], "but the edits still apply")
        #expect(TestSupport.size(try #require(model.image)) == (width: 2, height: 4))
    }

    /// The measurement the design rests on: a held instance renders parameter changes in single
    /// digit milliseconds, where a fresh one costs 86 ms at best.
    @Test("A held instance develops previews quickly", .enabled(if: hasRawFile))
    func heldInstanceIsFast() throws {
        let developer = try #require(RawDeveloper(url: Self.rawURL))
        _ = developer.develop(developer.defaults, preview: true)   // pay the decode once

        var settings = developer.defaults
        let start = ProcessInfo.processInfo.systemUptime
        for step in 1...5 {
            settings.exposure = developer.defaults.exposure + Float(step) * 0.1
            _ = developer.develop(settings, preview: true)
        }
        let averageMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 5

        #expect(averageMilliseconds < 60, "measured around 7 ms; 60 leaves room for a busy machine")
    }
}

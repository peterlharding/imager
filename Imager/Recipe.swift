import Foundation
import Observation

/// A named set of edits that can be applied to another image.
///
/// Holds the general edit list rather than just an orientation and an `Adjustments`,
/// which costs nothing and leaves room for future edit types. What a recipe means in
/// practice is narrower: only the last adjustment applies and rotations compose, so the
/// effective content is an orientation plus one set of adjustments.
struct Recipe: Identifiable, Equatable, Codable {
    /// Bumped if the stored shape ever changes in a way older readers cannot handle.
    static let currentFormatVersion = 1

    var formatVersion = Recipe.currentFormatVersion
    var name: String
    var created: Date
    var edits: [ImageEdit]

    /// How to develop a RAW file, when the recipe was made from one. Ignored when applied to
    /// an image that is not RAW, so one recipe can serve both.
    var rawSettings: RawSettings?

    var id: String { name }

    init(name: String, edits: [ImageEdit], rawSettings: RawSettings? = nil, created: Date = Date()) {
        self.name = name
        self.edits = edits
        self.rawSettings = rawSettings
        self.created = created
    }
}

/// Saved recipes, one JSON file each.
@Observable
final class RecipeStore {

    private(set) var recipes: [Recipe] = []

    /// Set aside for reporting a save or delete that failed.
    var errorMessage: String?

    @ObservationIgnored private let directory: URL

    /// `directory` is injected so tests write to a temporary folder rather than the
    /// user's real recipe collection.
    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
        reload()
    }

    /// Inside the sandbox container, so it needs no permission from the user.
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Imager/Recipes", isDirectory: true)
    }

    // MARK: - Reading

    func reload() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []

        let decoder = JSONDecoder()
        recipes = contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                // A file that cannot be read is skipped rather than failing the lot:
                // one bad recipe should not hide the rest.
                return try? decoder.decode(Recipe.self, from: data)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Writing

    /// Saves under `name`, replacing any recipe already using it.
    @discardableResult
    func save(name: String, edits: [ImageEdit], rawSettings: RawSettings? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "A recipe needs a name."
            return false
        }
        guard !edits.isEmpty || rawSettings != nil else {
            errorMessage = "There are no changes to save."
            return false
        }

        let recipe = Recipe(name: trimmed, edits: edits, rawSettings: rawSettings)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(recipe).write(to: fileURL(for: trimmed), options: .atomic)
        } catch {
            errorMessage = "Couldn't save the recipe. \(error.localizedDescription)"
            return false
        }
        reload()
        return true
    }

    @discardableResult
    func delete(_ recipe: Recipe) -> Bool {
        do {
            try FileManager.default.removeItem(at: fileURL(for: recipe.name))
        } catch {
            errorMessage = "Couldn't delete “\(recipe.name)”. \(error.localizedDescription)"
            return false
        }
        reload()
        return true
    }

    // MARK: - Naming

    private func fileURL(for name: String) -> URL {
        directory.appendingPathComponent(Self.fileName(for: name))
    }

    /// A recipe's name becomes its filename, so characters a file name cannot hold are
    /// replaced rather than allowed to make the save fail.
    static func fileName(for name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        var safe = name.components(separatedBy: forbidden).joined(separator: "-")
        safe = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        // A leading dot would make the file hidden, and be skipped when reloading.
        while safe.hasPrefix(".") { safe = String(safe.dropFirst()) }
        if safe.isEmpty { safe = "Recipe" }
        return safe + ".json"
    }
}

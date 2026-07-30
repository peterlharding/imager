import SwiftUI
import UniformTypeIdentifiers

/// Sets up and runs a batch over the folder being browsed.
struct BatchSheet: View {
    let model: ImageModel
    let recipes: RecipeStore

    @State private var runner = BatchRunner()
    @State private var source: Source = .currentEdits
    @State private var format: BatchFormat = .sameAsSource
    @State private var destination: URL?
    @State private var destinationProblem: String?
    @Environment(\.dismiss) private var dismiss

    /// What to apply: the edits on screen, or a saved recipe.
    private enum Source: Hashable {
        case currentEdits
        case recipe(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Process Folder")
                .font(.headline)

            if let summary = runner.summary {
                summaryView(summary)
            } else if runner.isRunning {
                progressView
            } else {
                setupView
            }
        }
        .padding(20)
        .frame(width: 460)
        .onDisappear { runner.cancel() }
    }

    // MARK: - Setting up

    @ViewBuilder private var setupView: some View {
        Text("^[\(model.folderImages.count) image](inflect: true) in “\(folderName)”. "
             + "Originals are never changed.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Form {
            Picker("Apply", selection: $source) {
                Text(currentEditsLabel).tag(Source.currentEdits)
                if !recipes.recipes.isEmpty {
                    Divider()
                    ForEach(recipes.recipes) { recipe in
                        Text(recipe.name).tag(Source.recipe(recipe.name))
                    }
                }
            }

            Picker("Format", selection: $format) {
                ForEach(BatchFormat.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            LabeledContent("Destination") {
                HStack {
                    Text(destination?.lastPathComponent ?? "None chosen")
                        .foregroundStyle(destination == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseDestination() }
                }
            }
        }
        .formStyle(.grouped)

        if let destinationProblem {
            Label(destinationProblem, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if editsToApply.isEmpty {
            Label("There are no changes to apply.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Start") { start() }
                .keyboardShortcut(.defaultAction)
                .disabled(destination == nil || editsToApply.isEmpty)
        }
    }

    // MARK: - Running

    @ViewBuilder private var progressView: some View {
        ProgressView(value: runner.progress) {
            Text("Processing \(runner.completed + 1) of \(runner.total)…")
        }
        Text(runner.currentName ?? " ")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

        HStack {
            Spacer()
            Button("Cancel") { runner.cancel() }
        }
    }

    // MARK: - Finished

    @ViewBuilder private func summaryView(_ summary: BatchRunner.Summary) -> some View {
        let headline = summary.wasCancelled
            ? "Stopped after ^[\(summary.written) image](inflect: true)."
            : "Wrote ^[\(summary.written) image](inflect: true)."
        Text(headline)

        if !summary.failures.isEmpty {
            Text("^[\(summary.failures.count) file](inflect: true) could not be processed:")
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(summary.failures) { failure in
                        Text("\(failure.name) — \(failure.message)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 120)
        }

        HStack {
            if let destination {
                Button("Show in Finder") { FileActions.showInFinder(destination) }
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Pieces

    private var folderName: String {
        model.folderURL?.lastPathComponent ?? "this folder"
    }

    private var currentEditsLabel: String {
        model.recipeEdits.isEmpty ? "Changes to this image (none)" : "Changes to this image"
    }

    private var editsToApply: [ImageEdit] {
        switch source {
        case .currentEdits:
            model.recipeEdits
        case .recipe(let name):
            recipes.recipes.first { $0.name == name }?.edits ?? []
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to write the processed images"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let chosen = panel.url else { return }

        if let folder = model.folderURL,
           !BatchProcessor.isValidDestination(chosen, sourceFolder: folder) {
            destination = nil
            destinationProblem = "Choose a folder other than the one being processed, "
                + "so the originals cannot be touched."
            return
        }
        destination = chosen
        destinationProblem = nil
    }

    private func start() {
        guard let destination else { return }
        runner.start(
            sources: model.folderImages,
            edits: editsToApply,
            format: format,
            destination: destination
        )
    }
}

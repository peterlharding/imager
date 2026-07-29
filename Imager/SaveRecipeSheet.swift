import SwiftUI

/// Asks for a name when saving a recipe.
///
/// A sheet rather than an alert because SwiftUI has no text-entry alert on macOS.
struct SaveRecipeSheet: View {
    let existingNames: [String]
    let onSave: (String) -> Void

    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var replacesExisting: Bool { existingNames.contains(trimmed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Recipe")
                .font(.headline)

            Text("Saves the rotation, flips and adjustments made to this image. "
                 + "Crops are left out, because they belong to this image's dimensions.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }

            if replacesExisting {
                Label("A recipe called “\(trimmed)” will be replaced.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(replacesExisting ? "Replace" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}

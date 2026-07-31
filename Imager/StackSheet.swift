import SwiftUI

/// Asks how close together frames must be taken to belong in the same stack, then groups
/// the folder.
///
/// The threshold is a judgement about how the photographs were made - a burst is under a
/// second apart, a bracket a few seconds, a set of tries at one composition perhaps half a
/// minute - so it is asked rather than assumed.
struct StackSheet: View {
    let model: ImageModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(StackSheet.intervalKey) private var interval = StackSheet.defaultInterval

    static let intervalKey = "stackInterval"
    static let defaultInterval = 2.0

    /// Presets rather than a free number: the useful values are few and named by how the
    /// frames were shot.
    private static let choices: [(seconds: Double, label: String)] = [
        (0.5, "Burst - half a second"),
        (2, "Burst - 2 seconds"),
        (5, "Bracket - 5 seconds"),
        (15, "Same shot - 15 seconds"),
        (60, "Same shot - a minute"),
    ]

    /// Capture times for the folder, read once when the sheet appears.
    ///
    /// Not a computed property: reading EXIF costs about 18 ms a frame on RAW, so a folder of 500
    /// takes nine seconds. Re-reading on every redraw - and the summary and the button's enabled
    /// state each ask - would hang the sheet outright on a real shoot.
    @State private var dated: [(name: String, date: Date?)]?

    /// How the folder would group at the chosen threshold. Pure once the times are in, so
    /// changing the threshold is instant.
    private var preview: (stacks: Int, frames: Int) {
        guard let dated else { return (0, 0) }
        let grouped = Stacks.autoStack(dated: dated, within: interval)
        return (grouped.count, grouped.reduce(0) { $0 + $1.count })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stack Photos")
                .font(.headline)

            Text("Frames taken within this of the one before them are grouped together.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Taken within", selection: $interval) {
                ForEach(Self.choices, id: \.seconds) { choice in
                    Text(choice.label).tag(choice.seconds)
                }
            }
            .frame(maxWidth: 320)

            summary
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Stack") {
                    if let dated { model.autoStack(dated: dated, within: interval) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview.stacks == 0)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
        .task {
            // A folder of RAWs takes seconds to read, so it happens off the main thread and the
            // sheet says what it is doing meanwhile.
            dated = await Stacks.captureDates(of: model.folderImages)
        }
    }

    @ViewBuilder private var summary: some View {
        if dated == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading capture times…")
            }
        } else {
            let result = preview
            if result.stacks == 0 {
                // Almost always because the files carry no capture time - scans, screenshots,
                // anything re-saved by a tool that drops EXIF.
                Text("Nothing to stack: no frames were taken this close together.")
            } else {
                Text("^[\(result.stacks) stack](inflect: true) "
                     + "from ^[\(result.frames) frame](inflect: true). "
                     + "Any stacks you have now are replaced.")
            }
        }
    }
}

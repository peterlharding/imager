import SwiftUI

/// Trailing inspector panel that lists metadata for the current image.
struct InfoInspector: View {
    let info: ImageInfo?
    let url: URL?

    var body: some View {
        if let info, !info.isEmpty {
            List {
                ForEach(info.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            LabeledContent(item.label) {
                                Text(item.value)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .safeAreaInset(edge: .bottom) {
                if let url {
                    HStack {
                        Button {
                            FileActions.showInFinder(url)
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        .help("Show in Finder")
                        Spacer()
                        Button {
                            FileActions.copyPath(url)
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.clipboard")
                        }
                        .help("Copy path to clipboard")
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
        } else {
            ContentUnavailableView {
                Label("No Image Info", systemImage: "info.circle")
            } description: {
                Text("Open an image to see its details.")
            }
        }
    }
}

/// Lets a scene-level menu command drive the inspector's visibility.
struct InspectorVisibilityKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

/// Lets a scene-level menu command drive the thumbnail sidebar's visibility.
struct SidebarVisibilityKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

/// Lets the Save Recipe menu command raise the naming sheet, which only a view can present.
struct SaveRecipeSheetKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

/// Lets the Process Folder menu command raise the batch sheet.
struct BatchSheetKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

/// Lets the Stack Photos menu command raise the stacking sheet.
struct StackSheetKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var inspectorVisible: Binding<Bool>? {
        get { self[InspectorVisibilityKey.self] }
        set { self[InspectorVisibilityKey.self] = newValue }
    }

    var saveRecipeSheetVisible: Binding<Bool>? {
        get { self[SaveRecipeSheetKey.self] }
        set { self[SaveRecipeSheetKey.self] = newValue }
    }

    var batchSheetVisible: Binding<Bool>? {
        get { self[BatchSheetKey.self] }
        set { self[BatchSheetKey.self] = newValue }
    }

    var stackSheetVisible: Binding<Bool>? {
        get { self[StackSheetKey.self] }
        set { self[StackSheetKey.self] = newValue }
    }

    var sidebarVisible: Binding<Bool>? {
        get { self[SidebarVisibilityKey.self] }
        set { self[SidebarVisibilityKey.self] = newValue }
    }
}

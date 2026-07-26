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

extension FocusedValues {
    var inspectorVisible: Binding<Bool>? {
        get { self[InspectorVisibilityKey.self] }
        set { self[InspectorVisibilityKey.self] = newValue }
    }

    var sidebarVisible: Binding<Bool>? {
        get { self[SidebarVisibilityKey.self] }
        set { self[SidebarVisibilityKey.self] = newValue }
    }
}

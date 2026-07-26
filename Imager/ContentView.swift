import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(ImageModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var showInfo = false
    @State private var showSidebar = false
    @State private var zoom = ZoomController()

    var body: some View {
        Group {
            if model.canBrowse {
                NavigationSplitView(columnVisibility: columnVisibility) {
                    thumbnailSidebar
                } detail: {
                    mainArea
                }
            } else {
                mainArea
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle(model.url?.lastPathComponent ?? "Imager")
        .inspector(isPresented: $showInfo) {
            InfoInspector(info: model.info, url: model.url)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 420)
        }
        .focusedSceneValue(\.inspectorVisible, $showInfo)
        .focusedSceneValue(\.sidebarVisible, $showSidebar)
        .focusedSceneValue(\.zoomController, zoom)
        .onAppear { model.setWindowOpener { openWindow(id: "main") } }
        .onChange(of: model.folderURL) { showSidebar = model.canBrowse }
        .toolbar {
            if model.canBrowse {
                ToolbarItem(placement: .navigation) {
                    Button {
                        showSidebar.toggle()
                    } label: {
                        Label("Thumbnails", systemImage: "sidebar.squares.left")
                    }
                    .help("Show or hide thumbnails")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let url = ImageOpener.run() {
                        model.load(from: url)
                    }
                } label: {
                    Label("Open", systemImage: "photo")
                }
            }
            if model.image != nil {
                ToolbarItem(placement: .principal) {
                    Picker("Tool", selection: toolBinding) {
                        Image(systemName: "hand.draw").tag(ImageTool.pan)
                        Image(systemName: "crop").tag(ImageTool.select)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Pan or Select tool")
                }
            }
            if zoom.canCrop {
                ToolbarItem(placement: .primaryAction) {
                    Button { cropSelection() } label: {
                        Label("Crop", systemImage: "crop")
                    }
                    .help("Crop to selection (⌘K)")
                }
            }
            if model.image != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { zoom.zoomOut() } label: {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    .help("Zoom out (⌘-)")

                    Button { zoom.zoomToFit() } label: {
                        Text("\(Int((zoom.magnification * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(minWidth: 44)
                    }
                    .help("Zoom to fit (⌘0)")

                    Button { zoom.zoomIn() } label: {
                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                    }
                    .help("Zoom in (⌘=)")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInfo.toggle()
                } label: {
                    Label("Image Info", systemImage: "info.circle")
                }
                .help("Show image info")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadFirstImage(from: providers)
        }
        .alert(
            "Unable to Open Image",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Panes

    @ViewBuilder private var mainArea: some View {
        if let image = model.image {
            ZoomableImageView(image: image, controller: zoom)
                .background(.background)
        } else {
            EmptyState()
        }
    }

    private var thumbnailSidebar: some View {
        List(selection: thumbnailSelection) {
            ForEach(model.folderImages, id: \.self) { url in
                ThumbnailRow(url: url)
                    .tag(url)
            }
        }
        .navigationSplitViewColumnWidth(min: 150, ideal: 190, max: 300)
    }

    // MARK: - Bindings

    /// Binding for the Pan/Select tool picker.
    private var toolBinding: Binding<ImageTool> {
        Binding(get: { zoom.tool }, set: { zoom.tool = $0 })
    }

    /// Crops the current image to the active selection, then clears it.
    private func cropSelection() {
        guard let selection = zoom.selection else { return }
        model.crop(to: selection)
        zoom.selection = nil
    }

    /// Maps the split view's column visibility to a simple shown/hidden flag.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { showSidebar ? .all : .detailOnly },
            set: { showSidebar = ($0 != .detailOnly) }
        )
    }

    /// Bridges the thumbnail List selection (by URL) to the model's index-based selection.
    private var thumbnailSelection: Binding<URL?> {
        Binding(
            get: {
                guard let i = model.selectionIndex, model.folderImages.indices.contains(i) else { return nil }
                return model.folderImages[i]
            },
            set: { url in
                if let url, let i = model.folderImages.firstIndex(of: url) {
                    model.select(i)
                }
            }
        )
    }

    /// Opens the first dropped URL - an image file, or a folder to browse.
    private func loadFirstImage(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { model.open(url) }
        }
        return true
    }
}

/// A thumbnail + filename row in the folder sidebar.
private struct ThumbnailRow: View {
    let url: URL
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            thumbnailImage
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .task(id: url) {
            thumbnail = await ThumbnailProvider.shared.thumbnail(for: url)
        }
    }

    @ViewBuilder private var thumbnailImage: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

/// Placeholder shown before any image is opened.
private struct EmptyState: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Image Open", systemImage: "photo")
        } description: {
            Text("Open an image with ⌘O or a folder with ⇧⌘O, use the toolbar, or drag a file here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

#Preview {
    ContentView()
        .environment(ImageModel())
}

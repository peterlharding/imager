import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(ImageModel.self) private var model
    @Environment(Slideshow.self) private var slideshow
    @Environment(RecipeStore.self) private var recipes
    @Environment(\.openWindow) private var openWindow
    @State private var showInfo = false
    @State private var showSaveRecipe = false
    @State private var showBatch = false
    @State private var showSidebar = false
    @State private var showRotate = false
    @State private var zoom = ZoomController()

    /// Sidebar and inspector visibility from before a slideshow hid them, so
    /// stopping puts the window back the way the user had it.
    @State private var chromeBeforeSlideshow: (sidebar: Bool, info: Bool)?

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
            InspectorPanes(model: model)
                .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
        }
        .focusedSceneValue(\.inspectorVisible, $showInfo)
        // Extracted: with the sheets inline the modifier chain grew past what the type
        // checker will resolve in reasonable time.
        .modifier(SheetPresentation(
            model: model,
            recipes: recipes,
            showSaveRecipe: $showSaveRecipe,
            showBatch: $showBatch
        ))
        .focusedSceneValue(\.sidebarVisible, $showSidebar)
        .focusedSceneValue(\.zoomController, zoom)
        .onAppear { model.setWindowOpener { openWindow(id: "main") } }
        .onChange(of: model.folderURL) {
            slideshow.stop()
            showSidebar = model.canBrowse
        }
        // Editing during a show stops it, so the timer can never walk away from
        // unsaved work or raise the discard confirmation mid-slideshow.
        .onChange(of: model.hasUnsavedEdits) { _, unsaved in
            if unsaved { slideshow.stop() }
        }
        .onChange(of: slideshow.isRunning) { _, running in
            running ? enterSlideshowMode() : leaveSlideshowMode()
        }
        // Leaving full screen (Escape, or the green button) also ends the show.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            slideshow.stop()
        }
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
            if model.image != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showRotate.toggle()
                    } label: {
                        Label("Rotate", systemImage: "crop.rotate")
                    }
                    .help("Rotate or flip")
                    .popover(isPresented: $showRotate, arrowEdge: .bottom) {
                        RotatePopover(model: model)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    } label: {
                        Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Enter full screen")
                }
            }
            if slideshow.canStart {
                ToolbarItem(placement: .primaryAction) {
                    Button { slideshow.toggle() } label: {
                        Label(
                            slideshow.isRunning ? "Stop Slideshow" : "Slideshow",
                            systemImage: slideshow.isRunning ? "stop.fill" : "play.fill"
                        )
                    }
                    .help(slideshow.isRunning ? "Stop the slideshow (⇧⌘F)" : "Start a slideshow (⇧⌘F)")
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
        .alert(
            "Discard your changes to “\(model.pendingDiscard?.fileName ?? "")”?",
            isPresented: Binding(
                get: { model.pendingDiscard != nil },
                set: { if !$0 { model.resolveDiscard(confirmed: false) } }
            )
        ) {
            Button("Discard Changes", role: .destructive) { model.resolveDiscard(confirmed: true) }
            Button("Cancel", role: .cancel) { model.resolveDiscard(confirmed: false) }
        } message: {
            Text("Your edits haven't been saved. Save a copy with File ▸ Save As… to keep them.")
        }
    }

    // MARK: - Panes

    @ViewBuilder private var mainArea: some View {
        if let image = model.image {
            ZoomableImageView(image: image, controller: zoom)
                .background { BackgroundFill() }
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

    // MARK: - Slideshow presentation

    /// Clears the window down to just the image and goes full screen.
    private func enterSlideshowMode() {
        chromeBeforeSlideshow = (sidebar: showSidebar, info: showInfo)
        showSidebar = false
        showInfo = false
        guard let window = NSApp.keyWindow, !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }

    /// Restores the chrome the user had, and leaves full screen if we entered it.
    private func leaveSlideshowMode() {
        if let chrome = chromeBeforeSlideshow {
            showSidebar = chrome.sidebar
            showInfo = chrome.info
            chromeBeforeSlideshow = nil
        }
        guard let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
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

/// The sheets raised from menu commands, and the focused values that let those commands
/// reach them. Kept out of `ContentView`'s own chain to keep it type-checkable.
private struct SheetPresentation: ViewModifier {
    let model: ImageModel
    let recipes: RecipeStore
    @Binding var showSaveRecipe: Bool
    @Binding var showBatch: Bool

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.saveRecipeSheetVisible, $showSaveRecipe)
            .sheet(isPresented: $showSaveRecipe) {
                SaveRecipeSheet(existingNames: recipes.recipes.map(\.name)) { name in
                    recipes.save(name: name, edits: model.recipeEdits)
                }
            }
            .focusedSceneValue(\.batchSheetVisible, $showBatch)
            .sheet(isPresented: $showBatch) {
                BatchSheet(model: model, recipes: recipes)
            }
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
    let model = ImageModel()
    ContentView()
        .environment(model)
        .environment(Slideshow(model: model))
}

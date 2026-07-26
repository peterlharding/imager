import SwiftUI

/// Handles image files opened from Finder ("Open With…") or `open -a`, routing
/// them through the same load path as the in-app open command, and keeps the
/// app alive / reopens a window under the single-window `Window` scene.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var sharedModel: ImageModel?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        AppDelegate.sharedModel?.open(url)
    }

    // A `Window` scene quits the app when its window closes; keep running so a
    // later open can bring a window back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Reopen the window when the Dock icon is clicked with no window showing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppDelegate.sharedModel?.ensureWindow() }
        return true
    }
}

@main
struct ImagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: ImageModel

    init() {
        // The model and the Open Recent menu share one store.
        let model = ImageModel(recents: RecentFilesStore())
        _model = State(initialValue: model)
        AppDelegate.sharedModel = model
    }

    var body: some Scene {
        Window("Imager", id: "main") {
            ContentView()
                .environment(model)
        }
        .commands {
            AppCommands(model: model)
        }
    }
}

/// File and View menu commands. Lives in a `Commands` type so it can read
/// `@Environment(\.openWindow)` from a scene-level context that stays valid
/// even after the window has been closed.
private struct AppCommands: Commands {
    let model: ImageModel
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.inspectorVisible) private var inspectorVisible
    @FocusedValue(\.sidebarVisible) private var sidebarVisible
    @FocusedValue(\.zoomController) private var zoom

    var body: some Commands {
        // Replace the default "New" item with an "Open…" command (⌘O).
        CommandGroup(replacing: .newItem) {
            Button("Open…") {
                if let url = ImageOpener.run() {
                    model.setWindowOpener { openWindow(id: "main") }
                    model.load(from: url)
                }
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Folder…") {
                if let url = ImageOpener.runFolder() {
                    model.setWindowOpener { openWindow(id: "main") }
                    model.openFolder(url)
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Menu("Open Recent") {
                ForEach(model.recents.items) { item in
                    Button(item.url.lastPathComponent) {
                        model.setWindowOpener { openWindow(id: "main") }
                        model.openRecent(item)
                    }
                }
                if !model.recents.items.isEmpty {
                    Divider()
                    Button("Clear Menu") {
                        model.recents.clear()
                    }
                }
            }
            .disabled(model.recents.items.isEmpty)
        }
        CommandGroup(after: .sidebar) {
            Button(sidebarVisible?.wrappedValue == true ? "Hide Thumbnails" : "Show Thumbnails") {
                sidebarVisible?.wrappedValue.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(sidebarVisible == nil || !model.canBrowse)

            Button(inspectorVisible?.wrappedValue == true ? "Hide Image Info" : "Show Image Info") {
                inspectorVisible?.wrappedValue.toggle()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(inspectorVisible == nil)

            Divider()

            Button("Previous Image") { model.showPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!model.canBrowse)

            Button("Next Image") { model.showNext() }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!model.canBrowse)

            Divider()

            Button("Zoom In") { zoom?.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(zoomDisabled)

            Button("Zoom Out") { zoom?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(zoomDisabled)

            Button("Zoom to Fit") { zoom?.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(zoomDisabled)

            Button("Actual Size") { zoom?.actualSize() }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(zoomDisabled)
        }
        CommandMenu("Image") {
            Button("Crop to Selection") {
                if let selection = zoom?.selection {
                    model.crop(to: selection)
                    zoom?.selection = nil
                }
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(zoom?.canCrop != true)

            Button("Revert to Original") { model.revert() }
                .disabled(!model.canRevert)

            Divider()

            Button("Export…") {
                guard let image = model.image else { return }
                let base = model.url?.deletingPathExtension().lastPathComponent ?? "Image"
                if let error = ImageExporter.run(image: image, suggestedName: "\(base)-export.png") {
                    model.errorMessage = error
                }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(model.image == nil)
        }
    }

    private var zoomDisabled: Bool {
        zoom == nil || model.image == nil
    }
}

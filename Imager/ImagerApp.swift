import SwiftUI
import UniformTypeIdentifiers

/// Handles image files opened from Finder ("Open With…") or `open -a`, routing
/// them through the same load path as the in-app open command, and keeps the
/// app alive / reopens a window under the single-window `Window` scene.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var sharedModel: ImageModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Serves the "Open in Imager" entry declared under NSServices in Info.plist.
        NSApp.servicesProvider = self
        // Services are cached by the system; ask it to re-read ours.
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        AppDelegate.sharedModel?.open(url)
    }

    /// Handles the "Open in Imager" service. The selector name must match the
    /// `NSMessage` value in Info.plist, and the signature is fixed by AppKit.
    @objc func openInImager(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let url = Self.fileURL(from: pasteboard) else {
            error.pointee = "No file or folder was provided." as NSString
            return
        }
        AppDelegate.sharedModel?.open(url)
    }

    /// The first file URL on a pasteboard, which is what a Finder service delivers.
    static func fileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
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

    // Don't let quitting silently throw away edits that were never saved. The alert is
    // presented by the window, so answer later once the user has chosen.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = AppDelegate.sharedModel, model.hasUnsavedEdits else { return .terminateNow }
        return model.requestQuitConfirmation() ? .terminateLater : .terminateCancel
    }
}

@main
struct ImagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: ImageModel
    @State private var slideshow: Slideshow

    init() {
        // The model and the Open Recent menu share one store.
        let model = ImageModel(recents: RecentFilesStore())
        _model = State(initialValue: model)
        _slideshow = State(initialValue: Slideshow(model: model))
        AppDelegate.sharedModel = model
    }

    var body: some Scene {
        Window("Imager", id: "main") {
            ContentView()
                .environment(model)
                .environment(slideshow)
        }
        .commands {
            AppCommands(model: model, slideshow: slideshow)
        }

        Window("About \(AboutView.appName)", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Settings {
            SettingsView(recents: model.recents)
        }
    }
}

/// File and View menu commands. Lives in a `Commands` type so it can read
/// `@Environment(\.openWindow)` from a scene-level context that stays valid
/// even after the window has been closed.
private struct AppCommands: Commands {
    let model: ImageModel
    let slideshow: Slideshow
    @Environment(\.openWindow) private var openWindow

    /// Menu bindings onto the model. `model` is a plain reference here rather than
    /// `@Bindable`, so the bindings are made by hand.
    private var sortOrderBinding: Binding<FolderSortOrder> {
        Binding(get: { model.sortOrder }, set: { model.sortOrder = $0 })
    }

    private var sortReversedBinding: Binding<Bool> {
        Binding(get: { model.sortReversed }, set: { model.sortReversed = $0 })
    }

    /// Applications for the Edit With menu, split into declared editors and the rest.
    private var externalEditors: (editors: [URL], others: [URL]) {
        guard let url = model.url else { return ([], []) }
        let apps = ExternalEditor.applications(forOpening: url)
        return ExternalEditor.split(apps, for: UTType(filenameExtension: url.pathExtension))
    }

    /// Hands the file on disk to another application.
    private func editWith(_ app: URL) {
        guard let url = model.url else { return }
        ExternalEditor.open(url, in: app)
    }
    @FocusedValue(\.inspectorVisible) private var inspectorVisible
    @FocusedValue(\.sidebarVisible) private var sidebarVisible
    @FocusedValue(\.zoomController) private var zoom

    var body: some Commands {
        // Replace the standard About panel with our custom About window.
        CommandGroup(replacing: .appInfo) {
            Button("About \(AboutView.appName)") { openWindow(id: "about") }
        }
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

            Divider()

            Button("Close Image") { model.close() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(model.image == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save As…") {
                guard let image = model.image, let url = model.url else { return }
                let sourceType = UTType(filenameExtension: url.pathExtension)
                // RAW and other read-only formats fall back to PNG; without this the
                // save panel offers a format ImageIO cannot write and always fails.
                let type = ImageExporter.saveAsType(for: sourceType)
                let ext = (type == sourceType && !url.pathExtension.isEmpty)
                    ? url.pathExtension                       // keep .jpg rather than normalising to .jpeg
                    : (type.preferredFilenameExtension ?? "png")
                let name = "\(url.deletingPathExtension().lastPathComponent).\(ext)"
                switch ImageExporter.run(image: image, defaultName: name, contentType: type) {
                case .saved: model.markEditsSaved()
                case .cancelled: break
                case .failed(let error): model.errorMessage = error
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(model.image == nil)

            Menu("Export As") {
                ForEach(ImageFormat.allCases) { format in
                    Button(format.displayName) {
                        guard let image = model.image else { return }
                        let base = model.url?.deletingPathExtension().lastPathComponent ?? "Image"
                        switch ImageExporter.run(
                            image: image,
                            defaultName: "\(base).\(format.fileExtension)",
                            contentType: format.contentType
                        ) {
                        case .saved: model.markEditsSaved()
                        case .cancelled: break
                        case .failed(let error): model.errorMessage = error
                        }
                    }
                }
            }
            .disabled(model.image == nil)

            Divider()

            Button("Show in Finder") {
                if let url = model.url { FileActions.showInFinder(url) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.url == nil)

            Button("Copy Path") {
                if let url = model.url { FileActions.copyPath(url) }
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(model.url == nil)

            Divider()

            Menu("Edit With") {
                let split = externalEditors
                ForEach(split.editors, id: \.self) { app in
                    Button(ExternalEditor.name(of: app)) { editWith(app) }
                }
                if !split.editors.isEmpty, !split.others.isEmpty {
                    Divider()
                }
                if !split.others.isEmpty {
                    Menu("All Applications") {
                        ForEach(split.others, id: \.self) { app in
                            Button(ExternalEditor.name(of: app)) { editWith(app) }
                        }
                    }
                }
                Divider()
                Button("Other…") {
                    if let app = ExternalEditor.chooseApplication() { editWith(app) }
                }
            }
            .disabled(model.url == nil)
        }
        // The stock pasteboard items act on the responder chain, which has no text or
        // image responder in this app, so they are inert. Replace them with commands
        // that copy and paste the image itself.
        CommandGroup(replacing: .pasteboard) {
            Button("Copy Image") { model.copyToPasteboard() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(model.image == nil)

            Button("Paste Image") { model.paste() }
                .keyboardShortcut("v", modifiers: .command)
        }
        // The stock Undo/Redo drive the responder chain's undo manager, which knows
        // nothing about image edits. Point them at the model's own history instead.
        CommandGroup(replacing: .undoRedo) {
            Button(model.undoActionName.map { "Undo \($0)" } ?? "Undo") { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)

            Button(model.redoActionName.map { "Redo \($0)" } ?? "Redo") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
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

            Button(slideshow.isRunning ? "Stop Slideshow" : "Start Slideshow") { slideshow.toggle() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!slideshow.canStart)

            Menu("Sort Images By") {
                Picker("Sort Images By", selection: sortOrderBinding) {
                    ForEach(FolderSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Toggle("Reversed", isOn: sortReversedBinding)
            }
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

            Divider()

            Button("Rotate Left") { model.rotate(byDegreesClockwise: -90) }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(model.image == nil)

            Button("Rotate Right") { model.rotate(byDegreesClockwise: 90) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.image == nil)

            Button("Rotate 180°") { model.rotate(byDegreesClockwise: 180) }
                .disabled(model.image == nil)

            Button("Flip Horizontal") { model.flip(horizontal: true) }
                .disabled(model.image == nil)

            Button("Flip Vertical") { model.flip(horizontal: false) }
                .disabled(model.image == nil)

            Divider()

            Button("Revert to Original") { model.revert() }
                .disabled(!model.canRevert)
        }
    }

    private var zoomDisabled: Bool {
        zoom == nil || model.image == nil
    }
}

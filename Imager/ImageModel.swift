import AppKit
import Observation
import UniformTypeIdentifiers

/// Holds the currently displayed image and, optionally, a folder of images to browse.
@Observable
final class ImageModel {
    var image: NSImage?
    var url: URL?
    var info: ImageInfo?
    var errorMessage: String?

    /// The image as originally loaded, kept so edits can be undone or reverted.
    private(set) var originalImage: NSImage?

    /// Edits applied to `originalImage`, oldest first. Replaying these produces `image`.
    private(set) var edits: [ImageEdit] = []

    /// Edits taken off `edits` by undo, newest first, waiting to be redone.
    /// Cleared as soon as a fresh edit is made, as usual for an undo history.
    private(set) var redoStack: [ImageEdit] = []

    /// The edit history as of the last save or load, so "unsaved" survives undo and redo.
    ///
    /// `nil` means nothing on disk corresponds to what is on screen, which is the case
    /// for a pasted image until it is exported. That makes a pasted image count as
    /// unsaved straight away, so closing or quitting asks before throwing it away.
    private var savedEdits: [ImageEdit]? = []

    /// True when the working image differs from the original (an edit can be undone).
    var canRevert: Bool { !edits.isEmpty }

    var canUndo: Bool { !edits.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Names for the Undo/Redo menu items, e.g. "Undo Rotate".
    var undoActionName: String? { edits.last?.actionName }
    var redoActionName: String? { redoStack.last?.actionName }

    /// True when the edit history differs from the last saved state.
    ///
    /// Derived rather than stored so that undoing back to the saved state clears it,
    /// and redoing away from it sets it again.
    var hasUnsavedEdits: Bool { edits != savedEdits }

    /// An action waiting on the user's answer to the "discard changes?" alert.
    /// Non-nil while the alert is showing.
    var pendingDiscard: PendingDiscard?

    /// A destructive action held back until the user confirms losing unsaved edits.
    struct PendingDiscard {
        let fileName: String
        let onDiscard: () -> Void
        let onCancel: () -> Void
    }

    // Folder browsing
    private(set) var folderURL: URL?
    private(set) var folderImages: [URL] = []
    private(set) var selectionIndex: Int?

    /// True when a folder of more than one image is loaded for navigation.
    var canBrowse: Bool { folderImages.count > 1 }

    let recents: RecentFilesStore

    /// How the browsed folder is ordered. Persisted, and re-sorts the folder in place
    /// while keeping the image on screen selected.
    var sortOrder: FolderSortOrder {
        didSet {
            defaults.set(sortOrder.rawValue, forKey: FolderSortOrder.orderKey)
            resortFolder()
        }
    }

    var sortReversed: Bool {
        didSet {
            defaults.set(sortReversed, forKey: FolderSortOrder.reversedKey)
            resortFolder()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Injectable so tests never touch the user's real clipboard.
    @ObservationIgnored private let pasteboard: NSPasteboard

    /// Reopens/fronts the app's window. Installed by the scene so any open path
    /// can display an image even after the window was closed.
    @ObservationIgnored private var windowOpener: (() -> Void)?

    /// Held security-scoped access to the folder currently being browsed.
    @ObservationIgnored private var folderAccess: URL?

    init(
        recents: RecentFilesStore = RecentFilesStore(),
        defaults: UserDefaults = .standard,
        pasteboard: NSPasteboard = .general
    ) {
        self.recents = recents
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.sortOrder = FolderSortOrder(rawValue: defaults.string(forKey: FolderSortOrder.orderKey) ?? "")
            ?? FolderSortOrder.defaultOrder
        self.sortReversed = defaults.bool(forKey: FolderSortOrder.reversedKey)
    }

    func setWindowOpener(_ opener: @escaping () -> Void) { windowOpener = opener }

    func ensureWindow() { windowOpener?() }

    // MARK: - Opening

    /// Opens a URL, browsing it if it's a folder or showing it if it's an image file.
    /// Used by Finder "Open With", `open -a`, and drag-and-drop.
    func open(_ url: URL) {
        confirmDiscardingEdits { [self] in performOpen(url) }
    }

    private func performOpen(_ url: URL) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            performOpenFolder(url)
        } else {
            performLoad(from: url)
        }
    }

    /// Clears the current image, returning to the empty state (the window stays open).
    func close() {
        confirmDiscardingEdits { [self] in performClose() }
    }

    private func performClose() {
        image = nil
        originalImage = nil
        url = nil
        info = nil
        errorMessage = nil
        edits.removeAll()
        redoStack.removeAll()
        savedEdits = []
        clearFolder()
    }

    /// Opens a single image file, showing just that image (clears any folder browsing).
    func load(from url: URL) {
        confirmDiscardingEdits { [self] in performLoad(from: url) }
    }

    private func performLoad(from url: URL) {
        ensureWindow()
        clearFolder()
        display(url, record: true)
    }

    /// Opens a previously recorded recent file, resolving its bookmark.
    func openRecent(_ item: RecentFilesStore.Item) {
        guard let url = recents.resolve(item) else {
            self.errorMessage = "“\(item.displayName)” could not be found. It may have been moved or deleted."
            return
        }
        load(from: url)
    }

    /// Opens a folder, populating the thumbnail list and showing its first image.
    func openFolder(_ folder: URL) {
        confirmDiscardingEdits { [self] in performOpenFolder(folder) }
    }

    private func performOpenFolder(_ folder: URL) {
        ensureWindow()
        clearFolder()

        // Folder access grants read to the contents; hold it for the session so
        // enumeration and every sibling image load succeed under the sandbox.
        let scoped = folder.startAccessingSecurityScopedResource()
        let images = Self.imageURLs(in: folder, order: sortOrder, reversed: sortReversed)
        guard !images.isEmpty else {
            if scoped { folder.stopAccessingSecurityScopedResource() }
            self.errorMessage = "No images found in “\(folder.lastPathComponent)”."
            return
        }
        folderAccess = scoped ? folder : nil
        folderURL = folder
        folderImages = images
        performSelect(0)
    }

    // MARK: - Navigation

    func select(_ index: Int) {
        guard index != selectionIndex else { return }
        confirmDiscardingEdits { [self] in performSelect(index) }
    }

    private func performSelect(_ index: Int) {
        guard folderImages.indices.contains(index) else { return }
        selectionIndex = index
        display(folderImages[index], record: false)
    }

    func showNext() {
        guard let i = selectionIndex else { return }
        select(min(i + 1, folderImages.count - 1))
    }

    func showPrevious() {
        guard let i = selectionIndex else { return }
        select(max(i - 1, 0))
    }

    // MARK: - Internals

    /// Loads and shows an image. Records to recents only for explicit single-file opens
    /// (folder navigation should not flood the recents list).
    private func display(_ url: URL, record: Bool) {
        // For standalone files this grants access; for folder-derived files access
        // comes from the held folder scope, so this is a harmless no-op.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let image = NSImage(contentsOf: url) else {
            self.errorMessage = "Couldn't read an image from \(url.lastPathComponent)."
            return
        }
        self.image = image
        self.originalImage = image
        self.url = url
        self.errorMessage = nil
        self.edits.removeAll()
        self.redoStack.removeAll()
        self.savedEdits = []
        updateInfo()
        if record { recents.record(url) }
    }

    /// Runs `action` immediately when there is nothing to lose, otherwise parks it in
    /// `pendingDiscard` for the confirmation alert to resolve.
    ///
    /// The prompt is deliberately driven from model state rather than `NSAlert.runModal()`:
    /// a nested modal started from inside a menu action is torn down when the menu's
    /// tracking loop unwinds, which dismissed the alert on its own and let the edits go.
    private func confirmDiscardingEdits(then action: @escaping () -> Void) {
        guard hasUnsavedEdits else { return action() }
        pendingDiscard = PendingDiscard(
            fileName: url?.lastPathComponent ?? "this image",
            onDiscard: action,
            onCancel: {}
        )
    }

    /// Asks about unsaved edits on quit, answering `NSApp` once the user decides.
    /// Returns false if a confirmation is already on screen, in which case the quit
    /// is refused outright rather than stacking a second prompt.
    func requestQuitConfirmation() -> Bool {
        guard pendingDiscard == nil else { return false }
        ensureWindow()
        pendingDiscard = PendingDiscard(
            fileName: url?.lastPathComponent ?? "this image",
            onDiscard: { NSApp.reply(toApplicationShouldTerminate: true) },
            onCancel: { NSApp.reply(toApplicationShouldTerminate: false) }
        )
        return true
    }

    /// Resolves the pending confirmation. Called by the alert's buttons.
    func resolveDiscard(confirmed: Bool) {
        guard let pending = pendingDiscard else { return }
        pendingDiscard = nil
        confirmed ? pending.onDiscard() : pending.onCancel()
    }

    /// Records that the current image has been written out, so it no longer counts
    /// as unsaved. The edits themselves remain revertable.
    func markEditsSaved() {
        guard hasUnsavedEdits else { return }
        savedEdits = edits
        updateInfo()
    }

    /// Refreshes `info` to reflect the currently displayed image: the source file's full
    /// metadata when unedited, or the in-memory image's metadata after an edit (e.g. crop).
    private func updateInfo() {
        guard let image else { info = nil; return }
        if !canRevert, let url {
            info = ImageInfoExtractor.info(for: url)
        } else {
            info = ImageInfoExtractor.info(forEditedImage: image, source: url, hasUnsavedEdits: hasUnsavedEdits)
        }
    }

    // MARK: - Editing

    /// Crops the current image to a rectangle in image pixel coordinates (top-left origin).
    func crop(to pixelRect: CGRect) { apply(.crop(pixelRect)) }

    /// Rotates the current image by the given angle in degrees (positive = clockwise).
    func rotate(byDegreesClockwise degrees: Double) { apply(.rotate(degreesClockwise: degrees)) }

    /// Mirrors the current image horizontally or vertically.
    func flip(horizontal: Bool) { apply(.flip(horizontal: horizontal)) }

    /// Applies an edit and records it, discarding any redo history.
    /// An edit that cannot be carried out is not recorded.
    private func apply(_ edit: ImageEdit) {
        guard let current = image, let result = edit.apply(to: current) else { return }
        image = result
        edits.append(edit)
        redoStack.removeAll()
        updateInfo()
    }

    /// Takes back the most recent edit.
    func undo() {
        guard let last = edits.popLast() else { return }
        redoStack.append(last)
        rebuildImage()
    }

    /// Re-applies the most recently undone edit.
    func redo() {
        guard let next = redoStack.popLast() else { return }
        edits.append(next)
        rebuildImage()
    }

    /// Restores the image as originally loaded, discarding the whole history.
    func revert() {
        guard originalImage != nil else { return }
        edits.removeAll()
        redoStack.removeAll()
        // A pasted image still has no file behind it, so reverting leaves it unsaved.
        savedEdits = url == nil ? nil : []
        rebuildImage()
    }

    // MARK: - Clipboard

    /// True when the pasteboard holds something that can be pasted as an image.
    var canPaste: Bool {
        pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    /// Puts the image currently on screen, including any edits, on the pasteboard.
    @discardableResult
    func copyToPasteboard() -> Bool {
        guard let image else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    /// Shows an image from the pasteboard. The result has no file behind it, so it
    /// counts as unsaved until it is written out with Export As.
    func paste() {
        confirmDiscardingEdits { [self] in performPaste() }
    }

    private func performPaste() {
        guard let pasted = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?
            .first as? NSImage else {
            errorMessage = "There is no image on the clipboard."
            return
        }
        ensureWindow()
        clearFolder()
        image = pasted
        originalImage = pasted
        url = nil
        errorMessage = nil
        edits.removeAll()
        redoStack.removeAll()
        savedEdits = nil
        updateInfo()
    }

    /// Recomputes the displayed image by replaying `edits` onto the original.
    private func rebuildImage() {
        guard let originalImage else { return }
        image = edits.isEmpty ? originalImage : edits.applied(to: originalImage)
        updateInfo()
    }

    private func clearFolder() {
        if let folder = folderAccess {
            folder.stopAccessingSecurityScopedResource()
            folderAccess = nil
        }
        folderURL = nil
        folderImages = []
        selectionIndex = nil
    }

    // MARK: - Enumeration

    /// Immediate (non-recursive) image files in a folder, in the requested order.
    /// Name order is Finder-style; date and size ties fall back to name so the
    /// result is stable rather than dependent on directory order.
    static func imageURLs(
        in folder: URL,
        order: FolderSortOrder = .name,
        reversed: Bool = false
    ) -> [URL] {
        let keys: [URLResourceKey] = [
            .contentTypeKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
        ]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        let sorted = contents.filter(isImageFile).sorted { a, b in
            switch order {
            case .name:
                byName(a, b)
            case .dateModified:
                modified(a) == modified(b) ? byName(a, b) : modified(a) < modified(b)
            case .size:
                size(a) == size(b) ? byName(a, b) : size(a) < size(b)
            }
        }
        return reversed ? sorted.reversed() : sorted
    }

    private static func byName(_ a: URL, _ b: URL) -> Bool {
        a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private static func size(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    /// Re-orders the current folder in place, keeping the image on screen selected.
    /// Deliberately does not go through `select()`: the displayed image is unchanged,
    /// so there is nothing to reload and nothing to confirm.
    private func resortFolder() {
        guard let folderURL, !folderImages.isEmpty else { return }
        let showing = selectionIndex.flatMap { folderImages.indices.contains($0) ? folderImages[$0] : nil }
        folderImages = Self.imageURLs(in: folderURL, order: sortOrder, reversed: sortReversed)
        if let showing, let index = folderImages.firstIndex(of: showing) {
            selectionIndex = index
        }
    }

    private static func isImageFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
              values.isRegularFile == true,
              let type = values.contentType else {
            return false
        }
        return type.conforms(to: .image)
    }
}

/// Presents standard macOS open panels for a single image file or a folder.
enum ImageOpener {
    static func run() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose an image to open"
        panel.prompt = "Open"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func runFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder of images to browse"
        panel.prompt = "Open"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

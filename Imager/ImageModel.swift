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

    /// Undo and redo hold whole snapshots of the edit list rather than individual edits.
    ///
    /// An `[ImageEdit]` is a handful of numbers, so snapshots cost nothing, and it is the
    /// only model that copes with an action that rewrites the list rather than appending
    /// to it - applying a recipe replaces the orientation and adjustments, so popping a
    /// single edit could not put back what it displaced.
    /// Each entry carries the name of the action that moved away from it, for the menu.
    private struct HistoryEntry {
        let edits: [ImageEdit]
        /// Carried alongside the edits because RAW development is not an `ImageEdit` - it
        /// produces the image rather than transforming one - yet must undo with everything else.
        let rawSettings: RawSettings?
        let actionName: String
    }

    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []

    /// The edit history as of the last save or load, so "unsaved" survives undo and redo.
    ///
    /// `nil` means nothing on disk corresponds to what is on screen, which is the case
    /// for a pasted image until it is exported. That makes a pasted image count as
    /// unsaved straight away, so closing or quitting asks before throwing it away.
    private var savedEdits: [ImageEdit]? = []

    /// How the current RAW file is being developed, or nil when the image is not RAW.
    private(set) var rawSettings: RawSettings?

    /// The RAW settings as of the last save or load, so developing counts as unsaved work.
    private var savedRawSettings: RawSettings?

    /// Holds the decoder open for the current RAW file. Keeping one alive is what makes
    /// dragging a RAW slider cost about 7 ms instead of 86 ms or more.
    @ObservationIgnored private var rawDeveloper: RawDeveloper?

    /// True when the image on screen came from a RAW file that can be developed.
    var isRaw: Bool { rawDeveloper != nil }

    /// Which RAW controls this file supports; varies by camera, decoder and system version.
    var rawSupport: RawSupport { rawDeveloper?.support ?? RawSupport() }

    /// The decoder's own reading of this shot, which is what Reset returns to.
    var rawDefaults: RawSettings? { rawDeveloper?.defaults }

    /// True when the working image differs from the original (an edit can be undone).
    var canRevert: Bool { !edits.isEmpty }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Names for the Undo/Redo menu items, e.g. "Undo Rotate".
    var undoActionName: String? { undoStack.last?.actionName }
    var redoActionName: String? { redoStack.last?.actionName }

    /// True when the edit history differs from the last saved state.
    ///
    /// Derived rather than stored so that undoing back to the saved state clears it,
    /// and redoing away from it sets it again.
    var hasUnsavedEdits: Bool { edits != savedEdits || rawSettings != savedRawSettings }

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

    /// Groupings of frames in the current folder: bursts, brackets, several tries at one shot.
    private(set) var stacks: [ImageStack] = []

    /// Picks of the stacks the user has opened up. Not persisted; expansion is a way of looking
    /// at a folder rather than a fact about it.
    private var expandedPicks: Set<String> = []

    /// Frame name to the stack holding it, so the derived lists below stay linear.
    private var stackByFrame: [String: ImageStack] {
        var map: [String: ImageStack] = [:]
        for stack in stacks {
            for frame in stack.frames { map[frame] = stack }
        }
        return map
    }

    /// What the browser shows: the pick of each collapsed stack, every frame of an expanded one,
    /// and anything unstacked as itself - all in folder order.
    var visibleImages: [URL] {
        guard !stacks.isEmpty else { return folderImages }
        let lookup = stackByFrame
        return folderImages.filter { url in
            let name = url.lastPathComponent
            guard let stack = lookup[name] else { return true }
            return expandedPicks.contains(stack.pick) || stack.pick == name
        }
    }

    /// One frame per stack, plus everything unstacked.
    ///
    /// What a slideshow and a batch run on: stacking is a photographic idea, so the features
    /// that present a folder present the pictures rather than every frame taken to get them.
    var pickImages: [URL] {
        guard !stacks.isEmpty else { return folderImages }
        let lookup = stackByFrame
        return folderImages.filter { url in
            let name = url.lastPathComponent
            guard let stack = lookup[name] else { return true }
            return stack.pick == name
        }
    }

    func stack(containing url: URL) -> ImageStack? { stackByFrame[url.lastPathComponent] }

    func isExpanded(_ stack: ImageStack) -> Bool { expandedPicks.contains(stack.pick) }

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

    /// How a file is sent to the Trash. Injectable so tests do not fill the user's
    /// actual Trash with temporary files.
    @ObservationIgnored private let trashItem: (URL) throws -> Void

    /// Reopens/fronts the app's window. Installed by the scene so any open path
    /// can display an image even after the window was closed.
    @ObservationIgnored private var windowOpener: (() -> Void)?

    /// Held security-scoped access to the folder currently being browsed.
    @ObservationIgnored private var folderAccess: URL?

    /// Held security-scoped access to the file currently displayed, kept so the file
    /// can still be acted on after it has been loaded.
    @ObservationIgnored private var fileAccess: URL?

    init(
        recents: RecentFilesStore = RecentFilesStore(),
        defaults: UserDefaults = .standard,
        pasteboard: NSPasteboard = .general,
        trashItem: @escaping (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
    ) {
        self.recents = recents
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.trashItem = trashItem
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
        clearHistory()
        savedEdits = []
        rawDeveloper = nil
        rawSettings = nil
        savedRawSettings = nil
        releaseFileAccess()
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
        stacks = Stacks.load(for: folder, available: images.map(\.lastPathComponent))
        performSelect(0)
    }

    // MARK: - Navigation

    func select(_ index: Int) {
        guard index != selectionIndex else { return }
        confirmDiscardingEdits { [self] in performSelect(index) }
    }

    /// Shows a particular file, if it is in the current folder.
    func select(_ url: URL) {
        guard let index = folderImages.firstIndex(of: url) else { return }
        select(index)
    }

    private func performSelect(_ index: Int) {
        guard folderImages.indices.contains(index) else { return }
        selectionIndex = index
        display(folderImages[index], record: false)
    }

    func showNext() { step(by: 1) }

    func showPrevious() { step(by: -1) }

    /// Steps through what the browser is showing rather than every file in the folder, so
    /// arrowing past a collapsed stack skips the frames hidden behind its pick.
    private func step(by offset: Int) {
        let visible = visibleImages
        guard let current = selectionIndex.flatMap({ folderImages.indices.contains($0) ? folderImages[$0] : nil }),
              let here = visible.firstIndex(of: current) else { return }
        let next = min(max(here + offset, 0), visible.count - 1)
        guard next != here else { return }
        select(visible[next])
    }

    // MARK: - Stack operations

    /// Groups the folder's frames by capture time.
    ///
    /// Takes the times already read rather than reading them, because reading them is the
    /// expensive part - about 18 ms a frame on RAW - and the sheet has to read them anyway to
    /// show what the grouping would be.
    func autoStack(dated frames: [(name: String, date: Date?)], within interval: TimeInterval) {
        guard folderURL != nil else { return }
        let grouped = Stacks.autoStack(dated: frames, within: interval)
        guard grouped != stacks else { return }
        stacks = grouped
        expandedPicks.removeAll()
        persistStacks()
        keepSelectionVisible()
    }

    /// Makes the shown frame the one its stack presents when collapsed.
    func promoteToPick(_ url: URL) {
        let name = url.lastPathComponent
        guard let index = stacks.firstIndex(where: { $0.contains(name) }), stacks[index].pick != name else { return }
        // Expansion is keyed by pick, so it has to move with it.
        let wasExpanded = expandedPicks.remove(stacks[index].pick) != nil
        stacks[index].pick = name
        if wasExpanded { expandedPicks.insert(name) }
        persistStacks()
    }

    /// Breaks up the stack holding this file, leaving its frames as ordinary images.
    func unstack(_ url: URL) {
        let name = url.lastPathComponent
        guard let index = stacks.firstIndex(where: { $0.contains(name) }) else { return }
        expandedPicks.remove(stacks[index].pick)
        stacks.remove(at: index)
        persistStacks()
    }

    func unstackAll() {
        guard !stacks.isEmpty else { return }
        stacks.removeAll()
        expandedPicks.removeAll()
        persistStacks()
    }

    func toggleExpansion(of stack: ImageStack) {
        if expandedPicks.remove(stack.pick) == nil { expandedPicks.insert(stack.pick) }
        keepSelectionVisible()
    }

    func expandAllStacks() {
        expandedPicks = Set(stacks.map(\.pick))
    }

    func collapseAllStacks() {
        guard !expandedPicks.isEmpty else { return }
        expandedPicks.removeAll()
        keepSelectionVisible()
    }

    /// Moves the selection to the pick when collapsing hides the frame being shown, so the
    /// browser never highlights a row that is not there.
    private func keepSelectionVisible() {
        guard let index = selectionIndex, folderImages.indices.contains(index) else { return }
        let showing = folderImages[index]
        guard !visibleImages.contains(showing), let stack = stack(containing: showing),
              let pick = folderImages.first(where: { $0.lastPathComponent == stack.pick }) else { return }
        performSelect(folderImages.firstIndex(of: pick) ?? index)
    }

    /// Brings the grouping back into line with the files present, after one has gone.
    private func reconcileStacks() {
        guard !stacks.isEmpty else { return }
        let reconciled = Stacks.reconcile(stacks, against: folderImages.map(\.lastPathComponent))
        guard reconciled != stacks else { return }
        stacks = reconciled
        expandedPicks.formIntersection(Set(stacks.map(\.pick)))
        persistStacks()
    }

    private func persistStacks() {
        guard let folderURL else { return }
        if case .failed(let message) = Stacks.save(stacks, for: folderURL) {
            errorMessage = message
        }
    }

    // MARK: - Internals

    /// Loads and shows an image. Records to recents only for explicit single-file opens
    /// (folder navigation should not flood the recents list).
    private func display(_ url: URL, record: Bool) {
        // For standalone files this grants access; for folder-derived files access
        // comes from the held folder scope, so this is a harmless no-op.
        //
        // Access is held for as long as the file is on screen rather than released
        // after loading. Anything acting on the file later needs it: handing it to
        // another application only grants that application access while Imager still
        // holds its own, and a file opened from a resolved bookmark has no access at
        // all once the scope is dropped.
        releaseFileAccess()
        let scoped = url.startAccessingSecurityScopedResource()

        // A RAW file is developed from its sensor data; anything else is just decoded.
        // The developer is kept for the lifetime of the open file - see RawDeveloper.
        let developer = RawDeveloper(url: url)
        let loaded = developer.flatMap { $0.develop($0.defaults, preview: false) }
            ?? NSImage(contentsOf: url)

        guard let image = loaded else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            self.errorMessage = "Couldn't read an image from \(url.lastPathComponent)."
            return
        }
        fileAccess = scoped ? url : nil
        rawDeveloper = developer
        rawSettings = developer?.defaults
        savedRawSettings = developer?.defaults
        self.image = image
        self.originalImage = image
        self.url = url
        self.errorMessage = nil
        clearHistory()
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
        savedRawSettings = rawSettings
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
        recordForUndo(edit.actionName)
        image = result
        edits.append(edit)
        updateInfo()
    }

    /// Snapshots the current history so `undo()` can come back to it, and drops any redo
    /// history, since the timeline has branched.
    private func recordForUndo(_ actionName: String) {
        undoStack.append(HistoryEntry(edits: edits, rawSettings: rawSettings, actionName: actionName))
        redoStack.removeAll()
    }

    /// Discards the edit history entirely, for when a different image takes over.
    private func clearHistory() {
        edits.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
    }

    // MARK: - Trash

    /// True when there is a file on disk that could be trashed. False for a pasted image.
    var canMoveToTrash: Bool { url != nil }

    /// Moves the current file to the Trash and shows a neighbouring image.
    ///
    /// Deliberately does not ask first. The Trash is itself the undo, Finder's ⌘⌫ does not
    /// prompt either, and a confirmation on every image would defeat the quick culling this
    /// exists for. It also does not ask about unsaved edits: the file is being thrown away,
    /// so preserving edits to it makes no sense.
    func moveToTrash() {
        guard let url else { return }

        do {
            try trashItem(url)
        } catch {
            errorMessage = "Couldn't move “\(url.lastPathComponent)” to the Trash. "
                + error.localizedDescription
            return
        }

        releaseFileAccess()

        // Drop it from the folder listing and show whatever took its place, or the one
        // before it if the trashed image was last.
        guard let index = folderImages.firstIndex(of: url) else {
            performClose()
            return
        }
        folderImages.remove(at: index)
        guard !folderImages.isEmpty else {
            performClose()
            return
        }
        // Trashing a frame can promote a pick, or leave a stack too small to remain one.
        reconcileStacks()
        selectionIndex = nil
        performSelect(min(index, folderImages.count - 1))
        keepSelectionVisible()
    }

    // MARK: - RAW development

    /// Changes how the RAW file is developed.
    ///
    /// Mirrors `setAdjustments`: one drag is one undo step. `preview` develops at reduced
    /// scale for speed, so a drag should pass true and `commitRawDevelopment()` should follow
    /// when it ends.
    func setRawSettings(_ value: RawSettings, continuingSession: Bool = false, preview: Bool = false) {
        guard rawDeveloper != nil, rawSettings != nil else { return }

        if !continuingSession {
            guard value != rawSettings else { return }
            recordForUndo("Develop")
        }
        rawSettings = value
        rebuildImage(preview: preview)
    }

    /// Re-develops at full size after a drag, which is left at preview scale for speed.
    func commitRawDevelopment() {
        guard rawDeveloper != nil else { return }
        rebuildImage(preview: false)
    }

    /// Returns development to the decoder's own reading of the shot.
    func resetRawDevelopment() {
        guard let rawDefaults, rawSettings != rawDefaults else { return }
        recordForUndo("Reset Development")
        rawSettings = rawDefaults
        rebuildImage()
    }

    // MARK: - Adjustments

    /// The adjustment currently in force, or neutral when there is none.
    var adjustments: Adjustments {
        for edit in edits.reversed() {
            if case .adjust(let value) = edit { return value }
        }
        return .neutral
    }

    /// Applies tonal and colour adjustments.
    ///
    /// `continuingSession` replaces the trailing adjustment instead of adding another,
    /// which is what a slider drag wants: one undo step for the drag rather than one
    /// per tick. The first change of a drag passes false, the rest pass true.
    func setAdjustments(_ value: Adjustments, continuingSession: Bool = false) {
        guard image != nil else { return }

        // Work out the resulting history first, so a call that changes nothing can be
        // dropped rather than costing an undo step that appears to do nothing.
        var updated = edits
        if continuingSession, updated.last?.isAdjustment == true {
            // Mid-drag: fold into the step this drag already started.
            updated.removeLast()
        }

        // A neutral adjustment is only worth recording when there is an earlier one for
        // it to cancel - that is what Reset does. Otherwise it would be an edit that
        // changes nothing.
        if !value.isNeutral || updated.contains(where: \.isAdjustment) {
            updated.append(.adjust(value))
        }

        // Only the start of a session is guarded. Skipping mid-drag would leave later
        // ticks folding into the previous session's step with no undo entry of their own.
        if !continuingSession {
            // A new session appends rather than replaces, so setting the value already in
            // force would add a second identical adjustment: a different list that renders
            // the same, and an undo step that appears to do nothing.
            if case .adjust(let current)? = edits.last, current == value { return }
            guard updated != edits else { return }
            recordForUndo("Adjust")
        }
        edits = updated
        rebuildImage()
    }

    /// Takes back the most recent action.
    func undo() {
        guard let entry = undoStack.popLast() else { return }
        redoStack.append(HistoryEntry(edits: edits, rawSettings: rawSettings, actionName: entry.actionName))
        edits = entry.edits
        rawSettings = entry.rawSettings
        rebuildImage()
    }

    /// Re-applies the most recently undone action.
    func redo() {
        guard let entry = redoStack.popLast() else { return }
        undoStack.append(HistoryEntry(edits: edits, rawSettings: rawSettings, actionName: entry.actionName))
        edits = entry.edits
        rawSettings = entry.rawSettings
        rebuildImage()
    }

    /// Restores the image as originally loaded, discarding the whole history.
    func revert() {
        guard originalImage != nil else { return }
        clearHistory()
        // Reverting means the file as it was opened, which for a RAW includes the
        // development the decoder chose.
        rawSettings = rawDeveloper?.defaults
        // A pasted image still has no file behind it, so reverting leaves it unsaved.
        savedEdits = url == nil ? nil : []
        rebuildImage()
    }

    // MARK: - Recipes

    /// Edits worth saving as a recipe: everything except crops, which are in pixel
    /// coordinates of one particular image and cannot transfer to another.
    var recipeEdits: [ImageEdit] { edits.filter { !$0.isCrop } }

    /// RAW development worth saving: only when it differs from what the decoder chose, so a
    /// recipe made from an untouched RAW does not silently pin another shot to this one's
    /// white balance.
    var recipeRawSettings: RawSettings? {
        guard let rawSettings, rawSettings != rawDefaults else { return nil }
        return rawSettings
    }

    var canSaveRecipe: Bool { !recipeEdits.isEmpty || recipeRawSettings != nil }

    /// Applies a saved recipe, replacing the orientation and adjustments while leaving
    /// any crop alone.
    ///
    /// Replacing rather than appending means the result is the same whatever had already
    /// been done to the image: a recipe holding "rotate 90" gives a 90° rotation rather
    /// than compounding with a rotation already made. It is one undo step because undo
    /// restores the whole history snapshot.
    func applyRecipe(_ recipe: Recipe) {
        guard image != nil else { return }
        let updated = edits.filter { $0.isCrop } + recipe.edits
        // RAW development travels with the recipe, but only lands on a file that has some.
        let updatedRaw = (rawDeveloper != nil && recipe.rawSettings != nil)
            ? recipe.rawSettings
            : rawSettings
        // Applying a recipe that lands on the state already in force changes nothing, so
        // it must not record an undo step. Otherwise the first ⌘Z appears to do nothing:
        // it restores a state identical to the current one, and only the second gets back.
        guard updated != edits || updatedRaw != rawSettings else { return }
        recordForUndo("Apply “\(recipe.name)”")
        edits = updated
        rawSettings = updatedRaw
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
        releaseFileAccess()
        image = pasted
        originalImage = pasted
        url = nil
        errorMessage = nil
        clearHistory()
        savedEdits = nil
        // A pasted image has no file, so nothing to develop.
        rawDeveloper = nil
        rawSettings = nil
        savedRawSettings = nil
        updateInfo()
    }

    /// Recomputes the displayed image by replaying `edits` onto the original.
    /// Recomputes the image: develop the base, then replay the edits onto it.
    ///
    /// `preview` develops a RAW at reduced scale, which is what makes dragging a RAW slider
    /// responsive. It has no effect on a file that is not RAW.
    private func rebuildImage(preview: Bool = false) {
        guard let base = developedBase(preview: preview) else { return }
        image = edits.isEmpty ? base : edits.applied(to: base)
        updateInfo()
    }

    private func developedBase(preview: Bool) -> NSImage? {
        guard let rawDeveloper, let rawSettings else { return originalImage }
        return rawDeveloper.develop(rawSettings, preview: preview) ?? originalImage
    }

    private func releaseFileAccess() {
        if let fileAccess {
            fileAccess.stopAccessingSecurityScopedResource()
            self.fileAccess = nil
        }
    }

    private func clearFolder() {
        if let folder = folderAccess {
            folder.stopAccessingSecurityScopedResource()
            folderAccess = nil
        }
        folderURL = nil
        folderImages = []
        selectionIndex = nil
        stacks = []
        expandedPicks = []
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

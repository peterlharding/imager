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

    /// The image as originally loaded, kept so edits (e.g. crop) can be reverted.
    private(set) var originalImage: NSImage?

    /// True when the working image differs from the original (an edit can be undone).
    var canRevert: Bool { image != nil && image !== originalImage }

    // Folder browsing
    private(set) var folderURL: URL?
    private(set) var folderImages: [URL] = []
    private(set) var selectionIndex: Int?

    /// True when a folder of more than one image is loaded for navigation.
    var canBrowse: Bool { folderImages.count > 1 }

    let recents: RecentFilesStore

    /// Reopens/fronts the app's window. Installed by the scene so any open path
    /// can display an image even after the window was closed.
    @ObservationIgnored private var windowOpener: (() -> Void)?

    /// Held security-scoped access to the folder currently being browsed.
    @ObservationIgnored private var folderAccess: URL?

    init(recents: RecentFilesStore = RecentFilesStore()) {
        self.recents = recents
    }

    func setWindowOpener(_ opener: @escaping () -> Void) { windowOpener = opener }

    func ensureWindow() { windowOpener?() }

    // MARK: - Opening

    /// Opens a URL, browsing it if it's a folder or showing it if it's an image file.
    /// Used by Finder "Open With", `open -a`, and drag-and-drop.
    func open(_ url: URL) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            openFolder(url)
        } else {
            load(from: url)
        }
    }

    /// Opens a single image file, showing just that image (clears any folder browsing).
    func load(from url: URL) {
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
        ensureWindow()
        clearFolder()

        // Folder access grants read to the contents; hold it for the session so
        // enumeration and every sibling image load succeed under the sandbox.
        let scoped = folder.startAccessingSecurityScopedResource()
        let images = Self.imageURLs(in: folder)
        guard !images.isEmpty else {
            if scoped { folder.stopAccessingSecurityScopedResource() }
            self.errorMessage = "No images found in “\(folder.lastPathComponent)”."
            return
        }
        folderAccess = scoped ? folder : nil
        folderURL = folder
        folderImages = images
        select(0)
    }

    // MARK: - Navigation

    func select(_ index: Int) {
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
        self.info = ImageInfoExtractor.info(for: url)
        self.errorMessage = nil
        if record { recents.record(url) }
    }

    // MARK: - Editing

    /// Crops the current image to a rectangle in image pixel coordinates (top-left origin).
    func crop(to pixelRect: CGRect) {
        guard let current = image,
              let cg = current.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let full = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let rect = pixelRect.integral.intersection(full)
        guard rect.width >= 1, rect.height >= 1, let cropped = cg.cropping(to: rect) else { return }
        image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    /// Restores the image as originally loaded, discarding edits.
    func revert() {
        if let originalImage { image = originalImage }
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

    /// Immediate (non-recursive) image files in a folder, sorted Finder-style by name.
    static func imageURLs(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.contentTypeKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }
        return contents
            .filter(isImageFile)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
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

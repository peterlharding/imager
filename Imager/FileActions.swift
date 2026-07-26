import AppKit

/// Filesystem actions for the current image's source file.
enum FileActions {
    /// Opens Finder with the file selected.
    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Copies the full file path to the clipboard.
    static func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
}

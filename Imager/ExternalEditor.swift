import AppKit
import UniformTypeIdentifiers

/// Hands the current file to another application, for the File ▸ Edit With menu.
///
/// Deliberately knows nothing about any particular editor. darktable, the DxO suite,
/// GIMP, upscalers and denoisers are all just applications that can open the file, so
/// the list comes from LaunchServices and any tool installed later appears on its own.
enum ExternalEditor {

    /// Applications macOS offers for opening `url`, sorted by name, with Imager removed.
    ///
    /// This is everything that can *display* the file, which on a typical Mac means
    /// browsers, chat apps and QuickTime as well as real editors. Use `split(_:for:)`
    /// to get a usable menu out of it.
    static func applications(forOpening url: URL) -> [URL] {
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: url)
        return sorted(excludingSelf(from: candidates))
    }

    /// Splits candidates into those that declare themselves editors of the type and
    /// everything else.
    ///
    /// The distinction is a hint, not a rule: darktable declares `Viewer` for all image
    /// types despite being an editor, and DxO is likely the same. So the remainder is
    /// kept and offered rather than discarded.
    static func split(_ apps: [URL], for type: UTType?) -> (editors: [URL], others: [URL]) {
        guard let type else { return ([], apps) }
        var editors: [URL] = []
        var others: [URL] = []
        for app in apps {
            if declaresEditorRole(app, for: type) {
                editors.append(app)
            } else {
                others.append(app)
            }
        }
        return (editors, others)
    }

    static func declaresEditorRole(_ app: URL, for type: UTType) -> Bool {
        guard let bundle = Bundle(url: app),
              let types = bundle.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]] else {
            return false
        }
        return declaresEditorRole(documentTypes: types, for: type)
    }

    /// The plist half of the role check, kept separate so it can be exercised without
    /// depending on which applications happen to be installed.
    static func declaresEditorRole(documentTypes: [[String: Any]], for type: UTType) -> Bool {
        for entry in documentTypes {
            guard entry["CFBundleTypeRole"] as? String == "Editor" else { continue }
            let identifiers = (entry["LSItemContentTypes"] as? [String]) ?? []
            for identifier in identifiers {
                if let declared = UTType(identifier), type.conforms(to: declared) { return true }
            }
        }
        return false
    }

    /// Drops Imager from a list of candidates.
    ///
    /// Matched on bundle file name rather than bundle identifier: several copies of
    /// Imager can be registered at once (a build directory, an exported copy, one in
    /// Applications), and reading each candidate's Info.plist to compare identifiers
    /// would mean loading every installed editor's bundle to build a menu.
    static func excludingSelf(
        from apps: [URL],
        selfBundleName: String = Bundle.main.bundleURL.lastPathComponent
    ) -> [URL] {
        apps.filter { $0.lastPathComponent != selfBundleName }
    }

    static func sorted(_ apps: [URL]) -> [URL] {
        apps.sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
    }

    /// An application's display name, e.g. "Pixelmator Pro" for Pixelmator Pro.app.
    static func name(of app: URL) -> String {
        app.deletingPathExtension().lastPathComponent
    }

    /// Opens `url` in `app`, bringing it to the front.
    ///
    /// The file's security scope has to be held across the call: macOS grants the
    /// receiving application access only while Imager still holds its own, otherwise
    /// the hand-off fails with "Imager does not have permission to open …".
    /// The open is asynchronous, so the scope is released in the completion handler
    /// rather than on return.
    static func open(_ url: URL, in app: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, _ in
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
    }

    /// Presents a panel to pick any application, for tools LaunchServices does not
    /// associate with the file type.
    static func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an application to edit the image with"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

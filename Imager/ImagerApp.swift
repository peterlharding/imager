import SwiftUI

@main
struct ImagerApp: App {
    @State private var model = ImageModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .commands {
            // Replace the default "New" item with an "Open…" command (⌘O).
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    if let url = ImageOpener.run() {
                        model.load(from: url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

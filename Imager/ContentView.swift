import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(ImageModel.self) private var model

    var body: some View {
        Group {
            if let image = model.image {
                ImageCanvas(image: image)
            } else {
                EmptyState()
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle(model.url?.lastPathComponent ?? "Imager")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let url = ImageOpener.run() {
                        model.load(from: url)
                    }
                } label: {
                    Label("Open", systemImage: "folder")
                }
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

    /// Loads the first dropped file URL as an image.
    private func loadFirstImage(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { model.load(from: url) }
        }
        return true
    }
}

/// Displays the loaded image, scaled to fit while preserving aspect ratio.
private struct ImageCanvas: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(.background)
    }
}

/// Placeholder shown before any image is opened.
private struct EmptyState: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Image Open", systemImage: "photo")
        } description: {
            Text("Open an image with ⌘O, the toolbar button, or drag a file here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

#Preview {
    ContentView()
        .environment(ImageModel())
}

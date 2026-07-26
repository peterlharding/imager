import SwiftUI

/// Contents of the custom About window.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text(Self.appName)
                .font(.title2).bold()

            Text("Version \(Self.version) (\(Self.build))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("A native macOS app for viewing, browsing, and cropping images.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !Self.copyright.isEmpty {
                Text(Self.copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(width: 320)
    }

    // MARK: - Bundle values

    static let appName = infoString("CFBundleName") ?? "Imager"
    static let version = infoString("CFBundleShortVersionString") ?? "—"
    static let build = infoString("CFBundleVersion") ?? "—"
    static let copyright = infoString("NSHumanReadableCopyright") ?? ""

    private static func infoString(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

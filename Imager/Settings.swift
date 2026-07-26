import AppKit
import SwiftUI

/// Background fill styles for the image viewing area.
enum BackgroundStyle: String, CaseIterable, Identifiable {
    case color
    case checkerboard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .color: "Solid Colour"
        case .checkerboard: "Checkerboard"
        }
    }
}

/// UserDefaults keys and default values for the background setting.
enum BackgroundSetting {
    static let styleKey = "background.style"
    static let redKey = "background.red"
    static let greenKey = "background.green"
    static let blueKey = "background.blue"
    static let opacityKey = "background.opacity"

    static let defaultStyle = BackgroundStyle.color.rawValue
    static let defaultRed = 0.15
    static let defaultGreen = 0.15
    static let defaultBlue = 0.16
    static let defaultOpacity = 1.0
}

/// The background drawn behind the image: the chosen colour or checkerboard, at the chosen
/// opacity, blended over the app's standard window background.
struct BackgroundFill: View {
    @AppStorage(BackgroundSetting.styleKey) private var style = BackgroundSetting.defaultStyle
    @AppStorage(BackgroundSetting.redKey) private var red = BackgroundSetting.defaultRed
    @AppStorage(BackgroundSetting.greenKey) private var green = BackgroundSetting.defaultGreen
    @AppStorage(BackgroundSetting.blueKey) private var blue = BackgroundSetting.defaultBlue
    @AppStorage(BackgroundSetting.opacityKey) private var opacity = BackgroundSetting.defaultOpacity

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            fill.opacity(opacity)
        }
    }

    @ViewBuilder private var fill: some View {
        switch BackgroundStyle(rawValue: style) ?? .color {
        case .color: Color(red: red, green: green, blue: blue)
        case .checkerboard: Checkerboard()
        }
    }
}

/// A classic light/grey checkerboard, drawn to fill its bounds.
struct Checkerboard: View {
    var square: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            let cols = Int(ceil(size.width / square))
            let rows = Int(ceil(size.height / square))
            guard cols > 0, rows > 0 else { return }
            for row in 0..<rows {
                for col in 0..<cols where (row + col) % 2 == 1 {
                    let rect = CGRect(x: CGFloat(col) * square, y: CGFloat(row) * square, width: square, height: square)
                    context.fill(Path(rect), with: .color(Color(white: 0.78)))
                }
            }
        }
    }
}

/// The Settings window contents (tabbed for future expansion).
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 460)
    }
}

/// Appearance settings: the image-area background.
struct AppearanceSettings: View {
    @AppStorage(BackgroundSetting.styleKey) private var style = BackgroundSetting.defaultStyle
    @AppStorage(BackgroundSetting.redKey) private var red = BackgroundSetting.defaultRed
    @AppStorage(BackgroundSetting.greenKey) private var green = BackgroundSetting.defaultGreen
    @AppStorage(BackgroundSetting.blueKey) private var blue = BackgroundSetting.defaultBlue
    @AppStorage(BackgroundSetting.opacityKey) private var opacity = BackgroundSetting.defaultOpacity

    var body: some View {
        Form {
            Picker("Background", selection: $style) {
                ForEach(BackgroundStyle.allCases) { style in
                    Text(style.label).tag(style.rawValue)
                }
            }

            if BackgroundStyle(rawValue: style) == .color {
                LabeledContent("Presets") {
                    HStack(spacing: 6) {
                        ForEach(Self.presets, id: \.name) { preset in
                            Button {
                                red = preset.red; green = preset.green; blue = preset.blue
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(red: preset.red, green: preset.green, blue: preset.blue))
                                    .frame(width: 22, height: 22)
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
                        }
                    }
                }
                channelSlider("Red", value: $red)
                channelSlider("Green", value: $green)
                channelSlider("Blue", value: $blue)
            }

            LabeledContent("Opacity") {
                HStack {
                    Slider(value: $opacity, in: 0...1)
                    Text("\(Int((opacity * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            LabeledContent("Preview") {
                BackgroundFill()
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            }
        }
        .formStyle(.grouped)
        .scenePadding()
    }

    private func channelSlider(_ label: String, value: Binding<Double>) -> some View {
        LabeledContent(label) {
            HStack {
                Slider(value: value, in: 0...1)
                Text("\(Int((value.wrappedValue * 255).rounded()))")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private static let presets: [(name: String, red: Double, green: Double, blue: Double)] = [
        ("Black", 0, 0, 0),
        ("Charcoal", 0.15, 0.15, 0.16),
        ("Gray", 0.5, 0.5, 0.5),
        ("Silver", 0.85, 0.85, 0.85),
        ("White", 1, 1, 1),
    ]
}

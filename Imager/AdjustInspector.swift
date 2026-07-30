import SwiftUI

/// The inspector's two panes: the image's metadata, and its adjustments.
struct InspectorPanes: View {
    let model: ImageModel

    @State private var pane: Pane = .info

    enum Pane: String, CaseIterable, Identifiable {
        case info = "Info"
        case adjust = "Adjust"
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            Divider()

            switch pane {
            case .info:
                InfoInspector(info: model.info, url: model.url)
            case .adjust:
                AdjustInspector(model: model)
            }
        }
    }
}

/// Sliders for tonal and colour adjustments.
///
/// Values are held locally while dragging and pushed into the model as they change, so
/// the image updates live. The first change of a drag starts a new undo step and the
/// rest replace it, which is what keeps one drag to one step.
struct AdjustInspector: View {
    let model: ImageModel

    @State private var values = Adjustments.neutral
    @State private var sessionStarted = false
    @State private var dragging = false

    var body: some View {
        Form {
            // RAW development comes first because that is the order the pipeline runs in:
            // develop from sensor data, then adjust the result.
            if model.isRaw {
                Section("Develop RAW") {
                    RawControls(model: model)
                }
            }

            Section {
                slider("Exposure", \.exposure, in: Adjustments.exposureRange, format: exposureLabel)
                slider("Highlights", \.highlights, in: Adjustments.highlightsRange, format: plainLabel)
                slider("Shadows", \.shadows, in: Adjustments.shadowsRange, format: plainLabel)
            }

            Section {
                slider("Contrast", \.contrast, in: Adjustments.contrastRange, format: plainLabel)
                slider("Saturation", \.saturation, in: Adjustments.saturationRange, format: plainLabel)
                slider("Vibrance", \.vibrance, in: Adjustments.vibranceRange, format: plainLabel)
                slider("Hue", \.hue, in: Adjustments.hueRange, format: degreesLabel)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset") { reset() }
                        .disabled(values.isNeutral)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.image == nil)
        .onAppear { values = model.adjustments }
        // Follow the model when it changes underneath us, e.g. undo, revert, or
        // opening another image. Ignored mid-drag, where this view is the source.
        .onChange(of: model.adjustments) { _, latest in
            if !dragging { values = latest }
        }
    }

    // MARK: - Pieces

    private func slider(
        _ title: String,
        _ keyPath: WritableKeyPath<Adjustments, Double>,
        in range: ClosedRange<Double>,
        format: (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(values[keyPath: keyPath]))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: binding(keyPath), in: range) { editing in
                dragging = editing
                if !editing { sessionStarted = false }
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<Adjustments, Double>) -> Binding<Double> {
        Binding(
            get: { values[keyPath: keyPath] },
            set: { newValue in
                values[keyPath: keyPath] = newValue
                model.setAdjustments(values, continuingSession: sessionStarted)
                sessionStarted = true
            }
        )
    }

    private func reset() {
        values = .neutral
        sessionStarted = false
        model.setAdjustments(.neutral)
    }

    private func exposureLabel(_ value: Double) -> String { String(format: "%+.2f EV", value) }
    private func plainLabel(_ value: Double) -> String { String(format: "%.2f", value) }
    private func degreesLabel(_ value: Double) -> String { String(format: "%.0f°", value) }
}

/// Development controls for a RAW file: exposure and white balance from sensor data.
///
/// Dragging develops at reduced scale and lets go at full size, because a full-size develop is
/// around 160 ms however warm the decoder is, while a preview is about 7 ms.
private struct RawControls: View {
    let model: ImageModel

    @State private var values = RawSettings()
    @State private var sessionStarted = false
    @State private var dragging = false

    var body: some View {
        slider("Exposure", \.exposure, in: RawSettings.exposureRange) {
            String(format: "%+.2f EV", $0)
        }
        slider("Temperature", \.temperature, in: RawSettings.temperatureRange) {
            String(format: "%.0f K", $0)
        }
        slider("Tint", \.tint, in: RawSettings.tintRange) {
            String(format: "%+.0f", $0)
        }
        slider("Boost", \.boost, in: RawSettings.boostRange) {
            String(format: "%.2f", $0)
        }
        slider("Shadow Boost", \.boostShadow, in: RawSettings.boostRange) {
            String(format: "%.2f", $0)
        }

        // Only offered when the camera, decoder and system all support it: the underlying
        // property arrived in macOS 26.
        if model.rawSupport.highlightRecovery {
            Toggle("Highlight Recovery", isOn: Binding(
                get: { values.highlightRecovery },
                set: { newValue in
                    values.highlightRecovery = newValue
                    model.setRawSettings(values)
                }
            ))
        }

        HStack {
            Spacer()
            Button("Reset Development") {
                model.resetRawDevelopment()
                values = model.rawSettings ?? values
            }
            .disabled(model.rawSettings == model.rawDefaults)
        }
        .onAppear { values = model.rawSettings ?? RawSettings() }
        .onChange(of: model.rawSettings) { _, latest in
            if !dragging, let latest { values = latest }
        }
    }

    private func slider(
        _ title: String,
        _ keyPath: WritableKeyPath<RawSettings, Float>,
        in range: ClosedRange<Float>,
        format: (Float) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(values[keyPath: keyPath]))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(values[keyPath: keyPath]) },
                    set: { newValue in
                        values[keyPath: keyPath] = Float(newValue)
                        model.setRawSettings(values, continuingSession: sessionStarted, preview: dragging)
                        sessionStarted = true
                    }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            ) { editing in
                dragging = editing
                if !editing {
                    sessionStarted = false
                    // Back to full size now the drag has finished.
                    model.commitRawDevelopment()
                }
            }
        }
    }
}

import SwiftUI

/// Popover content for rotating and flipping the current image.
struct RotatePopover: View {
    let model: ImageModel
    @State private var fineAngle: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rotate & Flip").font(.headline)

            HStack(spacing: 8) {
                action("Rotate Left", "rotate.left") { model.rotate(byDegreesClockwise: -90) }
                action("Rotate Right", "rotate.right") { model.rotate(byDegreesClockwise: 90) }
                action("Rotate 180°", "arrow.2.circlepath") { model.rotate(byDegreesClockwise: 180) }
                Divider().frame(height: 20)
                action("Flip Horizontal", "arrow.left.and.right") { model.flip(horizontal: true) }
                action("Flip Vertical", "arrow.up.and.down") { model.flip(horizontal: false) }
            }

            Divider()

            Text("Fine rotate").font(.subheadline)
            HStack {
                Stepper(value: $fineAngle, in: 0.5...15, step: 0.5) {
                    Text(String(format: "%.1f°", fineAngle)).monospacedDigit()
                }
                .fixedSize()
                Spacer()
                Button {
                    model.rotate(byDegreesClockwise: -fineAngle)
                } label: {
                    Image(systemName: "rotate.left")
                }
                .help(String(format: "Rotate %.1f° left", fineAngle))
                Button {
                    model.rotate(byDegreesClockwise: fineAngle)
                } label: {
                    Image(systemName: "rotate.right")
                }
                .help(String(format: "Rotate %.1f° right", fineAngle))
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func action(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).frame(width: 26, height: 22)
        }
        .help(title)
    }
}

// Regenerates the test images in this folder.
//
//   swift data/make-test-images.swift data
//
// Everything is drawn straight into a CGContext of the exact pixel size. Going via
// NSImage.lockFocus would draw at the display's backing scale instead, silently
// producing images twice the intended size on a Retina Mac.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "data")

// MARK: - Canvas

/// A pixel buffer of an exact size, drawn into and written out as a PNG.
final class Canvas {
    let width: Int
    let height: Int
    private let buffer: UnsafeMutablePointer<UInt8>
    let context: CGContext

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        buffer.initialize(repeating: 0, count: width * height * 4)
        context = CGContext(
            data: buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    deinit { buffer.deallocate() }

    func setPixel(_ x: Int, _ y: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
        let offset = (y * width + x) * 4
        buffer[offset] = r
        buffer[offset + 1] = g
        buffer[offset + 2] = b
        buffer[offset + 3] = 255
    }

    /// Draws using AppKit into this exact-size context, rather than at screen scale.
    func drawWithAppKit(_ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    func write(to url: URL) throws {
        let cgImage = context.makeImage()!
        let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])!
        try data.write(to: url)
        print("  \(url.lastPathComponent)  \(cgImage.width)x\(cgImage.height)  \(data.count / 1024) KB")
    }

    /// Writes a JPEG carrying an EXIF capture time, which is what stacking groups by.
    func writeJPEG(to url: URL, taken: String, subSecond: String) throws {
        let cgImage = context.makeImage()!
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: taken,
                kCGImagePropertyExifSubsecTimeOriginal: subSecond,
            ],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        print("  \(url.lastPathComponent)  \(cgImage.width)x\(cgImage.height)  taken \(taken).\(subSecond)")
    }
}

// MARK: - Adjustment test pattern

func makeAdjustmentTestPattern(in directory: URL) throws {
    let width = 2400
    let bandHeight = 200
    let canvas = Canvas(width: width, height: bandHeight * 6)

    func greyRamp(band: Int, low: Double, high: Double) {
        for y in (band * bandHeight)..<((band + 1) * bandHeight) {
            for x in 0..<width {
                let t = Double(x) / Double(width - 1)
                let value = UInt8(max(0, min(255, (low + (high - low) * t).rounded())))
                canvas.setPixel(x, y, value, value, value)
            }
        }
    }

    func hueRamp(band: Int, saturation: Double, brightness: Double) {
        for y in (band * bandHeight)..<((band + 1) * bandHeight) {
            for x in 0..<width {
                let hue = Double(x) / Double(width - 1)
                let colour = NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
                    .usingColorSpace(.sRGB)!
                canvas.setPixel(x, y,
                                UInt8((colour.redComponent * 255).rounded()),
                                UInt8((colour.greenComponent * 255).rounded()),
                                UInt8((colour.blueComponent * 255).rounded()))
            }
        }
    }

    greyRamp(band: 0, low: 0, high: 255)      // full range, the smooth banding reference
    greyRamp(band: 1, low: 118, high: 138)    // ~20 levels stretched wide: the worst case
    greyRamp(band: 2, low: 200, high: 255)    // highlights
    greyRamp(band: 3, low: 0, high: 55)       // shadows
    hueRamp(band: 4, saturation: 1.0, brightness: 1.0)    // hue and saturation
    hueRamp(band: 5, saturation: 0.25, brightness: 0.85)  // vibrance moves this far more

    try canvas.write(to: directory.appendingPathComponent("adjustment-test.png"))
}

// MARK: - Slideshow set

func makeSlideshowSet(in directory: URL) throws {
    let slides: [(name: String, colour: NSColor)] = [
        ("1-red", .systemRed),
        ("2-green", .systemGreen),
        ("3-blue", .systemBlue),
        ("4-orange", .systemOrange),
        ("5-purple", .systemPurple),
    ]

    let folder = directory.appendingPathComponent("slideshow", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    for (index, slide) in slides.enumerated() {
        let canvas = Canvas(width: 1200, height: 800)
        canvas.drawWithAppKit {
            slide.colour.setFill()
            NSRect(x: 0, y: 0, width: canvas.width, height: canvas.height).fill()

            let label = NSAttributedString(string: "\(index + 1)", attributes: [
                .font: NSFont.systemFont(ofSize: 420, weight: .heavy),
                .foregroundColor: NSColor.white,
            ])
            let size = label.size()
            label.draw(at: NSPoint(
                x: (CGFloat(canvas.width) - size.width) / 2,
                y: (CGFloat(canvas.height) - size.height) / 2
            ))
        }
        try canvas.write(to: folder.appendingPathComponent("\(slide.name).png"))
    }
}

// MARK: - Stacking set

/// A folder shaped like a real shoot, so auto-stacking has something to find.
///
/// JPEG rather than PNG because the capture time lives in EXIF, which PNG does not carry -
/// the other test images here are invisible to stacking for exactly that reason.
///
/// The timings are chosen so the presets in the Stack Photos sheet each give a different
/// answer: half a second finds the burst alone, two seconds adds the bracket, and a minute
/// also picks up the two tries at the last frame.
func makeStackingSet(in directory: URL) throws {
    /// Seconds from the start of the shoot, and the label drawn on the frame.
    let frames: [(offset: Double, label: String)] = [
        (0.00, "burst 1"), (0.25, "burst 2"), (0.50, "burst 3"), (0.75, "burst 4"),
        (240, "single"),
        (400, "bracket -1"), (402, "bracket 0"), (404, "bracket +1"),
        (700, "try 1"), (720, "try 2"),
    ]
    // Every gap between groups is well over a minute, so the lone frame stays lone at every
    // threshold the sheet offers - at exactly 60s apart it would have joined the bracket.

    let folder = directory.appendingPathComponent("stacks", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    // A fixed start - 2025-03-03 12:30 UTC - so regenerating does not churn the files.
    // Written in local time, as a camera does, so the reading back matches.
    let start = Date(timeIntervalSince1970: 1_741_012_200)

    for (index, frame) in frames.enumerated() {
        let canvas = Canvas(width: 1200, height: 800)
        let hue = Double(index) / Double(frames.count)
        canvas.drawWithAppKit {
            NSColor(calibratedHue: hue, saturation: 0.45, brightness: 0.9, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: canvas.width, height: canvas.height).fill()

            let label = NSAttributedString(string: frame.label, attributes: [
                .font: NSFont.systemFont(ofSize: 110, weight: .semibold),
                .foregroundColor: NSColor.white,
            ])
            let size = label.size()
            label.draw(at: NSPoint(
                x: (CGFloat(canvas.width) - size.width) / 2,
                y: (CGFloat(canvas.height) - size.height) / 2
            ))
        }

        let moment = start.addingTimeInterval(frame.offset)
        // EXIF DateTimeOriginal holds whole seconds only; the fraction goes in SubsecTimeOriginal,
        // which is how frames inside a burst are told apart at all.
        let fraction = frame.offset - frame.offset.rounded(.down)
        let name = String(format: "shot-%02d.jpg", index + 1)
        try canvas.writeJPEG(
            to: folder.appendingPathComponent(name),
            taken: formatter.string(from: moment),
            subSecond: String(format: "%02d", Int((fraction * 100).rounded()))
        )
    }
}

// MARK: - Run

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
print("writing to \(outputDirectory.path)")
try makeAdjustmentTestPattern(in: outputDirectory)
try makeSlideshowSet(in: outputDirectory)
try makeStackingSet(in: outputDirectory)

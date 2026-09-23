// Build review sheets from real ./scripts/shoot.sh --capture-only window captures.
// Usage: swift mini-visualizer-contact.swift <captures-dir> <output-dir> [blue,classic,red,green,amber]
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 3 else {
    print("Usage: swift mini-visualizer-contact.swift <captures-dir> <output-dir> [palettes]")
    exit(64)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let palettes = (CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "blue,classic,red,green,amber")
    .split(separator: ",").map(String.init)
let styles = [
    ("classic", "Classic Spectrum"), ("smooth", "Smooth Spectrum"), ("dot", "Dot Spectrum"),
    ("mirrored", "Mirrored Spectrum"), ("line", "Line Waveform"), ("waterfall", "Waterfall"),
    ("particle", "Particle Waveform"), ("stereo", "Stereo Bars"),
]
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func load(_ style: String, _ palette: String) throws -> CGImage {
    let url = input.appendingPathComponent("\(style)-\(palette)-0.png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw CocoaError(.fileReadCorruptFile) }
    return image
}

func context(width: Int, height: Int) -> CGContext {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.028, green: 0.039, blue: 0.060, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context
}

func label(_ text: String, at point: CGPoint, in context: CGContext, size: CGFloat = 13) {
    let string = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("HelveticaNeue" as CFString, size, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.85, alpha: 1),
    ])
    context.textPosition = point
    CTLineDraw(CTLineCreateWithAttributedString(string), context)
}

func save(_ context: CGContext, _ name: String) throws {
    let url = output.appendingPathComponent(name)
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    print(url.path)
}

// Player context at its logical display size: keeps the navy/gold chrome and green typography.
for palette in palettes {
    let sheet = context(width: 1040, height: 1120)
    label("AmpX · \(palette.capitalized) · real music playback", at: CGPoint(x: 24, y: 1088), in: sheet, size: 19)
    label("Eight styles, captured sequentially from the live Player", at: CGPoint(x: 24, y: 1065), in: sheet)
    for (index, style) in styles.enumerated() {
        let image = try load(style.0, palette)
        let scale = CGFloat(image.width) / 490
        guard let crop = image.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: 223.5 * scale)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let x = CGFloat(24 + (index % 2) * 510)
        let top = CGFloat(1040 - (index / 2) * 259)
        label(style.1, at: CGPoint(x: x, y: top), in: sheet)
        sheet.draw(crop, in: CGRect(x: x, y: top - 234, width: 490, height: 223.5))
    }
    try save(sheet, "player-\(palette).png")
}

// Detail sheet uses original Retina mini pixels. No fabricated audio or substituted rendering.
let width = 24 + palettes.count * 299
let height = 1010
let detail = context(width: width, height: height)
detail.interpolationQuality = .none
let title = palettes.count == 1
    ? "AmpX · live mini visualizers"
    : "AmpX mini visualizers · live music · original Retina pixels"
label(title, at: CGPoint(x: 24, y: 982), in: detail, size: 17)
for (column, palette) in palettes.enumerated() {
    label(palette.capitalized, at: CGPoint(x: 24 + column * 299, y: 952), in: detail)
}
for (row, style) in styles.enumerated() {
    let top = CGFloat(922 - row * 114)
    label(style.1, at: CGPoint(x: 24, y: top + 12), in: detail)
    for (column, palette) in palettes.enumerated() {
        let image = try load(style.0, palette)
        let scale = CGFloat(image.width) / 490
        // AmpXMetrics: content starts below the 28.5-point header; spectrum is (33,57,137.5,41).
        let rect = CGRect(x: 33 * scale, y: 85.5 * scale, width: 137.5 * scale, height: 41 * scale)
        guard let crop = image.cropping(to: rect) else { throw CocoaError(.fileReadCorruptFile) }
        detail.draw(crop, in: CGRect(x: CGFloat(24 + column * 299), y: top - 82, width: 275, height: 82))
    }
}
try save(detail, "all-minis.png")

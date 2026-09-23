import AppKit
import CoreGraphics

struct AmpXLabel {
    var text: String
    var color: NSColor
    var fontSize: CGFloat
    var weight: NSFont.Weight
    var alignment: NSTextAlignment
    /// Additional advance between glyphs, in points.
    var tracking: CGFloat

    init(
        text: String,
        color: NSColor,
        fontSize: CGFloat,
        weight: NSFont.Weight = .regular,
        alignment: NSTextAlignment = .left,
        tracking: CGFloat = 0
    ) {
        self.text = text
        self.color = color
        self.fontSize = fontSize
        self.weight = weight
        self.alignment = alignment
        self.tracking = tracking
    }

    func font(skin: any AmpXSkin) -> NSFont {
        skin.font(size: self.fontSize, weight: self.weight)
    }

    /// Single-line advance size; wrapping is never implied.
    func measuredSize(skin: any AmpXSkin) -> CGSize {
        self.attributedString(skin: skin, paragraph: nil).size()
    }

    /// Visible glyph bounds relative to the line origin: x from the left edge, y up from the baseline.
    func inkBounds(skin: any AmpXSkin) -> CGRect {
        let line = CTLineCreateWithAttributedString(attributedString(skin: skin, paragraph: nil))
        return CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    }

    /// Typographic box of a single line whose baseline is at `baseline` (flipped coordinates).
    func lineRect(x: CGFloat, baseline: CGFloat, skin: any AmpXSkin) -> CGRect {
        let font = font(skin: skin)
        let width = self.measuredSize(skin: skin).width
        return CGRect(x: x, y: baseline - font.ascender, width: width, height: font.ascender - font.descender)
    }

    /// Draws one line with its baseline at `baseline`. `x` is the left edge, or the center/right edge
    /// for centered/right alignment.
    func draw(x: CGFloat, baseline: CGFloat, context: CGContext, skin: any AmpXSkin) {
        let font = font(skin: skin)
        let attributed = self.attributedString(skin: skin, paragraph: nil)
        let width = attributed.size().width
        let originX: CGFloat = switch self.alignment {
        case .center: x - width / 2
        case .right: x - width
        default: x
        }
        // Stem darkening differs between layer and offscreen contexts; disable it so both match.
        context.saveGState()
        context.setShouldSmoothFonts(false)
        attributed.draw(at: CGPoint(x: originX, y: baseline - font.ascender))
        context.restoreGState()
    }

    func draw(in rect: CGRect, context: CGContext, skin: any AmpXSkin) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = self.alignment

        let attributed = self.attributedString(skin: skin, paragraph: paragraph)
        let boundingRect = rect.insetBy(dx: 0, dy: 1)
        let size = attributed.boundingRect(
            with: CGSize(width: boundingRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size

        let originY = boundingRect.minY + (boundingRect.height - size.height) / 2
        let drawRect = CGRect(x: boundingRect.minX, y: originY, width: boundingRect.width, height: size.height)
        context.saveGState()
        context.setShouldSmoothFonts(false)
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        context.restoreGState()
    }

    private func attributedString(skin: any AmpXSkin, paragraph: NSParagraphStyle?) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: self.font(skin: skin),
            .foregroundColor: self.color,
        ]
        if self.tracking != 0 {
            attributes[.kern] = self.tracking
        }
        if let paragraph {
            attributes[.paragraphStyle] = paragraph
        }
        return NSAttributedString(string: self.text, attributes: attributes)
    }
}

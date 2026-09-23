import AppKit
import CoreGraphics

/// Seven-segment timer glyphs drawn in fixed-size cells so digits never stretch as the text changes.
struct AmpXSegmentDigits {
    struct Metrics {
        var digitSize: CGSize
        var gap: CGFloat
        var colonWidth: CGFloat
        var minusWidth: CGFloat
        var stroke: CGFloat
        var joint: CGFloat
        var colonDot: CGSize
    }

    /// Fitted to the `01:51` reference timer (ReferenceMeasurementsV2 digits 17–21).
    static let referenceMetrics = Metrics(
        digitSize: CGSize(width: 14.5, height: 25),
        gap: 1.5,
        colonWidth: 18,
        minusWidth: 9,
        stroke: 2.4,
        joint: 0.6,
        colonDot: CGSize(width: 3.25, height: 3.5)
    )

    let skin: any AmpXSkin
    var metrics: Metrics = referenceMetrics

    /// Right-aligned cells, vertically centered in `rect`. Cells may extend left of `rect` for long text.
    static func cells(
        for text: String,
        in rect: CGRect,
        metrics: Metrics = referenceMetrics
    ) -> [(character: Character, rect: CGRect)] {
        let height = metrics.digitSize.height
        let y = rect.minY + (rect.height - height) / 2
        var maxX = rect.maxX
        var cells: [(character: Character, rect: CGRect)] = []
        for character in text.reversed() {
            let width: CGFloat = switch character {
            case ":": metrics.colonWidth
            case "-": metrics.minusWidth
            default: metrics.digitSize.width
            }
            cells.append((character, CGRect(x: maxX - width, y: y, width: width, height: height)))
            maxX -= width + metrics.gap
        }
        return cells.reversed()
    }

    func draw(_ text: String, in rect: CGRect, context: CGContext) {
        context.setFillColor(self.skin.green.cgColor)
        for cell in Self.cells(for: text, in: rect, metrics: self.metrics) {
            switch cell.character {
            case ":":
                self.drawColon(in: cell.rect, context: context)
            case "-":
                context.addPath(self.horizontalSegment(in: cell.rect, centerY: cell.rect.midY))
                context.fillPath()
            default:
                self.drawDigit(cell.character, in: cell.rect, context: context)
            }
        }
    }

    private func drawDigit(_ character: Character, in rect: CGRect, context: CGContext) {
        let lit = self.segments(for: character)
        let t = self.metrics.stroke
        let path = CGMutablePath()
        if lit.contains("a") {
            path.addPath(self.horizontalSegment(in: rect, centerY: rect.minY + t / 2))
        }
        if lit.contains("g") {
            path.addPath(self.horizontalSegment(in: rect, centerY: rect.midY))
        }
        if lit.contains("d") {
            path.addPath(self.horizontalSegment(in: rect, centerY: rect.maxY - t / 2))
        }
        let upper = (rect.minY, rect.midY)
        let lower = (rect.midY, rect.maxY)
        if lit.contains("f") {
            path.addPath(self.verticalSegment(centerX: rect.minX + t / 2, span: upper))
        }
        if lit.contains("b") {
            path.addPath(self.verticalSegment(centerX: rect.maxX - t / 2, span: upper))
        }
        if lit.contains("e") {
            path.addPath(self.verticalSegment(centerX: rect.minX + t / 2, span: lower))
        }
        if lit.contains("c") {
            path.addPath(self.verticalSegment(centerX: rect.maxX - t / 2, span: lower))
        }
        context.addPath(path)
        context.fillPath()
    }

    /// Hexagonal segment with pointed ends, leaving `joint` clearance at each corner.
    private func horizontalSegment(in rect: CGRect, centerY: CGFloat) -> CGPath {
        let half = self.metrics.stroke / 2
        let x0 = rect.minX + self.metrics.joint
        let x1 = rect.maxX - self.metrics.joint
        let path = CGMutablePath()
        path.addLines(between: [
            CGPoint(x: x0, y: centerY),
            CGPoint(x: x0 + half, y: centerY - half),
            CGPoint(x: x1 - half, y: centerY - half),
            CGPoint(x: x1, y: centerY),
            CGPoint(x: x1 - half, y: centerY + half),
            CGPoint(x: x0 + half, y: centerY + half),
        ])
        path.closeSubpath()
        return path
    }

    private func verticalSegment(centerX: CGFloat, span: (CGFloat, CGFloat)) -> CGPath {
        let half = self.metrics.stroke / 2
        let y0 = span.0 + self.metrics.joint
        let y1 = span.1 - self.metrics.joint
        let path = CGMutablePath()
        path.addLines(between: [
            CGPoint(x: centerX, y: y0),
            CGPoint(x: centerX + half, y: y0 + half),
            CGPoint(x: centerX + half, y: y1 - half),
            CGPoint(x: centerX, y: y1),
            CGPoint(x: centerX - half, y: y1 - half),
            CGPoint(x: centerX - half, y: y0 + half),
        ])
        path.closeSubpath()
        return path
    }

    private func drawColon(in rect: CGRect, context: CGContext) {
        let dot = self.metrics.colonDot
        let x = rect.midX - dot.width / 2
        for fraction in [0.29, 0.71] {
            let centerY = rect.minY + rect.height * fraction
            context.fill(CGRect(x: x, y: centerY - dot.height / 2, width: dot.width, height: dot.height))
        }
    }

    private func segments(for character: Character) -> String {
        switch character {
        case "0": "abcdef"
        case "1": "bc"
        case "2": "abdeg"
        case "3": "abcdg"
        case "4": "bcfg"
        case "5": "acdfg"
        case "6": "acdefg"
        case "7": "abc"
        case "8": "abcdefg"
        case "9": "abcdfg"
        default: ""
        }
    }
}

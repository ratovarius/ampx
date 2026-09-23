import AppKit
import CoreGraphics

/// Vector glyphs. `rect` is the glyph's visible ink box.
enum AmpXIcon {
    case play
    case pause
    case stop
    case previous
    case next
    case eject
    case `repeat`
    case menu
    case collapse
    case expand
    case minimize
    case close
    case brand
    case dropdown

    func draw(in rect: CGRect, context: CGContext, skin: any AmpXSkin, color: NSColor? = nil) {
        let tint = color ?? skin.text
        context.saveGState()
        context.setFillColor(tint.cgColor)
        context.setStrokeColor(tint.cgColor)

        switch self {
        case .play:
            self.fillPolygon([
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.minX, y: rect.maxY),
            ], context: context)
        case .pause:
            let barWidth = rect.width * 0.34
            context.fill(CGRect(x: rect.minX, y: rect.minY, width: barWidth, height: rect.height))
            context.fill(CGRect(x: rect.maxX - barWidth, y: rect.minY, width: barWidth, height: rect.height))
        case .stop:
            context.fill(rect)
        case .previous:
            let barWidth = rect.width * 0.16
            context.fill(CGRect(x: rect.minX, y: rect.minY, width: barWidth, height: rect.height))
            self.fillPolygon([
                CGPoint(x: rect.minX + rect.width * 0.24, y: rect.midY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
            ], context: context)
        case .next:
            let barWidth = rect.width * 0.16
            context.fill(CGRect(x: rect.maxX - barWidth, y: rect.minY, width: barWidth, height: rect.height))
            self.fillPolygon([
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.midY),
                CGPoint(x: rect.minX, y: rect.maxY),
            ], context: context)
        case .eject:
            let barHeight = rect.height * 0.2
            self.fillPolygon([
                CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.6),
                CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.6),
            ], context: context)
            context.fill(CGRect(x: rect.minX, y: rect.maxY - barHeight, width: rect.width, height: barHeight))
        case .repeat:
            self.drawRepeat(in: rect, context: context)
        case .menu:
            let barHeight = rect.height * 0.18
            for row in 0 ..< 3 {
                let y = rect.minY + (rect.height - barHeight) * CGFloat(row) / 2
                context.fill(CGRect(x: rect.minX, y: y, width: rect.width, height: barHeight))
            }
        case .collapse:
            self.drawFoldedShade(in: rect, context: context)
        case .expand:
            context.setLineWidth(max(0.8, rect.width * 0.13))
            context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        case .minimize:
            context.fill(rect)
            context.setFillColor(NSColor.white.withAlphaComponent(0.45).cgColor)
            context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.25))
        case .close:
            context.setLineWidth(max(1, rect.width * 0.18))
            context.setLineCap(.butt)
            context.strokeLineSegments(between: [
                CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY),
            ])
        case .brand:
            self.drawSpectrum(in: rect, context: context, tint: tint)
        case .dropdown:
            self.fillPolygon([
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.midX, y: rect.maxY),
            ], context: context)
        }

        context.restoreGState()
    }

    private func fillPolygon(_ points: [CGPoint], context: CGContext) {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
    }

    private func drawRepeat(in rect: CGRect, context: CGContext) {
        let stroke = min(rect.width, rect.height) * 0.14
        let arrow = rect.height * 0.26
        let radius = rect.height * 0.28
        let top = rect.minY + arrow / 2
        let bottom = rect.maxY - arrow / 2
        let left = rect.minX + stroke / 2
        let right = rect.maxX - stroke / 2

        let path = CGMutablePath()
        path.move(to: CGPoint(x: left, y: rect.midY + stroke / 2))
        path.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: right, y: top), radius: radius)
        path.addLine(to: CGPoint(x: right - arrow, y: top))
        path.move(to: CGPoint(x: right, y: rect.midY - stroke / 2))
        path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: left, y: bottom), radius: radius)
        path.addLine(to: CGPoint(x: left + arrow, y: bottom))
        context.setLineWidth(stroke)
        context.addPath(path)
        context.strokePath()

        self.fillPolygon([
            CGPoint(x: right - arrow * 1.1, y: top - arrow / 2),
            CGPoint(x: rect.maxX, y: top),
            CGPoint(x: right - arrow * 1.1, y: top + arrow / 2),
        ], context: context)
        self.fillPolygon([
            CGPoint(x: left + arrow * 1.1, y: bottom - arrow / 2),
            CGPoint(x: rect.minX, y: bottom),
            CGPoint(x: left + arrow * 1.1, y: bottom + arrow / 2),
        ], context: context)
    }

    /// Five spectrum bars, tallest in the middle, in an 18 × 16 pt design box (flipped: y grows down).
    private func drawSpectrum(in rect: CGRect, context: CGContext, tint: NSColor) {
        let heights: [CGFloat] = [6, 10, 16, 12.5, 8]
        let barWidth: CGFloat = 2.8
        let pitch: CGFloat = 3.8
        let scaleX = rect.width / 18
        let scaleY = rect.height / 16
        let bars = heights.enumerated().map { index, height in
            CGRect(
                x: rect.minX + CGFloat(index) * pitch * scaleX,
                y: rect.maxY - height * scaleY,
                width: barWidth * scaleX,
                height: height * scaleY
            )
        }
        let outline = 0.5 * scaleX
        context.setFillColor(NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 0.85).cgColor)
        context.fill(bars.map { $0.insetBy(dx: -outline, dy: -outline) })
        context.setFillColor(tint.cgColor)
        context.fill(bars)
    }

    /// Windowshade "folded" glyph: top bar, up chevron, inset bottom bar (flipped: y grows down).
    private func drawFoldedShade(in rect: CGRect, context: CGContext) {
        let line = max(1, rect.width * 0.15)
        context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: line))
        context.fill(CGRect(x: rect.minX + rect.width * 0.08, y: rect.maxY - line, width: rect.width * 0.84, height: line))
        context.setLineWidth(line)
        context.setLineCap(.butt)
        context.setLineJoin(.miter)
        let chevron = CGMutablePath()
        chevron.addLines(between: [
            CGPoint(x: rect.midX - rect.width * 0.28, y: rect.minY + rect.height * 0.68),
            CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.40),
            CGPoint(x: rect.midX + rect.width * 0.28, y: rect.minY + rect.height * 0.68),
        ])
        context.addPath(chevron)
        context.strokePath()
    }
}

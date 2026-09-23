import AppKit
import CoreGraphics

enum AmpXCompactSliderDrawing {
    static func draw(
        track: CGRect, thumb: CGRect, fill: AmpXTrackFill, value: Double, thumbStyle: AmpXFaceStyle,
        skin: any AmpXSkin, context: CGContext, backingScale: CGFloat
    ) {
        skin.displayWell(track, in: context, backingScale: backingScale)
        let inner = track.insetBy(dx: 1.5, dy: 1.5)
        if value > 0, inner.width > 0, inner.height > 0 {
            let lit = CGRect(x: inner.minX, y: inner.minY, width: max(0, thumb.midX - inner.minX), height: inner.height)
            context.saveGState()
            context.clip(to: inner.intersection(lit))
            switch fill {
            case .volume:
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [skin.orange.cgColor, skin.yellow.cgColor] as CFArray,
                    locations: [0, 1]
                ) {
                    context.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: inner.minX, y: inner.midY),
                        end: CGPoint(x: inner.maxX, y: inner.midY),
                        options: []
                    )
                }
                context.setFillColor(NSColor.white.withAlphaComponent(0.3).cgColor)
                context.fill(CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: 0.5))
            case .balance:
                let pitch = 26 * AmpXCompactMetrics.factor
                let width = 21 * AmpXCompactMetrics.factor
                var x = inner.minX
                while x < inner.maxX {
                    let cell = CGRect(x: x, y: inner.minY, width: width, height: inner.height)
                    context.setFillColor(NSColor(srgbRed: 0.06, green: 1, blue: 0.02, alpha: 1).cgColor)
                    context.fill(cell)
                    context.setFillColor(NSColor(srgbRed: 0.45, green: 1, blue: 0.06, alpha: 1).cgColor)
                    context.fill(CGRect(x: x, y: inner.minY, width: width, height: inner.height * 0.3))
                    x += pitch
                }
            }
            context.restoreGState()
        }
        skin.metallicThumb(thumb, material: .steel, style: thumbStyle, in: context, backingScale: backingScale)
    }
}

import AppKit
import CoreGraphics

struct ClassicModernSkin: AmpXSkin {
    let background = NSColor(srgbRed: 0.043, green: 0.059, blue: 0.094, alpha: 1)
    let panel = NSColor(srgbRed: 0.082, green: 0.106, blue: 0.161, alpha: 1)
    let panelLight = NSColor(srgbRed: 0.125, green: 0.157, blue: 0.227, alpha: 1)
    let border = NSColor(srgbRed: 0.231, green: 0.275, blue: 0.361, alpha: 1)
    let borderHighlight = NSColor(srgbRed: 0.396, green: 0.443, blue: 0.529, alpha: 1)
    let borderDark = NSColor(srgbRed: 0.035, green: 0.047, blue: 0.078, alpha: 1)
    let text = NSColor(srgbRed: 0.902, green: 0.929, blue: 0.969, alpha: 1)
    let textDim = NSColor(srgbRed: 0.545, green: 0.588, blue: 0.667, alpha: 1)
    let selection = NSColor(srgbRed: 0.13, green: 0.18, blue: 0.29, alpha: 1)
    let green = NSColor(hex: 0x00FF32)
    let yellow = NSColor(hex: 0xFFD21A)
    let orange = NSColor(hex: 0xFF9D00)
    let display = NSColor(hex: 0x000000)
    let gold = NSColor(srgbRed: 0.749, green: 0.627, blue: 0.322, alpha: 1)
    let goldLight = NSColor(srgbRed: 1.0, green: 0.953, blue: 0.286, alpha: 1)
    // Light ink on the Midnight Hardware navy face.
    let faceInk = NSColor(srgbRed: 238 / 255, green: 243 / 255, blue: 252 / 255, alpha: 1)
    let faceInkDim = NSColor(srgbRed: 128 / 255, green: 141 / 255, blue: 163 / 255, alpha: 1)
    // The navy face is dark enough for the bright accents themselves.
    let faceGreen = NSColor(hex: 0x00FF32)
    let faceAmber = NSColor(hex: 0xFFD21A)
    let faceOrange = NSColor(hex: 0xFF9D00)

    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        AmpXFonts.font(size: size, weight: weight)
    }

    func bevel(_ rect: CGRect, in context: CGContext, backingScale: CGFloat) {
        self.raisedFace(rect, style: .surface, in: context, backingScale: backingScale)
    }

    func inset(_ rect: CGRect, in context: CGContext, backingScale: CGFloat) {
        let inner = AmpXPixelGrid.strokeRect(rect.insetBy(dx: 1, dy: 1), lineWidth: 1, backingScale: backingScale)
        context.setFillColor(self.panel.cgColor)
        context.fill(inner)

        context.setStrokeColor(self.borderDark.cgColor)
        context.setLineWidth(1 / backingScale)
        context.stroke(inner)
    }

    func accentLine(_ rect: CGRect, in context: CGContext, backingScale: CGFloat) {
        let line = CGRect(
            x: AmpXPixelGrid.align(rect.minX, backingScale: backingScale),
            y: AmpXPixelGrid.align(rect.minY, backingScale: backingScale),
            width: rect.width,
            height: max(1 / backingScale, AmpXPixelGrid.align(rect.height, backingScale: backingScale))
        )
        context.setFillColor(self.yellow.cgColor)
        context.fill(line)
    }

    // MARK: - Layered materials (edge bands sampled from ReferenceMeasurementsV2 edge profiles)

    func displayWell(_ rect: CGRect, in context: CGContext, backingScale: CGFloat) {
        let well = self.snapped(rect, backingScale: backingScale)
        let unit = self.bandUnit(for: well)
        context.setFillColor(Palette.wellBlack.cgColor)
        context.fill(well)
        self.drawBands(in: well, unit: unit, context: context, edges: Edges(
            top: [rgb(35, 43, 69), rgb(52, 64, 92), rgb(28, 35, 55)],
            left: [rgb(38, 48, 72), rgb(50, 62, 88), rgb(24, 31, 50)],
            bottom: [rgb(56, 68, 96), rgb(44, 55, 80), rgb(16, 20, 32)],
            right: [rgb(50, 62, 88), rgb(44, 55, 80), rgb(20, 26, 42)]
        ))
    }

    func panelFrame(_ rect: CGRect, contentFrame: CGRect?, in context: CGContext, backingScale: CGFloat) {
        let panelRect = self.snapped(rect, backingScale: backingScale)
        context.setFillColor(Palette.panel.cgColor)
        context.fill(panelRect)
        self.drawBands(in: panelRect, unit: 0.5, context: context, edges: Edges(
            top: [rgb(42, 51, 66), rgb(79, 92, 120), rgb(71, 84, 118), rgb(76, 90, 122), rgb(31, 44, 67)],
            left: [rgb(55, 65, 91), rgb(57, 69, 98), rgb(47, 57, 85), rgb(57, 71, 99), rgb(70, 89, 121), rgb(31, 39, 59)],
            bottom: [
                rgb(25, 31, 49), rgb(48, 59, 86), rgb(41, 52, 79), rgb(42, 53, 81),
                rgb(42, 53, 81), rgb(45, 56, 84), rgb(34, 44, 67), rgb(13, 21, 41),
            ],
            right: [rgb(40, 48, 70), rgb(57, 69, 98), rgb(47, 57, 85), rgb(57, 71, 99), rgb(64, 80, 110), rgb(31, 39, 59)]
        ))

        guard let contentFrame else { return }
        let frame = self.snapped(contentFrame, backingScale: backingScale)
        context.setFillColor(rgb(8, 12, 24).cgColor)
        context.fill(frame.insetBy(dx: -0.5, dy: -0.5))
        self.drawVerticalGradient(
            in: frame,
            stops: [(0, rgb(27, 38, 62)), (1, rgb(23, 32, 54))],
            context: context
        )
        let frameSide = [
            rgb(42, 55, 78), rgb(46, 60, 84), rgb(35, 45, 67), rgb(51, 61, 86),
            rgb(80, 91, 118), rgb(91, 104, 132), rgb(44, 55, 81),
        ]
        self.drawBands(in: frame, unit: 0.5, context: context, edges: Edges(
            top: [rgb(60, 72, 97), rgb(80, 99, 130), rgb(67, 82, 110), rgb(26, 35, 55)],
            left: frameSide,
            bottom: [rgb(81, 94, 127), rgb(101, 115, 148), rgb(47, 56, 82), rgb(11, 15, 31)],
            right: frameSide
        ))
    }

    /// Midnight Hardware: one navy key material for every button and handle. Hover lifts the face and
    /// brightens the bevel; a press darkens both but keeps the bevel raised.
    private enum Hardware {
        static let radius: CGFloat = 2
        static let face: [(CGFloat, NSColor)] = [(0, rgb(49, 64, 89)), (0.48, rgb(39, 53, 78)), (1, rgb(30, 42, 64))]
        static let hovered: [(CGFloat, NSColor)] = [(0, rgb(57, 72, 97)), (0.48, rgb(47, 61, 86)), (1, rgb(38, 50, 72))]
        static let pressed: [(CGFloat, NSColor)] = [(0, rgb(39, 54, 79)), (0.48, rgb(31, 45, 69)), (1, rgb(24, 36, 56))]
        static let edges = Edges(
            top: [rgb(6, 9, 16), rgb(93, 112, 141), rgb(62, 79, 106)],
            left: [rgb(6, 9, 16), rgb(76, 95, 124), rgb(52, 69, 96)],
            bottom: [rgb(3, 5, 13), rgb(12, 20, 35), rgb(23, 34, 53)],
            right: [rgb(3, 5, 13), rgb(17, 28, 45), rgb(31, 44, 65)]
        )
        static let menuFace: [(CGFloat, NSColor)] = [(0, rgb(252, 165, 48)), (0.5, rgb(245, 150, 36)), (1, rgb(232, 126, 22))]
        static let menuHovered: [(CGFloat, NSColor)] = [(0, rgb(255, 173, 56)), (1, rgb(240, 134, 30))]
        static let menuPressed: [(CGFloat, NSColor)] = [(0, rgb(220, 133, 25)), (1, rgb(200, 103, 15))]
        static let menuEdges = Edges(
            top: [rgb(6, 6, 7), rgb(125, 116, 61), rgb(255, 230, 99), rgb(242, 170, 48)],
            left: [rgb(6, 6, 7), rgb(196, 138, 52), rgb(250, 190, 80)],
            bottom: [rgb(11, 6, 14), rgb(122, 46, 14), rgb(203, 80, 9), rgb(200, 93, 13)],
            right: [rgb(11, 6, 14), rgb(150, 70, 15), rgb(215, 110, 20)]
        )
        static let hoverBands: CGFloat = 1.12
        static let pressedBands: CGFloat = 0.78
    }

    func raisedFace(_ rect: CGRect, style: AmpXFaceStyle, in context: CGContext, backingScale: CGFloat) {
        let face = self.snapped(rect, backingScale: backingScale)
        context.saveGState()
        context.addPath(CGPath(roundedRect: face, cornerWidth: Hardware.radius, cornerHeight: Hardware.radius, transform: nil))
        context.clip()

        switch style {
        case .normal:
            self.drawVerticalGradient(in: face, stops: Hardware.face, context: context)
            self.drawBands(in: face, unit: 0.5, context: context, edges: Hardware.edges)
        case .hovered:
            self.drawVerticalGradient(in: face, stops: Hardware.hovered, context: context)
            self.drawBands(in: face, unit: 0.5, context: context, edges: Hardware.edges.scaled(Hardware.hoverBands))
        case .pressed:
            self.drawVerticalGradient(in: face, stops: Hardware.pressed, context: context)
            self.drawBands(in: face, unit: 0.5, context: context, edges: Hardware.edges.scaled(Hardware.pressedBands))
        case .menu:
            self.drawVerticalGradient(in: face, stops: Hardware.menuFace, context: context)
            self.drawBands(in: face, unit: 0.5, context: context, edges: Hardware.menuEdges)
        case .menuHovered:
            self.drawVerticalGradient(in: face, stops: Hardware.menuHovered, context: context)
            self.drawBands(in: face, unit: 0.5, context: context, edges: Hardware.menuEdges.scaled(Hardware.hoverBands))
        case .menuPressed:
            self.drawVerticalGradient(in: face, stops: Hardware.menuPressed, context: context)
            self.drawBands(in: face, unit: 0.5, context: context, edges: Hardware.menuEdges.scaled(Hardware.pressedBands))
        case .surface:
            self.drawVerticalGradient(
                in: face,
                stops: [(0, rgb(39, 51, 76)), (1, rgb(31, 42, 64))],
                context: context
            )
            self.drawBands(in: face, unit: 0.5, context: context, edges: Edges(
                top: [rgb(6, 9, 16), rgb(25, 29, 40), rgb(110, 125, 150), rgb(111, 131, 159), rgb(89, 105, 129)],
                left: [rgb(6, 9, 16), rgb(60, 70, 90), rgb(98, 113, 139), rgb(58, 70, 94)],
                bottom: [rgb(3, 5, 13), rgb(1, 2, 8), rgb(7, 14, 26), rgb(15, 25, 41), rgb(16, 23, 40), rgb(21, 28, 46)],
                right: [rgb(3, 5, 12), rgb(14, 20, 34), rgb(26, 35, 52)]
            ))
        }
        context.restoreGState()
    }

    func headerRule(_ rect: CGRect, in context: CGContext, backingScale: CGFloat) {
        let lineHeight = rect.height * 3.5 / 9.5
        let upper = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: lineHeight)
        let lower = CGRect(x: rect.minX, y: rect.maxY - lineHeight, width: rect.width, height: lineHeight)
        self.fillRows(in: self.snapped(upper, backingScale: backingScale), colors: [
            rgb(108, 116, 122), rgb(247, 250, 254), rgb(212, 193, 133), rgb(133, 93, 8),
            rgb(215, 194, 100), rgb(255, 255, 242), rgb(182, 185, 175),
        ], context: context)
        self.fillRows(in: self.snapped(lower, backingScale: backingScale), colors: [
            rgb(29, 33, 43), rgb(216, 218, 223), rgb(240, 224, 160), rgb(167, 112, 12),
            rgb(212, 150, 5), rgb(253, 220, 46), rgb(202, 178, 73),
        ], context: context)
    }

    func dotGrid(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        context.setFillColor(rgb(26, 33, 45).cgColor)
        var y = rect.minY + 1.15
        while y < rect.maxY {
            var x = rect.minX + 1.35
            while x < rect.maxX {
                context.fill(CGRect(x: x, y: y, width: 1.5, height: 2))
                x += 4.25
            }
            y += 5
        }
        context.restoreGState()
    }

    func sliderTrack(
        _ rect: CGRect,
        fill: AmpXTrackFill,
        fraction: Double,
        in context: CGContext,
        backingScale: CGFloat
    ) {
        let track = self.snapped(rect, backingScale: backingScale)
        let ramp = AmpXSliderColorRamp.color(for: fill, fraction: fraction)
        let color = TrackColor(r: ramp.r, g: ramp.g, b: ramp.b)
        // Winamp's full-width bar: the ramp color spans the whole track; only its color follows the value.
        self.drawTrackShell(track, context: context) { inner in
            self.drawVerticalGradient(in: inner, stops: [
                (0, rgb(color.r * 0.88, color.g * 0.85, color.b)),
                (0.2, rgb(color.r, color.g, color.b)),
                (0.8, rgb(color.r, color.g, color.b)),
                (1, rgb(min(255, color.r + 8), min(255, color.g + 50), min(255, color.b + 110))),
            ], context: context)
        }
    }

    func seekWell(_: CGRect, track: CGRect, in context: CGContext, backingScale: CGFloat) {
        self.neutralTrack(track, in: context, backingScale: backingScale)
    }

    func neutralTrack(_ rect: CGRect, in context: CGContext, backingScale: CGFloat) {
        self.drawTrackShell(self.snapped(rect, backingScale: backingScale), context: context) { inner in
            self.drawVerticalGradient(in: inner, stops: [(0, rgb(12, 18, 33)), (1, rgb(17, 26, 44))], context: context)
        }
    }

    /// Shared track construction: a 0.5 pt steel ring, a lower lip 1 pt down, a black channel and the fill
    /// inset 1.5 pt, all on the 2 pt key radius.
    private func drawTrackShell(_ track: CGRect, context: CGContext, fill: (CGRect) -> Void) {
        func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
            let r = min(radius, rect.width / 2, rect.height / 2)
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        }
        let radius = Hardware.radius
        context.addPath(rounded(track.insetBy(dx: -0.5, dy: -0.5), radius + 0.5))
        context.setFillColor(rgb(58, 70, 90).cgColor)
        context.fillPath()
        context.addPath(rounded(track.offsetBy(dx: 0, dy: 1), radius))
        context.setFillColor(rgb(88, 106, 130).cgColor)
        context.fillPath()
        context.addPath(rounded(track, radius))
        context.setFillColor(rgb(2, 3, 6).cgColor)
        context.fillPath()

        let inner = track.insetBy(dx: 1.5, dy: 1.5)
        guard inner.width > 0, inner.height > 0 else { return }
        context.saveGState()
        context.addPath(rounded(inner, 0.5))
        context.clip()
        fill(inner)
        context.restoreGState()
    }

    /// Every handle is a key: the shared face, plus three grip cuts across its travel.
    func metallicThumb(
        _ rect: CGRect,
        material: AmpXThumbMaterial,
        style: AmpXFaceStyle,
        in context: CGContext,
        backingScale: CGFloat
    ) {
        let thumb = self.snapped(rect, backingScale: backingScale)
        self.raisedFace(thumb, style: style, in: context, backingScale: backingScale)
        let sink: CGFloat = style.isPressed ? 0.5 : 0
        context.setFillColor(self.faceInk.cgColor)
        for offset: CGFloat in [-3, 0, 3] {
            let cut = material.travelsVertically
                ? CGRect(x: thumb.midX - 4, y: thumb.midY + offset - 0.5 + sink, width: 8, height: 1)
                : CGRect(x: thumb.midX + offset - 0.5, y: thumb.midY - 4 + sink, width: 1, height: 8)
            context.fill(cut)
        }
    }

    // MARK: - Band drawing

    private struct TrackColor {
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat
    }

    private struct Edges {
        var top: [NSColor]
        var left: [NSColor]
        var bottom: [NSColor]
        var right: [NSColor]

        /// Every band's RGB multiplied by `factor`, clamped to 1.
        func scaled(_ factor: CGFloat) -> Edges {
            func scale(_ colors: [NSColor]) -> [NSColor] {
                colors.map { color in
                    let c = color.usingColorSpace(.sRGB) ?? color
                    return NSColor(
                        srgbRed: min(1, c.redComponent * factor),
                        green: min(1, c.greenComponent * factor),
                        blue: min(1, c.blueComponent * factor),
                        alpha: c.alphaComponent
                    )
                }
            }
            return Edges(top: scale(self.top), left: scale(self.left), bottom: scale(self.bottom), right: scale(self.right))
        }
    }

    private enum Palette {
        static let panel = rgb(19, 27, 45)
        static let wellBlack = rgb(3, 5, 7)
    }

    private func bandUnit(for rect: CGRect) -> CGFloat {
        min(0.5, min(rect.width, rect.height) / 12)
    }

    /// Draws edge bands from the outside inward; each band is `unit` points wide.
    private func drawBands(in rect: CGRect, unit: CGFloat, context: CGContext, edges: Edges) {
        for (index, color) in edges.left.enumerated() {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: rect.minX + CGFloat(index) * unit, y: rect.minY, width: unit, height: rect.height))
        }
        for (index, color) in edges.right.enumerated() {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: rect.maxX - CGFloat(index + 1) * unit, y: rect.minY, width: unit, height: rect.height))
        }
        for (index, color) in edges.top.enumerated() {
            let inset = CGFloat(index) * unit
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: rect.minX + inset, y: rect.minY + inset, width: rect.width - inset * 2, height: unit))
        }
        for (index, color) in edges.bottom.enumerated() {
            let inset = CGFloat(index) * unit
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: rect.minX + inset, y: rect.maxY - inset - unit, width: rect.width - inset * 2, height: unit))
        }
    }

    private func fillRows(in rect: CGRect, colors: [NSColor], context: CGContext) {
        guard !colors.isEmpty else { return }
        let rowHeight = rect.height / CGFloat(colors.count)
        for (index, color) in colors.enumerated() {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: rect.minX, y: rect.minY + CGFloat(index) * rowHeight, width: rect.width, height: rowHeight))
        }
    }

    private func drawVerticalGradient(in rect: CGRect, stops: [(CGFloat, NSColor)], context: CGContext) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops.map(\.1.cgColor) as CFArray,
            locations: stops.map(\.0)
        ) else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
        context.restoreGState()
    }

    private func snapped(_ rect: CGRect, backingScale: CGFloat) -> CGRect {
        let minX = AmpXPixelGrid.align(rect.minX, backingScale: backingScale)
        let minY = AmpXPixelGrid.align(rect.minY, backingScale: backingScale)
        return CGRect(
            x: minX,
            y: minY,
            width: AmpXPixelGrid.align(rect.maxX, backingScale: backingScale) - minX,
            height: AmpXPixelGrid.align(rect.maxY, backingScale: backingScale) - minY
        )
    }
}

// MARK: - Equalizer level sliders

extension ClassicModernSkin {
    private struct LevelRGB {
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat

        func mixed(with other: LevelRGB, _ t: CGFloat) -> LevelRGB {
            LevelRGB(r: self.r + (other.r - self.r) * t, g: self.g + (other.g - self.g) * t, b: self.b + (other.b - self.b) * t)
        }

        var color: NSColor {
            rgb(self.r, self.g, self.b)
        }
    }

    func levelTrack(_ slot: CGRect, decibels: Double, in context: CGContext, backingScale: CGFloat) {
        let color = self.levelColor(decibels: decibels)
        let bottom = LevelRGB(r: color.r, g: color.g * 0.96, b: color.b * 0.5)
        self.drawTrackShell(self.snapped(slot, backingScale: backingScale), context: context) { bar in
            self.drawVerticalGradient(in: bar, stops: [
                (0, rgb(color.r, color.g, min(255, color.b + 40))),
                (0.05, color.color),
                (1, bottom.color),
            ], context: context)
        }
    }

    /// Bar hue by gain: shared slider green at −12 dB, yellow near 0, and shared red at +12 dB.
    private func levelColor(decibels: Double) -> LevelRGB {
        let minimum = AmpXSliderColorRamp.green
        let maximum = AmpXSliderColorRamp.red
        let stops: [(decibels: Double, color: LevelRGB)] = [
            (-12, LevelRGB(r: minimum.r, g: minimum.g, b: minimum.b)), (-6, LevelRGB(r: 200, g: 236, b: 50)),
            (-3.2, LevelRGB(r: 204, g: 230, b: 42)), (-2.3, LevelRGB(r: 250, g: 222, b: 46)),
            (-1, LevelRGB(r: 234, g: 220, b: 40)), (0, LevelRGB(r: 238, g: 218, b: 36)),
            (0.4, LevelRGB(r: 241, g: 214, b: 33)), (0.8, LevelRGB(r: 253, g: 192, b: 70)),
            (1.7, LevelRGB(r: 250, g: 206, b: 50)), (3, LevelRGB(r: 251, g: 168, b: 30)),
            (12, LevelRGB(r: maximum.r, g: maximum.g, b: maximum.b)),
        ]
        let value = min(max(decibels, -12), 12)
        for (lower, upper) in zip(stops, stops.dropFirst()) where value <= upper.decibels {
            let t = CGFloat((value - lower.decibels) / (upper.decibels - lower.decibels))
            return lower.color.mixed(with: upper.color, t)
        }
        return stops[stops.count - 1].color
    }
}

private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

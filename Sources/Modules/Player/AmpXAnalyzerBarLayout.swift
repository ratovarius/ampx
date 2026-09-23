import CoreGraphics

/// Geometry for the analyzer mode: one thin continuous bar per analysis band with a floating peak
/// cap, twice the resolution of the segmented bars mode. Pure, so the mapping is testable without
/// drawing.
enum AmpXAnalyzerBarLayout {
    /// Gap between neighbouring bars, in points.
    static let barGap: CGFloat = 1

    /// Height of the floating peak cap, in points.
    static let capHeight: CGFloat = 1

    private static var barCount: Int {
        AudioFeatures.spectrumBandCount
    }

    /// Bars in flipped AppKit coordinates, growing upward from the bottom of `rect`. A silent band
    /// still draws a hairline, so the analyzer shows a floor rather than an empty well.
    static func bars(levels: [Float], in rect: CGRect) -> [CGRect] {
        self.rects(values: levels, in: rect) { height in
            CGRect(x: 0, y: rect.maxY - height, width: 0, height: height)
        }
    }

    /// Caps in flipped AppKit coordinates, floating at each band's peak-hold level.
    static func caps(peaks: [Float], in rect: CGRect) -> [CGRect] {
        self.rects(values: peaks, in: rect) { height in
            let top = min(max(rect.maxY - height, rect.minY), rect.maxY - self.capHeight)
            return CGRect(x: 0, y: top, width: 0, height: self.capHeight)
        }
    }

    /// Index into the shared segment palette for a bar of this height.
    static func paletteIndex(forLevel level: Float, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let clamped = CGFloat(min(max(level, 0), 1))
        return min(count - 1, Int(clamped * CGFloat(count)))
    }

    private static func rects(
        values: [Float],
        in rect: CGRect,
        vertical: (CGFloat) -> CGRect
    ) -> [CGRect] {
        let count = min(self.barCount, values.count)
        guard count > 0, rect.width > 0 else { return [] }
        let pitch = rect.width / CGFloat(count)
        let width = max(1, pitch - self.barGap)

        return (0 ..< count).map { index in
            let level = CGFloat(min(max(values[index], 0), 1))
            let slot = vertical(max(1, level * rect.height))
            return CGRect(
                x: rect.minX + CGFloat(index) * pitch,
                y: slot.minY,
                width: width,
                height: slot.height
            )
        }
    }
}

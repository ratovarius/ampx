import CoreGraphics

enum AmpXPixelGrid {
    static func align(_ value: CGFloat, backingScale: CGFloat) -> CGFloat {
        guard backingScale > 0 else { return value }
        return (value * backingScale).rounded() / backingScale
    }

    /// `lineWidth` is in device pixels (callers stroke with `lineWidth / backingScale` points).
    static func strokeRect(_ rect: CGRect, lineWidth: CGFloat, backingScale: CGFloat) -> CGRect {
        let alignedMinX = self.align(rect.minX, backingScale: backingScale)
        let alignedMinY = self.align(rect.minY, backingScale: backingScale)
        let alignedMaxX = self.align(rect.maxX, backingScale: backingScale)
        let alignedMaxY = self.align(rect.maxY, backingScale: backingScale)
        let pointWidth = backingScale > 0 ? lineWidth / backingScale : lineWidth
        return CGRect(
            x: alignedMinX + pointWidth / 2,
            y: alignedMinY + pointWidth / 2,
            width: alignedMaxX - alignedMinX - pointWidth,
            height: alignedMaxY - alignedMinY - pointWidth
        )
    }
}

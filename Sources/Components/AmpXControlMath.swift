import CoreGraphics
import Foundation

enum AmpXControlMath {
    static let minimumHitSize: CGFloat = 44
    static let buttonPressDuration: TimeInterval = 0.07

    static func value(
        fraction: Double,
        range: ClosedRange<Double>,
        step: Double = 0
    ) -> Double {
        let span = range.upperBound - range.lowerBound
        let raw = range.lowerBound + fraction * span
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        guard step > 0 else { return clamped }
        return self.snap(clamped, step: step, range: range)
    }

    static func fraction(value: Double, range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (value - range.lowerBound) / span
    }

    static func horizontalFraction(point: CGPoint, track: CGRect) -> Double {
        guard track.width > 0 else { return 0 }
        return Double((point.x - track.minX) / track.width)
    }

    static func verticalFraction(point: CGPoint, track: CGRect) -> Double {
        guard track.height > 0 else { return 0 }
        return Double(1 - (point.y - track.minY) / track.height)
    }

    static func clampedScrollOffset(
        _ offset: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat
    ) -> CGFloat {
        let maxOffset = max(0, contentLength - viewportLength)
        return min(max(offset, 0), maxOffset)
    }

    static func expandedHitRect(
        for rect: CGRect,
        minimumSize: CGFloat = minimumHitSize
    ) -> CGRect {
        let width = max(rect.width, minimumSize)
        let height = max(rect.height, minimumSize)
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Distance from `point` to the nearest edge of `rect`; zero inside it.
    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func snap(
        _ value: Double,
        step: Double,
        range: ClosedRange<Double>
    ) -> Double {
        let steps = round((value - range.lowerBound) / step)
        let snapped = range.lowerBound + steps * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}

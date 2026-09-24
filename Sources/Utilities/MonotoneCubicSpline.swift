import CoreGraphics

/// Monotone cubic (Fritsch–Butland) spline for the EQ response curve.
///
/// Unlike Catmull-Rom, the curve never overshoots its knots: between two knots it stays within
/// their heights, so raising one band cannot dip its neighbours. The outer tangents are flat,
/// which joins the curve smoothly to the flat runs out to the view edges.
enum MonotoneCubicSpline {
    struct Segment: Equatable {
        var start: CGPoint
        var control1: CGPoint
        var control2: CGPoint
        var end: CGPoint
    }

    /// Cubic Bézier segments through `points`, which must be sorted by strictly increasing x.
    static func segments(through points: [CGPoint]) -> [Segment] {
        guard points.count >= 2 else { return [] }
        let tangents = self.tangents(for: points)
        return (0 ..< points.count - 1).map { index in
            let start = points[index]
            let end = points[index + 1]
            let third = (end.x - start.x) / 3
            return Segment(
                start: start,
                control1: CGPoint(x: start.x + third, y: start.y + tangents[index] * third),
                control2: CGPoint(x: end.x - third, y: end.y - tangents[index + 1] * third),
                end: end
            )
        }
    }

    /// Appends the spline to `path`, starting with a line to the first knot.
    static func addCurve(through points: [CGPoint], to path: CGMutablePath) {
        guard let first = points.first else { return }
        path.addLine(to: first)
        for segment in self.segments(through: points) {
            path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
        }
    }

    private static func tangents(for points: [CGPoint]) -> [CGFloat] {
        let widths = zip(points, points.dropFirst()).map { $1.x - $0.x }
        let slopes = zip(points, points.dropFirst()).enumerated().map { index, pair in
            (pair.1.y - pair.0.y) / widths[index]
        }
        var tangents = Array(repeating: CGFloat(0), count: points.count)
        for index in 1 ..< points.count - 1 {
            let before = slopes[index - 1]
            let after = slopes[index]
            // A local extremum or flat side keeps the knot flat, so nothing overshoots it.
            guard before * after > 0 else { continue }
            let weightBefore = 2 * widths[index] + widths[index - 1]
            let weightAfter = widths[index] + 2 * widths[index - 1]
            tangents[index] = (weightBefore + weightAfter) / (weightBefore / before + weightAfter / after)
        }
        return tangents
    }
}

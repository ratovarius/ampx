@testable import AmpX
import CoreGraphics
import XCTest

final class MonotoneCubicSplineTests: XCTestCase {
    private func points(_ ys: [CGFloat]) -> [CGPoint] {
        ys.enumerated().map { CGPoint(x: CGFloat($0.offset) * 18, y: $0.element) }
    }

    func testSegmentsPassThroughEveryKnot() {
        let knots = self.points([20, 10, 30, 25, 5])
        let segments = MonotoneCubicSpline.segments(through: knots)
        XCTAssertEqual(segments.count, knots.count - 1)
        for (index, segment) in segments.enumerated() {
            XCTAssertEqual(segment.start, knots[index])
            XCTAssertEqual(segment.end, knots[index + 1])
        }
    }

    func testRaisingOneKnotNeverDipsTheFlatNeighbours() {
        // Catmull-Rom undershot here: the segment before the raised knot's neighbour dipped
        // below the flat line, so the curve moved down before following the slider up.
        let knots = self.points([21, 21, 21, 5, 21, 21, 21])
        for segment in MonotoneCubicSpline.segments(through: knots) {
            let low = min(segment.start.y, segment.end.y)
            let high = max(segment.start.y, segment.end.y)
            for control in [segment.control1, segment.control2] {
                XCTAssertGreaterThanOrEqual(control.y, low - 0.0001, "Curve must not overshoot below its knots")
                XCTAssertLessThanOrEqual(control.y, high + 0.0001, "Curve must not overshoot above its knots")
            }
        }
    }

    func testOuterTangentsAreFlat() {
        let knots = self.points([10, 30, 20])
        let segments = MonotoneCubicSpline.segments(through: knots)
        XCTAssertEqual(segments.first?.control1.y ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(segments.last?.control2.y ?? 0, 20, accuracy: 0.0001)
    }
}

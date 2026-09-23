import CoreGraphics
import Foundation

/// Winamp track-title marquee: a title wider than its well loops right-to-left as
/// `text *** text`, at a constant speed. Titles that fit stay still.
struct AmpXMarqueeLayout: Equatable {
    static let separator = "  ***  "
    /// Points per second.
    static let speed: CGFloat = 30

    var textWidth: CGFloat
    var separatorWidth: CGFloat
    var viewportWidth: CGFloat

    var scrolls: Bool {
        self.textWidth > self.viewportWidth
    }

    /// Distance from one copy of the text to the next.
    var cycleLength: CGFloat {
        self.textWidth + self.separatorWidth
    }

    /// How far the text has moved left after `elapsed` seconds; always in `0 ..< cycleLength`.
    func offset(elapsed: TimeInterval) -> CGFloat {
        guard self.scrolls, self.cycleLength > 0, elapsed > 0 else { return 0 }
        let distance = CGFloat(elapsed) * Self.speed
        return distance.truncatingRemainder(dividingBy: self.cycleLength)
    }

    /// Left edges of the text copies to draw, relative to the unscrolled origin.
    func copyOrigins(elapsed: TimeInterval) -> [CGFloat] {
        guard self.scrolls else { return [0] }
        let first = -self.offset(elapsed: elapsed)
        return [first, first + self.cycleLength]
    }
}

import Foundation

/// Per-column spectrum level, color-band mapping, and peak-hold decay for the Player display.
enum AmpXSpectrumColumnModel {
    static let segmentCount = AmpXMetrics.spectrumSegmentCount
    static let columnCount = AmpXMetrics.spectrumColumnCount

    static func litCount(level: Float, segmentCount: Int) -> Int {
        guard segmentCount > 0 else { return 0 }
        let clamped = min(max(level, 0), 1)
        return Int((clamped * Float(segmentCount)).rounded())
    }

    static func colorBand(segment: Int, count: Int) -> Int {
        let ratio = Float(segment) / Float(max(count - 1, 1))
        if ratio < 0.45 {
            return 0
        }
        if ratio < 0.75 {
            return 1
        }
        return 2
    }
}

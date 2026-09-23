import AppKit

enum AmpXCompactTimeLayout {
    static func text(current: TimeInterval, duration: TimeInterval, remaining: Bool, hasLoadedTrack: Bool) -> String {
        guard hasLoadedTrack, current.isFinite, current < Double(Int.max) else { return "00:00" }
        let elapsed = max(0, current)
        let seconds: Double
        if remaining {
            guard duration.isFinite, duration > 0, duration < Double(Int.max) else { return "00:00" }
            seconds = max(0, duration - elapsed)
        } else {
            seconds = elapsed
        }
        let total = Int(seconds)
        // Interpolation preserves 64-bit hour counts; C's %d would truncate large durations.
        let hours = total / 3600
        let minutes = total / 60 % 60
        let tail = String(format: "%02d:%02d", minutes, total % 60)
        let body = hours > 0 ? "\(hours):\(tail)" : tail
        return remaining ? "-" + body : body
    }

    static let digitStyles: [AmpXSegmentDigits.Metrics] = [
        .init(
            digitSize: CGSize(width: 7.5, height: 13),
            gap: 2.8,
            colonWidth: 4,
            minusWidth: 4,
            stroke: 1.2,
            joint: 0.3,
            colonDot: CGSize(width: 1.5, height: 1.5)
        ),
        .init(
            digitSize: CGSize(width: 6, height: 10.4),
            gap: 0.6,
            colonWidth: 2.3,
            minusWidth: 3.1,
            stroke: 0.92,
            joint: 0.23,
            colonDot: CGSize(width: 1.15, height: 1.15)
        ),
        .init(
            digitSize: CGSize(width: 4.3, height: 7.45),
            gap: 0.45,
            colonWidth: 1.65,
            minusWidth: 2.2,
            stroke: 0.66,
            joint: 0.165,
            colonDot: CGSize(width: 0.83, height: 0.83)
        ),
    ]

    static func metrics(for text: String, in rect: CGRect) -> AmpXSegmentDigits.Metrics {
        self.digitStyles.first { metrics in
            AmpXSegmentDigits.cells(for: text, in: rect, metrics: metrics).allSatisfy { rect.contains($0.rect) }
        } ?? self.digitStyles[self.digitStyles.count - 1]
    }
}

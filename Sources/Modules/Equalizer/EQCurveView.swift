import AppKit
import CoreGraphics
import QuartzCore

/// EQ response curve: one knot per band slider on a monotone spline, plus a preamp line.
final class EQCurveView: AmpXDrawingView {
    static let animationDuration: TimeInterval = 0.075

    struct Reference: Equatable {
        /// Normalized −1…1 band gains.
        var bandValues: [Float]
        /// Normalized −1…1 preamp gain.
        var preampValue: Float
    }

    /// Display-only curve for deterministic reference presentation; `nil` draws the animated live curve.
    var reference: Reference? {
        didSet { needsDisplay = true }
    }

    /// Sampled from the reference curve stroke.
    private static let curveColor = NSColor(srgbRed: 246 / 255, green: 182 / 255, blue: 6 / 255, alpha: 1)
    private static let knotColor = NSColor(srgbRed: 1, green: 206 / 255, blue: 20 / 255, alpha: 1)
    private static let preampColor = NSColor(srgbRed: 246 / 255, green: 182 / 255, blue: 6 / 255, alpha: 0.35)

    /// Values currently drawn; lag `target*` while an animation is in flight. Internal for tests.
    private(set) var displayedBandValues = Array(repeating: Float(0), count: AmpXEQBands.bandCount)
    private(set) var displayedPreampValue: Float = 0
    private var targetBandValues = Array(repeating: Float(0), count: AmpXEQBands.bandCount)
    private var targetPreampValue: Float = 0

    private var animationStartTime: TimeInterval?
    private var animationFromBands = Array(repeating: Float(0), count: AmpXEQBands.bandCount)
    private var animationFromPreamp: Float = 0
    private var animationLink: CADisplayLink?
    private var animationForwarder: EQCurveAnimationForwarder?

    override init(skin: any AmpXSkin) {
        super.init(skin: skin)
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// One knot per band at the measured pitch, with heights from `AmpXEQBands.responseCurvePoints`.
    static func knotPoints(bandValues: [Float], size: CGSize) -> [CGPoint] {
        let span = AmpXMetrics.eqCurveBandPitch * CGFloat(AmpXEQBands.bandCount)
        let origin = AmpXMetrics.eqCurveFirstBandOffset - AmpXMetrics.eqCurveBandPitch / 2
        return AmpXEQBands.responseCurvePoints(bandValues: bandValues, width: span, height: size.height)
            .map { CGPoint(x: $0.x + origin, y: $0.y) }
    }

    /// `animated` only takes effect for jumps that move more than one band (presets, reset).
    /// A single slider drag or a preamp change redraws at once: the slider is already moving
    /// under the pointer, and easing toward each drag event made the curve trail behind it.
    func setCurve(bandValues: [Float], preampValue: Float, animated: Bool) {
        let bands = self.normalizedBands(from: bandValues)
        let changedBands = zip(bands, self.targetBandValues).count(where: { $0 != $1 })
        if animated, changedBands == 0, self.animationStartTime != nil {
            // Preamp-only update (e.g. AUTO after a preset) while the bands are still easing:
            // move the preamp line now and let the band animation finish.
            self.animationFromPreamp = preampValue
            self.targetPreampValue = preampValue
            self.displayedPreampValue = preampValue
            needsDisplay = true
            return
        }
        if !animated || changedBands <= 1 {
            self.stopAnimation()
            self.displayedBandValues = bands
            self.displayedPreampValue = preampValue
            self.targetBandValues = bands
            self.targetPreampValue = preampValue
            needsDisplay = true
            return
        }

        self.animationFromBands = self.displayedBandValues
        self.animationFromPreamp = self.displayedPreampValue
        self.targetBandValues = bands
        self.targetPreampValue = preampValue
        self.animationStartTime = CACurrentMediaTime()
        self.startAnimation()
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let points = Self.knotPoints(
            bandValues: self.reference.map { self.normalizedBands(from: $0.bandValues) } ?? self.displayedBandValues,
            size: bounds.size
        )
        guard let first = points.first, let last = points.last else { return }
        let preampValue = self.reference?.preampValue ?? self.displayedPreampValue

        context.saveGState()
        // Preamp as its own line (as in Winamp), so each curve knot mirrors one band slider.
        let preampY = AmpXEQBands.curveY(forNormalizedGain: preampValue, height: bounds.height)
        context.setStrokeColor(Self.preampColor.cgColor)
        context.setLineWidth(1)
        context.strokeLineSegments(between: [CGPoint(x: 0, y: preampY), CGPoint(x: bounds.width, y: preampY)])

        // The curve runs flat from the view edges to the outer knots.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: first.y))
        MonotoneCubicSpline.addCurve(through: points, to: path)
        path.addLine(to: CGPoint(x: bounds.width, y: last.y))
        context.addPath(path)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(Self.curveColor.cgColor)
        context.strokePath()
        context.setFillColor(Self.knotColor.cgColor)
        for point in points {
            context.fillEllipse(in: CGRect(x: point.x - 1.6, y: point.y - 1.6, width: 3.2, height: 3.2))
        }
        context.restoreGState()
    }

    nonisolated deinit {
        MainActor.assumeIsolated {
            stopAnimation()
        }
    }

    private func normalizedBands(from values: [Float]) -> [Float] {
        var bands = Array(repeating: Float(0), count: AmpXEQBands.bandCount)
        for index in 0 ..< AmpXEQBands.bandCount where index < values.count {
            bands[index] = values[index]
        }
        return bands
    }

    private func startAnimation() {
        // Only replace the display link here. `stopAnimation()` would also clear
        // `animationStartTime`, which `setCurve` has just set; with it nil every tick
        // returned early, so the curve never left its launch values and the link ran forever.
        self.stopDisplayLink()

        let forwarder = EQCurveAnimationForwarder()
        forwarder.view = self
        self.animationForwarder = forwarder

        let link = displayLink(
            target: forwarder,
            selector: #selector(EQCurveAnimationForwarder.displayLinkFired(_:))
        )
        self.animationLink = link
        link.add(to: .main, forMode: .common)
        self.animationTick(at: CACurrentMediaTime())
    }

    func animationTick(at time: TimeInterval) {
        guard let start = animationStartTime else { return }
        // `CADisplayLink.timestamp` is the previous frame's time and can predate `start`; a
        // negative progress would extrapolate away from the target (a raised band dipped first).
        let progress = max(0, min(1, (time - start) / Self.animationDuration))
        self.displayedBandValues = zip(self.animationFromBands, self.targetBandValues).map { from, to in
            from + (to - from) * Float(progress)
        }
        self.displayedPreampValue = self.animationFromPreamp + (self.targetPreampValue - self.animationFromPreamp) * Float(progress)
        setNeedsDisplay(bounds)

        if progress >= 1 {
            self.finishAnimation()
        }
    }

    private func finishAnimation() {
        self.displayedBandValues = self.targetBandValues
        self.displayedPreampValue = self.targetPreampValue
        self.stopAnimation()
        needsDisplay = true
    }

    private func stopAnimation() {
        self.stopDisplayLink()
        self.animationStartTime = nil
    }

    private func stopDisplayLink() {
        self.animationLink?.invalidate()
        self.animationLink = nil
        self.animationForwarder = nil
    }
}

/// Deliberately not `@MainActor`: AppKit calls this `@objc` selector from its display-link callback
/// without a Swift task, and on macOS 26 an isolated entry point traps in
/// `swift_task_isCurrentExecutor`. The link runs on the main run loop, so hopping is safe.
/// Deliberately not `@MainActor`, and the work hops through a real `Task`: AppKit calls this `@objc`
/// selector from its display-link callback with no Swift task, and on macOS 26 the executor check
/// then crashes in `swift_task_isCurrentExecutor` — both at an isolated entry point and inside
/// `MainActor.assumeIsolated`. Entering a task gives the check a valid context (see commit 5562af8).
private final class EQCurveAnimationForwarder: NSObject {
    nonisolated(unsafe) weak var view: EQCurveView?

    @objc func displayLinkFired(_ link: CADisplayLink) {
        // Only the timestamp crosses the boundary; `CADisplayLink` is not Sendable.
        let timestamp = link.timestamp
        let view = self.view
        Task { @MainActor in
            view?.animationTick(at: timestamp)
        }
    }
}

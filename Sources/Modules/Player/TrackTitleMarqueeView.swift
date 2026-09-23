import AppKit
import CoreGraphics

/// Player track title. Long titles scroll (see `AmpXMarqueeLayout`); the display link runs only then.
final class TrackTitleMarqueeView: AmpXContinuousView {
    static let fontSize: CGFloat = 13.75

    var title = "" {
        didSet {
            guard self.title != oldValue else { return }
            self.restartScrolling()
        }
    }

    /// Left edge and baseline of the unscrolled text, in this view's coordinates.
    var textOrigin: CGPoint = .zero {
        didSet { self.restartScrolling() }
    }

    /// Visible text area in this view's coordinates; `nil` uses the bounds.
    var textClip: CGRect? {
        didSet { self.restartScrolling() }
    }

    /// Holds the text still, for deterministic reference captures.
    var isScrollingSuppressed = false {
        didSet { self.restartScrolling() }
    }

    private(set) var layout = AmpXMarqueeLayout(textWidth: 0, separatorWidth: 0, viewportWidth: 0)
    private var scrollStart: TimeInterval?
    private(set) var elapsed: TimeInterval = 0

    override init(skin: any AmpXSkin) {
        super.init(skin: skin)
        // Scrolling copies must not paint over the well's bevel.
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        self.restartScrolling()
    }

    /// Clicks and drags reach the Player behind the title, as before the marquee existed.
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func tick(at time: TimeInterval) {
        let start = self.scrollStart ?? time
        self.scrollStart = start
        self.elapsed = time - start
        setNeedsDisplay(bounds)
    }

    private func label(_ text: String) -> AmpXLabel {
        AmpXLabel(text: text, color: skin.green, fontSize: Self.fontSize, weight: .regular)
    }

    private func restartScrolling() {
        self.layout = AmpXMarqueeLayout(
            textWidth: self.label(self.title).measuredSize(skin: skin).width,
            separatorWidth: self.label(AmpXMarqueeLayout.separator).measuredSize(skin: skin).width,
            viewportWidth: (self.textClip ?? bounds).maxX - self.textOrigin.x
        )
        self.scrollStart = nil
        self.elapsed = 0
        setContinuousRenderingPaused(self.isScrollingSuppressed || !self.layout.scrolls)
        needsDisplay = true
    }

    override func draw(_: NSRect) {
        guard !self.title.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let elapsed = self.isScrollingSuppressed ? 0 : self.elapsed
        let baseline = self.textOrigin.y
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: self.textClip ?? bounds)
        for origin in self.layout.copyOrigins(elapsed: elapsed) {
            let x = self.textOrigin.x + origin
            self.label(self.title).draw(x: x, baseline: baseline, context: context, skin: skin)
            if self.layout.scrolls {
                self.label(AmpXMarqueeLayout.separator)
                    .draw(x: x + self.layout.textWidth, baseline: baseline, context: context, skin: skin)
            }
        }
    }
}

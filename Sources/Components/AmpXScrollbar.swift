import AppKit
import CoreGraphics

final class AmpXScrollbar: AmpXControlView {
    var offset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var contentLength: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var viewportLength: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    /// Fixed thumb length; `nil` sizes the thumb proportionally to the viewport.
    var fixedThumbLength: CGFloat? {
        didSet { needsDisplay = true }
    }

    var onScroll: ((CGFloat) -> Void)?

    private static let minimumThumbLength: CGFloat = 12

    private var isDraggingThumb = false {
        didSet { needsDisplay = true }
    }

    private enum Part {
        case up, down, thumb
    }

    /// Arrow key held down by the current click.
    private var pressedArrow: Part? {
        didSet { needsDisplay = true }
    }

    private var dragStartOffset: CGFloat = 0
    private var dragStartY: CGFloat = 0

    override init(skin: any AmpXSkin) {
        super.init(skin: skin)
        setAccessibilityRole(.scrollBar)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1

        // Trough, arrows and handle use the shared track and key materials and states.
        skin.neutralTrack(self.trackRect(), in: context, backingScale: backingScale)
        let hovered = self.hoveredPart
        for (part, rect, glyph) in [
            (Part.up, self.upArrowRect(), AmpXMetrics.playlistScrollbarUpGlyph),
            (Part.down, self.downArrowRect(), AmpXMetrics.playlistScrollbarDownGlyph),
        ] {
            let style = AmpXFaceStyle.resolve(pressed: self.pressedArrow == part, hovered: hovered == part)
            skin.raisedFace(rect, style: style, in: context, backingScale: backingScale)
            let sink = style.isPressed ? AmpXButton.pressedInkOffset : 0
            self.drawArrow(up: part == .up, in: self.glyphRect(glyph, in: rect).offsetBy(dx: 0, dy: sink), context: context)
        }
        let thumbStyle = AmpXFaceStyle.resolve(pressed: self.isDraggingThumb, hovered: hovered == .thumb)
        skin.metallicThumb(self.thumbRect(), material: .goldTab, style: thumbStyle, in: context, backingScale: backingScale)

        if !isEnabled {
            context.setFillColor(skin.background.withAlphaComponent(0.35).cgColor)
            context.fill(bounds)
        }

        drawFocusRing(in: context, backingScale: backingScale)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        let thumb = self.thumbRect()

        if thumb.contains(point) {
            self.isDraggingThumb = true
            self.dragStartOffset = self.offset
            self.dragStartY = point.y
            return
        }

        if self.upArrowRect().contains(point) {
            self.pressedArrow = .up
            self.scrollBy(-self.viewportLength / 3)
            return
        }

        if self.downArrowRect().contains(point) {
            self.pressedArrow = .down
            self.scrollBy(self.viewportLength / 3)
            return
        }

        let track = self.trackRect()
        guard track.contains(point) else { return }
        if point.y < thumb.midY {
            self.scrollBy(-self.viewportLength)
        } else {
            self.scrollBy(self.viewportLength)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, self.isDraggingThumb else { return }
        let point = convert(event.locationInWindow, from: nil)
        let track = self.trackRect()
        guard track.height > 0 else { return }

        let thumbHeight = self.thumbRect().height
        let travel = max(track.height - thumbHeight, 1)
        let maxOffset = max(contentLength - self.viewportLength, 0)
        let deltaY = point.y - self.dragStartY
        let offsetDelta = deltaY / travel * maxOffset
        self.setOffset(self.dragStartOffset + offsetDelta)
    }

    override func mouseUp(with _: NSEvent) {
        self.isDraggingThumb = false
        self.pressedArrow = nil
    }

    override func cancelInteraction() {
        self.isDraggingThumb = false
        self.pressedArrow = nil
    }

    private var hoveredPart: Part? {
        guard isHovered, isEnabled, self.pressedArrow == nil, !self.isDraggingThumb, let window else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if self.thumbRect().contains(point) {
            return .thumb
        }
        if self.upArrowRect().contains(point) {
            return .up
        }
        if self.downArrowRect().contains(point) {
            return .down
        }
        return nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { return }
        self.scrollBy(-event.deltaY * 8)
    }

    override func accessibilityValue() -> Any? {
        self.offset
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled else { return false }
        self.scrollBy(self.viewportLength / 5)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled else { return false }
        self.scrollBy(-self.viewportLength / 5)
        return true
    }

    private func setOffset(_ newOffset: CGFloat) {
        let clamped = AmpXControlMath.clampedScrollOffset(newOffset, contentLength: self.contentLength, viewportLength: self.viewportLength)
        guard clamped != self.offset else { return }
        self.offset = clamped
        self.onScroll?(clamped)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    private func scrollBy(_ delta: CGFloat) {
        self.setOffset(self.offset + delta)
    }

    // MARK: - Geometry

    private var upButtonHeight: CGFloat {
        min(AmpXMetrics.playlistScrollbarUpButtonHeight, bounds.height / 3)
    }

    private var downButtonHeight: CGFloat {
        min(AmpXMetrics.playlistScrollbarDownButtonHeight, bounds.height / 3)
    }

    func trackRect() -> CGRect {
        CGRect(
            x: bounds.minX,
            y: bounds.minY + self.upButtonHeight,
            width: bounds.width,
            height: max(0, bounds.height - self.upButtonHeight - self.downButtonHeight)
        )
    }

    func upArrowRect() -> CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: self.upButtonHeight)
    }

    func downArrowRect() -> CGRect {
        CGRect(x: bounds.minX, y: bounds.maxY - self.downButtonHeight, width: bounds.width, height: self.downButtonHeight)
    }

    func thumbRect() -> CGRect {
        let track = self.trackRect()
        let maxOffset = max(contentLength - self.viewportLength, 0)
        let proportional = track.height * self.viewportLength / max(self.contentLength, 1)
        let length = min(track.height, max(self.fixedThumbLength ?? proportional, Self.minimumThumbLength))
        let travel = max(track.height - length, 0)
        let progress = maxOffset > 0 ? self.offset / maxOffset : 0
        let inset = AmpXMetrics.playlistScrollbarThumbInset
        return CGRect(
            x: bounds.minX + inset,
            y: track.minY + progress * travel,
            width: bounds.width - inset * 2,
            height: length
        )
    }

    private func glyphRect(_ glyph: CGRect, in button: CGRect) -> CGRect {
        glyph.offsetBy(dx: button.minX, dy: button.minY)
    }

    private func drawArrow(up: Bool, in rect: CGRect, context: CGContext) {
        let path = CGMutablePath()
        if up {
            path.addLines(between: [
                CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
            ])
        } else {
            path.addLines(between: [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.midX, y: rect.maxY),
            ])
        }
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(skin.faceInk.cgColor)
        context.fillPath()
    }
}

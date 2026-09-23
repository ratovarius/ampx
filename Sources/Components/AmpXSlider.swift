import AppKit
import CoreGraphics

final class AmpXSlider: AmpXControlView {
    enum Artwork {
        /// Full-bounds well with a small bevelled thumb (Equalizer, pending its reconstruction).
        case legacy
        /// Colored track with the shared key handle.
        case pill(AmpXTrackFill)
        /// Neutral seek channel with the shared key handle.
        case seek
        /// Vertical EQ slot tinted by the displayed value, with the shared key handle.
        case level
        case compact(AmpXTrackFill)
    }

    /// Thumb-center travel length centered on the track; `nil` keeps the thumb inside the track.
    var travelLength: CGFloat? {
        didSet { needsDisplay = true }
    }

    var value: Double = 0 {
        didSet { needsDisplay = true }
    }

    var range: ClosedRange<Double> = 0 ... 1 {
        didSet { needsDisplay = true }
    }

    var step: Double = 0 {
        didSet { needsDisplay = true }
    }

    var onChange: ((Double) -> Void)?
    var isVertical = false {
        didSet { needsDisplay = true }
    }

    var showsGradient = false {
        didSet { needsDisplay = true }
    }

    var showsThumbGrip = false {
        didSet { needsDisplay = true }
    }

    var artwork: Artwork = .legacy {
        didSet { needsDisplay = true }
    }

    /// Visible track size, centered in bounds. `nil` uses the full bounds.
    var trackSize: CGSize? {
        didSet { needsDisplay = true }
    }

    /// Visible thumb size. `nil` derives the legacy size from the track.
    var thumbSize: CGSize? {
        didSet { needsDisplay = true }
    }

    /// Display-only value for deterministic reference presentation; `nil` draws `value`.
    var displayValueOverride: Double? {
        didSet { needsDisplay = true }
    }

    var accessibilityTitle: String?
    var accessibilityStep: Double?
    var accessibilityRangeOverride: ClosedRange<Double>?
    var accessibilityValueFormatter: ((Double) -> Any)?

    private var isDragging = false {
        didSet { needsDisplay = true }
    }

    override func cancelInteraction() {
        self.isDragging = false
    }

    override init(skin: any AmpXSkin) {
        super.init(skin: skin)
        setAccessibilityRole(.slider)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setValue(_ newValue: Double, sendChange: Bool) {
        let clamped = AmpXControlMath.value(
            fraction: AmpXControlMath.fraction(value: newValue, range: self.range),
            range: self.range,
            step: self.step
        )
        self.value = clamped
        if sendChange {
            self.onChange?(clamped)
        }
    }

    // MARK: - Geometry shared by drawing and pointer mapping

    var trackRect: CGRect {
        guard let trackSize else { return bounds }
        return CGRect(
            x: bounds.midX - trackSize.width / 2,
            y: bounds.midY - trackSize.height / 2,
            width: trackSize.width,
            height: trackSize.height
        )
    }

    var resolvedThumbSize: CGSize {
        if let thumbSize {
            return thumbSize
        }
        let track = self.trackRect
        return self.isVertical ? CGSize(width: 10, height: 8) : CGSize(width: 8, height: max(0, track.height - 2))
    }

    /// Thumb-center displacement perpendicular to the travel axis.
    var thumbCrossOffset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    /// Thumb-center travel endpoints: minimum value first.
    var travel: (start: CGPoint, end: CGPoint) {
        let track = self.trackRect
        let size = self.resolvedThumbSize
        if self.isVertical {
            let x = track.midX + self.thumbCrossOffset
            let half = (travelLength ?? (track.height - size.height)) / 2
            return (CGPoint(x: x, y: track.midY + half), CGPoint(x: x, y: track.midY - half))
        }
        let y = track.midY + self.thumbCrossOffset
        let half = (travelLength ?? (track.width - size.width)) / 2
        return (CGPoint(x: track.midX - half, y: y), CGPoint(x: track.midX + half, y: y))
    }

    var thumbRect: CGRect {
        thumbRect(forValue: self.displayValueOverride ?? self.value)
    }

    func thumbRect(forValue value: Double) -> CGRect {
        let fraction = CGFloat(min(max(AmpXControlMath.fraction(value: value, range: self.range), 0), 1))
        let (start, end) = self.travel
        let size = self.resolvedThumbSize
        let center = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    func value(at point: CGPoint) -> Double {
        let (start, end) = self.travel
        let fraction: Double
        if self.isVertical {
            let span = start.y - end.y
            fraction = span > 0 ? Double((start.y - point.y) / span) : 0
        } else {
            let span = end.x - start.x
            fraction = span > 0 ? Double((point.x - start.x) / span) : 0
        }
        return AmpXControlMath.value(fraction: fraction, range: self.range, step: self.step)
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1
        let track = self.trackRect
        let thumb = self.thumbRect
        let thumbStyle = self.thumbStyle(thumb)

        switch self.artwork {
        case .legacy:
            skin.displayWell(track, in: context, backingScale: backingScale)
            if self.showsGradient {
                self.drawGradient(in: context, track: track)
            }
            skin.bevel(thumb, in: context, backingScale: backingScale)
            context.setFillColor(skin.panelLight.cgColor)
            context.fill(thumb.insetBy(dx: 1, dy: 1))
            if self.showsThumbGrip {
                context.setFillColor(skin.borderDark.cgColor)
                context.fill(CGRect(x: thumb.minX + 2, y: thumb.midY - 1, width: thumb.width - 4, height: 1))
                context.fill(CGRect(x: thumb.minX + 2, y: thumb.midY + 1, width: thumb.width - 4, height: 1))
            }
        case let .pill(fill):
            let fraction = AmpXControlMath.fraction(value: self.displayValueOverride ?? self.value, range: self.range)
            skin.sliderTrack(
                track,
                fill: fill,
                fraction: fraction,
                in: context,
                backingScale: backingScale
            )
            skin.metallicThumb(thumb, material: .steel, style: thumbStyle, in: context, backingScale: backingScale)
        case .seek:
            skin.seekWell(bounds, track: track, in: context, backingScale: backingScale)
            skin.metallicThumb(thumb, material: .gold, style: thumbStyle, in: context, backingScale: backingScale)
        case .level:
            skin.levelTrack(track, decibels: self.displayValueOverride ?? self.value, in: context, backingScale: backingScale)
            skin.metallicThumb(thumb, material: .steelLevel, style: thumbStyle, in: context, backingScale: backingScale)
        case let .compact(fill):
            AmpXCompactSliderDrawing.draw(
                track: track, thumb: thumb, fill: fill,
                value: AmpXControlMath.fraction(value: self.displayValueOverride ?? self.value, range: self.range),
                thumbStyle: thumbStyle,
                skin: self.skin, context: context, backingScale: backingScale
            )
        }

        if !isEnabled {
            context.setFillColor(skin.background.withAlphaComponent(0.35).cgColor)
            context.fill(track.union(thumb))
        }

        drawFocusRing(in: context, backingScale: backingScale)
    }

    /// Handles share the key states: dragging reads as pressed, pointing at the handle as hovered.
    private func thumbStyle(_ thumb: CGRect) -> AmpXFaceStyle {
        var hovered = false
        if isHovered, isEnabled, let window {
            hovered = thumb.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        return AmpXFaceStyle.resolve(pressed: self.isDragging, hovered: hovered)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        self.isDragging = true
        self.updateValue(for: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, self.isDragging else { return }
        self.updateValue(for: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with _: NSEvent) {
        self.isDragging = false
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { return }
        let delta = event.deltaY != 0 ? event.deltaY : event.deltaX
        guard delta != 0 else { return }
        let increment = self.step > 0 ? self.step : (self.range.upperBound - self.range.lowerBound) / 100
        let direction = self.isVertical ? -delta : delta
        self.setValue(self.value + Double(direction) * increment, sendChange: true)
    }

    override func accessibilityLabel() -> String? {
        self.accessibilityTitle ?? super.accessibilityLabel()
    }

    override func accessibilityValue() -> Any? {
        self.accessibilityValueFormatter?(self.value) ?? self.value
    }

    override func accessibilityMinValue() -> Any? {
        (self.accessibilityRangeOverride ?? self.range).lowerBound
    }

    override func accessibilityMaxValue() -> Any? {
        (self.accessibilityRangeOverride ?? self.range).upperBound
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled else { return false }
        let increment = self.accessibilityStep ?? (self.step > 0 ? self.step : 1)
        self.setValue(self.value + increment, sendChange: true)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled else { return false }
        let increment = self.accessibilityStep ?? (self.step > 0 ? self.step : 1)
        self.setValue(self.value - increment, sendChange: true)
        return true
    }

    @discardableResult
    func handleArrowKey(_ event: NSEvent) -> Bool {
        guard isEnabled else { return false }
        let increment = self.step > 0 ? self.step : (self.range.upperBound - self.range.lowerBound) / 20
        switch event.keyCode {
        case 123, 125:
            self.setValue(self.value - increment, sendChange: true)
            return true
        case 124, 126:
            self.setValue(self.value + increment, sendChange: true)
            return true
        default:
            return false
        }
    }

    private func updateValue(for point: CGPoint) {
        let next = self.value(at: point)
        self.value = next
        self.onChange?(next)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    private func drawGradient(in context: CGContext, track: CGRect) {
        let colors: CFArray
        let start: CGPoint
        let end: CGPoint
        if self.isVertical {
            colors = [skin.orange.cgColor, skin.yellow.cgColor, skin.green.cgColor] as CFArray
            start = CGPoint(x: track.midX, y: track.minY)
            end = CGPoint(x: track.midX, y: track.maxY)
        } else {
            colors = [skin.green.cgColor, skin.yellow.cgColor, skin.orange.cgColor] as CFArray
            start = CGPoint(x: track.minX, y: track.midY)
            end = CGPoint(x: track.maxX, y: track.midY)
        }

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.5, 1]
        ) else { return }

        context.saveGState()
        context.clip(to: track.insetBy(dx: 1, dy: 1))
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }
}

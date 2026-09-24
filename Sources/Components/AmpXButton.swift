import AppKit
import CoreGraphics

final class AmpXButton: AmpXControlView {
    enum Style {
        case bevel
        case menu
    }

    var action: (() -> Void)?
    var isActive = false {
        didSet { needsDisplay = true }
    }

    var label: String? {
        didSet { needsDisplay = true }
    }

    var icon: AmpXIcon? {
        didSet { needsDisplay = true }
    }

    var iconColor: NSColor? {
        didSet { needsDisplay = true }
    }

    var showsActiveIndicator = false {
        didSet { needsDisplay = true }
    }

    /// Active state is shown as a depressed face. Unused by the Midnight Hardware keys, which keep
    /// transient presses and persistent state (green glyph or lamp) separate.
    var showsActiveFace = false {
        didSet { needsDisplay = true }
    }

    var style: Style = .bevel {
        didSet { needsDisplay = true }
    }

    /// Measured content layout in bounds coordinates; `nil` values center the content.
    var labelBaselineOrigin: CGPoint? {
        didSet { needsDisplay = true }
    }

    var labelFontSize: CGFloat? {
        didSet { needsDisplay = true }
    }

    var labelWeight: NSFont.Weight = .semibold {
        didSet { needsDisplay = true }
    }

    var iconRect: CGRect? {
        didSet { needsDisplay = true }
    }

    var indicatorRect: CGRect? {
        didSet { needsDisplay = true }
    }

    /// Display-only active state for deterministic reference presentation.
    var displayActiveOverride: Bool? {
        didSet { needsDisplay = true }
    }

    var accessibilityTitle: String?

    /// Shared key label weight; size is `AmpXMetrics.keyLabelFontSize`.
    static let keyLabelWeight: NSFont.Weight = .medium

    /// Pressed ink sinks this far, so the key reads as travelling without inverting its bevel.
    static let pressedInkOffset: CGFloat = 0.5

    func applyKeyLabelStyle() {
        self.labelFontSize = AmpXMetrics.keyLabelFontSize
        self.labelWeight = Self.keyLabelWeight
    }

    private(set) var isPressed = false {
        didSet { needsDisplay = true }
    }

    private var pressResetWorkItem: DispatchWorkItem?

    override init(skin: any AmpXSkin) {
        super.init(skin: skin)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var displaysActive: Bool {
        self.displayActiveOverride ?? self.isActive
    }

    /// Glyph and label ink: light on both the navy key face and the orange menu face.
    private var inkColor: NSColor {
        self.style == .menu ? skin.text : skin.faceInk
    }

    private var dimInkColor: NSColor {
        self.style == .menu ? skin.textDim : skin.faceInkDim
    }

    private var labelLines: [String] {
        self.label?.components(separatedBy: "\n") ?? []
    }

    var labelFont: NSFont {
        skin.font(size: self.labelFontSize ?? (self.labelLines.count > 1 ? 7 : 8), weight: self.labelWeight)
    }

    /// Typographic box of the label lines; never narrower than one line height.
    var labelRect: CGRect {
        let font = self.labelFont
        let lineHeight = font.ascender - font.descender
        let blockHeight = lineHeight * CGFloat(max(self.labelLines.count, 1))
        let width = self.labelLines.map { self.measuredWidth(of: $0) }.max() ?? 0
        if let origin = labelBaselineOrigin {
            return CGRect(x: origin.x, y: origin.y - font.ascender, width: width, height: blockHeight)
        }
        let height = min(blockHeight, bounds.height)
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    var resolvedIconRect: CGRect {
        if let iconRect {
            return iconRect
        }
        let area = bounds.insetBy(dx: 8, dy: 8)
        return area.insetBy(dx: area.width * 0.28, dy: area.height * 0.28)
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1

        let faceStyle = AmpXFaceStyle.resolve(
            pressed: self.isPressed || (self.showsActiveFace && self.displaysActive),
            hovered: isHovered && isEnabled,
            menu: self.style == .menu
        )
        skin.raisedFace(bounds, style: faceStyle, in: context, backingScale: backingScale)

        if !isEnabled {
            context.setFillColor(skin.background.withAlphaComponent(0.35).cgColor)
            context.fill(bounds.insetBy(dx: 1, dy: 1))
        }

        context.saveGState()
        if faceStyle.isPressed {
            context.translateBy(x: 0, y: Self.pressedInkOffset)
        }
        if self.label != nil {
            self.drawLabel(in: context)
        }

        if let icon {
            let tint = self.iconColor ?? (self.displaysActive ? skin.green : self.inkColor)
            icon.draw(in: self.resolvedIconRect, context: context, skin: skin, color: isEnabled ? tint : self.dimInkColor)
        }

        if self.showsActiveIndicator {
            self.drawIndicator(in: context)
        }
        context.restoreGState()

        drawFocusRing(in: context, backingScale: backingScale)
    }

    private func drawLabel(in context: CGContext) {
        let font = self.labelFont
        let color = isEnabled ? self.inkColor : self.dimInkColor
        let rect = self.labelRect
        let lineHeight = font.ascender - font.descender
        for (index, line) in self.labelLines.enumerated() {
            let baseline = rect.minY + font.ascender + CGFloat(index) * lineHeight
            if self.labelBaselineOrigin != nil {
                AmpXLabel(text: line, color: color, fontSize: font.pointSize, weight: self.labelWeight)
                    .draw(x: rect.minX, baseline: baseline, context: context, skin: skin)
            } else {
                AmpXLabel(text: line, color: color, fontSize: font.pointSize, weight: self.labelWeight, alignment: .center)
                    .draw(x: bounds.midX, baseline: baseline, context: context, skin: skin)
            }
        }
    }

    /// Every toggle lamp is the same 8 × 8 pt rounded square; only its core changes with state.
    private func drawIndicator(in context: CGContext) {
        let size = AmpXMetrics.keyLampSize
        let lamp = self.indicatorRect ?? CGRect(
            x: AmpXMetrics.keyLampX,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
            NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1).cgColor
        }
        let on = self.displaysActive
        context.addPath(CGPath(roundedRect: lamp, cornerWidth: 2, cornerHeight: 2, transform: nil))
        context.setFillColor(color(5, 13, 10))
        context.fillPath()
        let core = lamp.insetBy(dx: 1, dy: 1)
        context.addPath(CGPath(roundedRect: core, cornerWidth: 1, cornerHeight: 1, transform: nil))
        context.setFillColor(on ? color(71, 240, 51) : color(41, 55, 70))
        context.fillPath()
        context.setFillColor(on ? color(158, 255, 133) : color(69, 83, 103))
        context.fill(CGRect(x: lamp.minX + 1.5, y: lamp.minY + 1.5, width: lamp.width - 3, height: 0.5))
    }

    private func measuredWidth(of text: String) -> CGFloat {
        AmpXLabel(text: text, color: skin.text, fontSize: self.labelFont.pointSize, weight: self.labelWeight)
            .measuredSize(skin: skin).width
    }

    override func mouseDown(with _: NSEvent) {
        guard isEnabled else { return }
        self.pressResetWorkItem?.cancel()
        self.pressResetWorkItem = nil
        self.isPressed = true
    }

    override func cancelInteraction() {
        self.pressResetWorkItem?.cancel()
        self.pressResetWorkItem = nil
        self.isPressed = false
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shouldFire = self.isPressed && isEnabled && bounds.contains(point)
        if shouldFire {
            self.action?()
            self.schedulePressReset()
        } else {
            self.isPressed = false
        }
    }

    /// Presses the button from the keyboard (Return/Enter while focused). Space stays global play/pause.
    @discardableResult
    func performKeyboardPress() -> Bool {
        guard isEnabled else { return false }
        self.action?()
        self.isPressed = true
        self.schedulePressReset()
        return true
    }

    override func accessibilityLabel() -> String? {
        self.accessibilityTitle ?? self.label ?? super.accessibilityLabel()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        self.action?()
        self.isPressed = true
        self.schedulePressReset()
        return true
    }

    private func schedulePressReset() {
        self.pressResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.isPressed = false
        }
        self.pressResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AmpXControlMath.buttonPressDuration, execute: work)
    }
}

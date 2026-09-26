import AppKit

final class AmpXModuleHeaderView: AmpXDrawingView {
    enum HeaderButton {
        case minimize, collapse, close
    }

    let moduleID: AmpXModuleID
    var onCollapse: (() -> Void)?
    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?
    /// Winamp title-bar drag, in screen coordinates: anywhere on the title bar outside the buttons.
    var onTitleDragBegan: ((CGPoint) -> Void)?
    var onTitleDragChanged: ((CGPoint) -> Void)?
    var onTitleDragEnded: ((CGPoint) -> Void)?

    private var titleTracking = false
    private var suppressMouseUp = false
    /// Header key held down by the current click; it paints pressed until mouse-up.
    private var pressedButton: HeaderButton? {
        didSet { needsDisplay = true }
    }

    init(moduleID: AmpXModuleID, skin: any AmpXSkin) {
        self.moduleID = moduleID
        super.init(skin: skin)
        setAccessibilityRole(.group)
        setAccessibilityLabel(self.accessibilityTitle(for: moduleID))
        setAccessibilityHelp("Module header")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, let coordinator = findCoordinator(in: window) {
            coordinator.noteFocusedModule(self.moduleID)
        }
        return became
    }

    private func findCoordinator(in window: NSWindow?) -> AmpXHostCoordinator? {
        guard let window else { return nil }
        return (window.windowController as? AmpXModuleWindowController)?.coordinator
    }

    // MARK: - Geometry (reference coordinates scaled with the module width)

    /// Playlist headers stretch: reference geometry at scale 1, title centered, buttons right-anchored.
    var stretchesHorizontally = false {
        didSet { needsDisplay = true }
    }

    private var scale: CGFloat {
        self.stretchesHorizontally ? 1 : bounds.width / AmpXMetrics.compositionWidth
    }

    /// Extra width beyond the reference, added to right-anchored elements.
    private var rightAnchorOffset: CGFloat {
        self.stretchesHorizontally ? bounds.width - AmpXMetrics.compositionWidth : 0
    }

    /// Half the extra width, added to the centered brand/title group.
    private var centerOffset: CGFloat {
        self.rightAnchorOffset / 2
    }

    private func scaled(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * self.scale, y: rect.minY * self.scale, width: rect.width * self.scale, height: rect.height * self.scale)
    }

    /// Drag handle around the left brand mark; stops short of the gold rules.
    var gripFrame: CGRect {
        self.scaled(CGRect(x: 4, y: 2, width: 29, height: 24.5))
    }

    func headerButtonLayout() -> [(button: HeaderButton, frame: CGRect)] {
        var layout: [(button: HeaderButton, frame: CGRect)] = []
        if self.moduleID == .player {
            layout.append((.minimize, self.scaled(AmpXMetrics.headerMinimizeButton)))
        }
        layout.append((.collapse, self.scaled(AmpXMetrics.headerCollapseButton)))
        layout.append((.close, self.scaled(AmpXMetrics.headerCloseButton)))
        let offset = self.rightAnchorOffset
        guard offset != 0 else { return layout }
        return layout.map { ($0.button, $0.frame.offsetBy(dx: offset, dy: 0)) }
    }

    private var brandLabel: AmpXLabel {
        let isPlayer = self.moduleID == .player
        return AmpXLabel(
            text: "AmpX",
            color: skin.text,
            fontSize: (isPlayer ? 20 : 18) * self.scale,
            weight: .semibold,
            tracking: (isPlayer ? 0.8 : 0.6) * self.scale
        )
    }

    /// Ink-positioned brand + title for non-Player headers, in reference points.
    private struct TitlePlacement {
        /// `nil` places the brand ink a fixed gap before the title.
        var brandInkX: CGFloat?
        var titleInkX: CGFloat
        var baseline: CGFloat
        var ruleGapBefore: CGFloat
        var ruleGapAfter: CGFloat
    }

    /// Equalizer measured (eq-measurements-v2); Playlist estimated from the full reference until Task 4.
    private var titlePlacement: TitlePlacement? {
        switch self.moduleID {
        case .player: nil
        case .equalizer: TitlePlacement(brandInkX: 175.5, titleInkX: 243.5, baseline: 21, ruleGapBefore: 19.5, ruleGapAfter: 18)
        case .playlist: TitlePlacement(brandInkX: 185, titleInkX: 244.5, baseline: 21, ruleGapBefore: 18.5, ruleGapAfter: 16)
        case .enthea: TitlePlacement(brandInkX: nil, titleInkX: 243.5, baseline: 21, ruleGapBefore: 19.5, ruleGapAfter: 16.5)
        }
    }

    private var moduleTitleLabel: AmpXLabel? {
        let title: String? = switch self.moduleID {
        case .player: nil
        case .equalizer: "EQUALIZER"
        case .playlist: "PLAYLIST"
        case .enthea: "ENTHEA"
        }
        return title.map {
            AmpXLabel(text: $0, color: skin.text, fontSize: 14.5 * self.scale, weight: .regular, tracking: 0.25 * self.scale)
        }
    }

    /// Horizontal extent of the centered brand/title group.
    var titleGroupFrame: CGRect {
        let brandWidth = self.brandLabel.measuredSize(skin: skin).width
        let titleWidth = self.moduleTitleLabel.map { $0.measuredSize(skin: skin).width + 20 * self.scale } ?? 0
        let width = brandWidth + titleWidth
        return CGRect(
            x: AmpXMetrics.headerTitleCenterX * self.scale + self.centerOffset - width / 2,
            y: AmpXMetrics.headerBrandInkTop * self.scale,
            width: width,
            height: 18 * self.scale
        )
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1

        AmpXIcon.brand.draw(
            in: self.scaled(AmpXMetrics.headerBrandGlyph),
            context: context,
            skin: skin,
            color: NSColor(srgbRed: 1, green: 0.8, blue: 0.08, alpha: 1)
        )
        self.drawTitleAndRules(in: context, backingScale: backingScale)
        for item in self.headerButtonLayout() {
            self.drawButton(item.button, frame: item.frame, in: context, backingScale: backingScale)
        }
    }

    private func drawTitleAndRules(in context: CGContext, backingScale: CGFloat) {
        if let placement = titlePlacement {
            self.drawPlacedTitleAndRules(placement, in: context, backingScale: backingScale)
            return
        }
        let group = self.titleGroupFrame
        let ruleY = AmpXMetrics.headerRuleY * self.scale
        let ruleHeight = AmpXMetrics.headerRuleHeight * self.scale
        let leftMaxX = group.minX - AmpXMetrics.headerRuleGapBeforeTitle * self.scale
        let rightMinX = group.maxX + AmpXMetrics.headerRuleGapAfterTitle * self.scale
        let leftMinX = AmpXMetrics.headerRuleMinX * self.scale
        skin.headerRule(
            CGRect(x: leftMinX, y: ruleY, width: leftMaxX - leftMinX, height: ruleHeight),
            in: context,
            backingScale: backingScale
        )
        skin.headerRule(
            CGRect(x: rightMinX, y: ruleY, width: AmpXMetrics.headerRuleMaxX * self.scale - rightMinX, height: ruleHeight),
            in: context,
            backingScale: backingScale
        )

        let brand = self.brandLabel
        let brandFont = brand.font(skin: skin)
        let baseline = group.minY + brandFont.capHeight
        brand.draw(x: group.minX, baseline: baseline, context: context, skin: skin)
        if let title = moduleTitleLabel {
            let titleX = group.minX + brand.measuredSize(skin: skin).width + 20 * self.scale
            title.draw(x: titleX, baseline: baseline, context: context, skin: skin)
        }
    }

    private func drawPlacedTitleAndRules(_ placement: TitlePlacement, in context: CGContext, backingScale: CGFloat) {
        let brand = self.brandLabel
        let brandInk = brand.inkBounds(skin: skin)
        let title = self.moduleTitleLabel
        let titleInk = title?.inkBounds(skin: skin) ?? .zero
        let titleInkX = placement.titleInkX * self.scale + self.centerOffset
        let brandInkX = placement.brandInkX.map { $0 * self.scale + self.centerOffset }
            ?? (titleInkX - 20 * self.scale - brandInk.width)
        let brandX = brandInkX - brandInk.minX
        let titleX = titleInkX - titleInk.minX
        let baseline = placement.baseline * self.scale

        let ruleY = AmpXMetrics.headerRuleY * self.scale
        let ruleHeight = AmpXMetrics.headerRuleHeight * self.scale
        let leftMinX = AmpXMetrics.headerRuleMinX * self.scale
        let leftMaxX = brandInkX - placement.ruleGapBefore * self.scale
        let inkMaxX = title == nil ? brandX + brandInk.maxX : titleX + titleInk.maxX
        let rightMinX = inkMaxX + placement.ruleGapAfter * self.scale
        // Run the rule up to the leftmost button: non-Player headers have no minimize button.
        let buttonsMinX = self.headerButtonLayout().map(\.frame.minX).min() ?? bounds.maxX
        let ruleMaxX = buttonsMinX - AmpXMetrics.headerRuleGapBeforeButtons * self.scale
        skin.headerRule(
            CGRect(x: leftMinX, y: ruleY, width: leftMaxX - leftMinX, height: ruleHeight),
            in: context,
            backingScale: backingScale
        )
        skin.headerRule(
            CGRect(x: rightMinX, y: ruleY, width: ruleMaxX - rightMinX, height: ruleHeight),
            in: context,
            backingScale: backingScale
        )

        brand.draw(x: brandX, baseline: baseline, context: context, skin: skin)
        title?.draw(x: titleX, baseline: baseline, context: context, skin: skin)
    }

    /// Header keys share the button face, states and light ink.
    private func drawButton(_ button: HeaderButton, frame: CGRect, in context: CGContext, backingScale: CGFloat) {
        let style = AmpXFaceStyle.resolve(
            pressed: self.pressedButton == button,
            hovered: self.pressedButton == nil && self.hoveredButton == button
        )
        skin.raisedFace(frame, style: style, in: context, backingScale: backingScale)
        let icon: AmpXIcon
        let glyphRect: CGRect
        switch button {
        case .minimize:
            icon = .minimize
            glyphRect = AmpXMetrics.headerMinimizeGlyph
        case .collapse:
            icon = .collapse
            glyphRect = AmpXMetrics.headerCollapseGlyph
        case .close:
            icon = .close
            glyphRect = AmpXMetrics.headerCloseGlyph
        }
        let sink = style.isPressed ? AmpXButton.pressedInkOffset : 0
        icon.draw(
            in: self.scaled(glyphRect).offsetBy(dx: frame.minX, dy: frame.minY + sink),
            context: context,
            skin: skin,
            color: skin.faceInk
        )
    }

    private var hoveredButton: HeaderButton? {
        guard isHovered, let window else { return nil }
        return self.headerButton(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func accessibilityTitle(for moduleID: AmpXModuleID) -> String {
        switch moduleID {
        case .player:
            "AmpX"
        case .equalizer:
            "Equalizer"
        case .playlist:
            "Playlist"
        case .enthea:
            "ENTHEA"
        }
    }

    // MARK: - Interaction

    private func headerButton(at point: CGPoint) -> HeaderButton? {
        self.headerButtonLayout().first { $0.frame.contains(point) }?.button
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        self.suppressMouseUp = false
        guard self.bounds.contains(point) else { return }

        if let button = self.headerButton(at: point) {
            self.pressedButton = button
            return
        }

        if event.clickCount == 2 {
            self.titleTracking = false
            self.suppressMouseUp = true
            self.onCollapse?()
            return
        }

        self.titleTracking = true
        self.onTitleDragBegan?(self.screenPoint(of: event))
    }

    override func mouseDragged(with event: NSEvent) {
        guard self.titleTracking else { return }
        self.onTitleDragChanged?(self.screenPoint(of: event))
    }

    private func screenPoint(of event: NSEvent) -> CGPoint {
        self.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }

    override func mouseUp(with event: NSEvent) {
        let pressed = self.pressedButton
        self.pressedButton = nil
        if self.suppressMouseUp {
            self.suppressMouseUp = false
            return
        }
        if self.titleTracking {
            self.titleTracking = false
            self.onTitleDragEnded?(self.screenPoint(of: event))
            return
        }

        let released = self.headerButton(at: convert(event.locationInWindow, from: nil))
        // A key fires only when the click that pressed it is released over it.
        switch pressed == released ? released : nil {
        case .close:
            self.onClose?()
        case .collapse:
            self.onCollapse?()
        case .minimize:
            self.onMinimize?()
        case nil:
            break
        }
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions: [NSAccessibilityCustomAction] = []

        if self.moduleID == .player, self.onMinimize != nil {
            actions.append(NSAccessibilityCustomAction(name: "Minimize", target: self, selector: #selector(self.accessibilityMinimize)))
        }

        actions.append(NSAccessibilityCustomAction(name: "Collapse", target: self, selector: #selector(self.accessibilityCollapse)))
        actions.append(NSAccessibilityCustomAction(name: "Close", target: self, selector: #selector(self.accessibilityClose)))

        return actions
    }

    @objc func accessibilityCollapse() -> Bool {
        self.onCollapse?()
        return true
    }

    @objc func accessibilityClose() -> Bool {
        self.onClose?()
        return true
    }

    @objc func accessibilityMinimize() -> Bool {
        self.onMinimize?()
        return true
    }
}

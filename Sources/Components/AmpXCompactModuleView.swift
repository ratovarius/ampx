import AppKit

/// Retained collapsed presentation; subclasses own their controls and model bindings.
class AmpXCompactModuleView: AmpXModuleContent {
    let moduleID: AmpXModuleID
    let expandButton: AmpXButton
    let closeButton: AmpXButton
    let minimizeButton: AmpXButton?
    var onExpand: (() -> Void)?
    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?
    /// Winamp title-bar drag in screen coordinates, as on the expanded header.
    var onTitleDragBegan: ((CGPoint) -> Void)?
    var onTitleDragChanged: ((CGPoint) -> Void)?
    var onTitleDragEnded: ((CGPoint) -> Void)?
    private var titleTracking = false

    var chromeLayout: AmpXCompactMetrics.Chrome {
        AmpXCompactMetrics.chrome(moduleID: self.moduleID, width: self.bounds.width)
    }

    var protectedRects: [CGRect] {
        [self.chromeLayout.expand, self.chromeLayout.close] + [self.chromeLayout.minimize].compactMap { $0 }
    }

    init(moduleID: AmpXModuleID, skin: any AmpXSkin) {
        self.moduleID = moduleID
        self.expandButton = AmpXButton(skin: skin)
        self.closeButton = AmpXButton(skin: skin)
        self.minimizeButton = moduleID == .player ? AmpXButton(skin: skin) : nil
        super.init(skin: skin)
        self.setAccessibilityRole(.group)
        self.setAccessibilityLabel("\(moduleID.rawValue.capitalized) compact")
        for button in [self.expandButton, self.closeButton] + [self.minimizeButton].compactMap({ $0 }) {
            button.setAccessibilityElement(true)
            button.confinesHitTestingToBounds = true
            button.focusRingInset = 1
            self.addSubview(button)
        }
        self.expandButton.icon = .expand
        self.expandButton.accessibilityTitle = "Expand \(moduleID.rawValue)"
        self.expandButton.action = { [weak self] in self?.onExpand?() }
        self.closeButton.icon = .close
        self.closeButton.iconColor = skin.faceInk
        self.closeButton.accessibilityTitle = "Close \(moduleID.rawValue)"
        self.closeButton.action = { [weak self] in self?.onClose?() }
        self.minimizeButton?.icon = .minimize
        self.minimizeButton?.iconColor = skin.faceInk
        self.minimizeButton?.accessibilityTitle = "Minimize Player"
        self.minimizeButton?.action = { [weak self] in self?.onMinimize?() }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func cancelInteraction() {
        self.titleTracking = false
    }

    override func cancelInteractions() {
        super.cancelInteractions()
        self.cancelInteraction()
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions = [
            NSAccessibilityCustomAction(name: "Expand", target: self, selector: #selector(self.accessibilityExpand)),
            NSAccessibilityCustomAction(name: "Close", target: self, selector: #selector(self.accessibilityClose)),
        ]
        if self.minimizeButton != nil {
            actions.append(NSAccessibilityCustomAction(name: "Minimize", target: self, selector: #selector(self.accessibilityMinimize)))
        }
        return actions
    }

    @objc private func accessibilityExpand() -> Bool {
        self.expandButton.accessibilityPerformPress()
    }

    @objc private func accessibilityClose() -> Bool {
        self.closeButton.accessibilityPerformPress()
    }

    @objc private func accessibilityMinimize() -> Bool {
        self.minimizeButton?.accessibilityPerformPress() ?? false
    }

    override func layout() {
        super.layout()
        let chrome = self.chromeLayout
        self.expandButton.frame = chrome.expand
        self.closeButton.frame = chrome.close
        if let minimize = chrome.minimize {
            self.minimizeButton?.frame = minimize
        }
        self.expandButton.iconRect = self.expandButton.bounds.insetBy(dx: 5, dy: 4.5)
        self.closeButton.iconRect = self.closeButton.bounds.insetBy(dx: 5, dy: 5)
        if let button = self.minimizeButton {
            button.iconRect = CGRect(x: 5, y: button.bounds.height - 7, width: button.bounds.width - 10, height: 2)
        }
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = self.window?.backingScaleFactor ?? 1
        self.skin.panelFrame(self.bounds, contentFrame: self.bounds.insetBy(dx: 2.5, dy: 2.5), in: context, backingScale: scale)
        self.drawBrand(in: context)
        let brand = self.chromeLayout.brand
        let label = AmpXLabel(text: "AmpX", color: self.skin.text, fontSize: 14.5, weight: .semibold, tracking: 0.1)
        context.saveGState()
        context.translateBy(x: brand.minX, y: brand.maxY - 2.6)
        context.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.18, d: 1, tx: 0, ty: 0))
        label.draw(x: 0, baseline: 0, context: context, skin: self.skin)
        context.restoreGState()
        for separator in self.chromeLayout.separators {
            self.drawSeparator(separator, in: context)
        }
    }

    func drawSeparator(_ rect: CGRect, in context: CGContext) {
        context.setFillColor(self.skin.borderDark.cgColor)
        context.fill(rect)
        context.setFillColor(self.skin.borderHighlight.cgColor)
        context.fill(CGRect(x: rect.midX, y: rect.minY, width: 0.65, height: rect.height))
    }

    private func drawBrand(in context: CGContext) {
        let dy = self.chromeLayout.brand.minY - AmpXCompactMetrics.source(123, 306, 97, 35).minY
        let rect = AmpXCompactMetrics.source(53, 303, 43, 38).offsetBy(dx: 0, dy: dy)
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0.52), CGPoint(x: 0.15, y: 0.52), CGPoint(x: 0.29, y: 0.06),
            CGPoint(x: 0.43, y: 0.06), CGPoint(x: 0.40, y: 0.66), CGPoint(x: 0.52, y: 0.66),
            CGPoint(x: 0.58, y: 0.38), CGPoint(x: 0.65, y: 0.94), CGPoint(x: 0.80, y: 0.94),
            CGPoint(x: 0.84, y: 0.51), CGPoint(x: 1, y: 0.51),
        ].map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        context.setStrokeColor(self.skin.yellow.cgColor)
        context.setLineWidth(0.95)
        context.setLineJoin(.miter)
        context.addLines(between: points)
        context.strokePath()
    }

    override func mouseDown(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        guard self.bounds.contains(point) else { return }
        guard !self.protectedRects.contains(where: { $0.contains(point) }) else { return }
        if event.clickCount == 2 {
            self.cancelInteraction()
            self.onExpand?()
            return
        }
        self.titleTracking = true
        self.onTitleDragBegan?(self.screenPoint(of: event))
    }

    override func mouseDragged(with event: NSEvent) {
        guard self.titleTracking else { return }
        self.onTitleDragChanged?(self.screenPoint(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard self.titleTracking else { return }
        self.titleTracking = false
        self.onTitleDragEnded?(self.screenPoint(of: event))
    }

    private func screenPoint(of event: NSEvent) -> CGPoint {
        self.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }
}

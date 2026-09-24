import AppKit

final class AmpXModuleView: NSView {
    let moduleID: AmpXModuleID
    let content: AmpXModuleContent
    let header: AmpXModuleHeaderView
    let compactContent: AmpXCompactModuleView?

    private(set) var presentation: AmpXHostPresentation = .normal
    private var savedNormalFrame: CGRect = .zero

    private let skin: any AmpXSkin
    private weak var rememberedContentResponder: NSView?

    init(moduleID: AmpXModuleID, content: AmpXModuleContent, skin: any AmpXSkin, compactContent: AmpXCompactModuleView? = nil) {
        self.moduleID = moduleID
        self.content = content
        self.compactContent = compactContent
        self.skin = skin
        self.header = AmpXModuleHeaderView(moduleID: moduleID, skin: skin)
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(self.header)
        addSubview(content)
        if let compactContent {
            compactContent.isHidden = true
            addSubview(compactContent)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel(self.accessibilityModuleLabel(for: moduleID))
        self.wireFocusTraversal()
    }

    func applyPresentationVisibility(_ value: AmpXPresentationVisibility) {
        if !value.expanded {
            self.content.setEffectivelyVisible(false)
        }
        if !value.compact {
            self.compactContent?.setEffectivelyVisible(false)
        }
        if value.expanded {
            self.content.setEffectivelyVisible(true)
        }
        if value.compact {
            self.compactContent?.setEffectivelyVisible(true)
        }
    }

    static func snappedFrame(_ frame: CGRect, backingScale: CGFloat) -> CGRect {
        let minX = AmpXPixelGrid.align(frame.minX, backingScale: backingScale)
        let minY = AmpXPixelGrid.align(frame.minY, backingScale: backingScale)
        let maxX = AmpXPixelGrid.align(frame.maxX, backingScale: backingScale)
        let maxY = AmpXPixelGrid.align(frame.maxY, backingScale: backingScale)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `nonisolated`: AppKit reads this from its layer-display path with no Swift task, and on
    /// macOS 26 an isolated getter crashes in `swift_task_isCurrentExecutor` (see commit 5562af8).
    override nonisolated var isFlipped: Bool {
        true
    }

    func applyLayout(frame: CGRect) {
        self.savedNormalFrame = frame
        guard self.presentation == .normal else { return }
        self.applyNormalLayout(frame: frame)
    }

    func enterTheaterPresentation(containerSize: CGSize) {
        self.presentation = .theater
        self.header.isHidden = true
        frame = CGRect(origin: .zero, size: containerSize)
        self.content.frame = bounds
        self.content.bounds = CGRect(origin: .zero, size: bounds.size)
        needsDisplay = true
    }

    func exitTheaterPresentation(restoreFrame: CGRect) {
        self.presentation = .normal
        self.header.isHidden = false
        let targetFrame = restoreFrame == .zero ? self.savedNormalFrame : restoreFrame
        if targetFrame == .zero {
            frame = restoreFrame
            return
        }
        self.applyNormalLayout(frame: targetFrame)
    }

    override func draw(_: NSRect) {
        guard self.presentation == .normal, !(self.isContentCollapsed && self.compactContent != nil) else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1
        self.skin.panelFrame(
            bounds,
            contentFrame: self.content.isHidden ? nil : self.contentFrameRect,
            in: context,
            backingScale: backingScale
        )
    }

    /// Recessed content frame shared by all modules; spans the header seam as in the reference.
    /// Insets follow the content scale, so a stretched Playlist keeps a constant border width.
    var contentFrameRect: CGRect {
        let scale = Self.stretchesHorizontally(self.moduleID) ? 1 : Self.scale(forWidth: bounds.width)
        let insets = AmpXMetrics.contentFrameInsets
        return CGRect(
            x: insets.left * scale,
            y: insets.top * scale,
            width: bounds.width - (insets.left + insets.right) * scale,
            height: max(0, bounds.height - (insets.top + insets.bottom) * scale)
        )
    }

    private func applyNormalLayout(frame: CGRect) {
        let backingScale = window?.backingScaleFactor ?? 1
        let snappedFrame = Self.snappedFrame(frame, backingScale: backingScale)
        self.frame = snappedFrame
        self.compactContent?.frame = self.bounds
        if self.isContentCollapsed, self.compactContent != nil {
            self.compactContent?.layoutSubtreeIfNeeded()
            return
        }

        // The Playlist stretches instead of scaling (spec Revision 9); every other module scales with its width.
        let stretches = Self.stretchesHorizontally(self.moduleID)
        let scale = stretches ? 1 : Self.scale(forWidth: snappedFrame.width)
        self.header.stretchesHorizontally = stretches
        let headerHeight = AmpXMetrics.headerHeight * scale
        self.header.frame = CGRect(x: 0, y: 0, width: snappedFrame.width, height: headerHeight)
        self.content.frame = CGRect(
            x: 0,
            y: headerHeight,
            width: snappedFrame.width,
            height: max(0, snappedFrame.height - headerHeight)
        )
        // Content lays out and draws in reference points; the bounds scale maps them to the UI scale,
        // keeping hit testing and drawing aligned.
        self.content.bounds = CGRect(
            origin: .zero,
            size: CGSize(width: self.content.frame.width / scale, height: self.content.frame.height / scale)
        )
    }

    static func scale(forWidth width: CGFloat) -> CGFloat {
        width > 0 ? width / AmpXMetrics.compositionWidth : 1
    }

    /// Only the Playlist keeps 1:1 content points at any width.
    static func stretchesHorizontally(_ moduleID: AmpXModuleID) -> Bool {
        moduleID == .playlist
    }

    func setContentCollapsed(_ collapsed: Bool) {
        guard collapsed != self.isContentCollapsed else { return }
        let responder = window?.firstResponder as? NSView
        let ownedFocus = responder.map { $0 === self || $0.isDescendant(of: self) } ?? false
        self.content.cancelInteractions()
        self.compactContent?.cancelInteractions()
        if collapsed {
            self.content.setEffectivelyVisible(false)
            if let responder, responder.isDescendant(of: self.content) {
                self.rememberedContentResponder = responder
            }
            self.content.isHidden = true
            self.header.isHidden = self.compactContent != nil
            self.compactContent?.isHidden = false
        } else {
            self.compactContent?.setEffectivelyVisible(false)
            self.compactContent?.isHidden = true
            self.content.isHidden = false
            self.header.isHidden = false
        }
        self.wireFocusTraversal()
        if ownedFocus {
            let restored = self.rememberedContentResponder
            if !collapsed, let restored, restored.window === window, !restored.isHiddenOrHasHiddenAncestor, restored.acceptsFirstResponder {
                window?.makeFirstResponder(restored)
            } else {
                window?.makeFirstResponder(self.preferredFocusView)
            }
        }
        self.needsDisplay = true
    }

    var isContentCollapsed: Bool {
        self.content.isHidden
    }

    var preferredFocusView: NSView {
        if self.isContentCollapsed, let compactContent {
            return compactContent.expandButton
        }
        return self.header
    }

    func focusableViews() -> [NSView] {
        if self.isContentCollapsed {
            return self.compactContent?.focusableControls() ?? [self.header]
        }
        var views: [NSView] = [header]
        views.append(contentsOf: self.content.focusableControls())
        return views
    }

    func wireFocusTraversal() {
        let views = self.focusableViews()
        guard !views.isEmpty else { return }
        for index in views.indices {
            views[index].nextKeyView = views[(index + 1) % views.count]
        }
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        if self.isContentCollapsed, let compactContent {
            return compactContent.accessibilityCustomActions()
        }
        return self.header.accessibilityCustomActions()
    }

    private func accessibilityModuleLabel(for moduleID: AmpXModuleID) -> String {
        switch moduleID {
        case .player: "Player"
        case .equalizer: "Equalizer"
        case .playlist: "Playlist"
        case .enthea: "ENTHEA"
        }
    }
}

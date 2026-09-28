import AppKit

/// One facet list (GENRE or ARTIST) with right-aligned counts (Library Module spec § Layout).
/// Values sort by name; the absent value ("(No Genre)") comes last.
final class LibraryFacetListView: AmpXControlView {
    static let titleHeight: CGFloat = 22
    static let rowHeight: CGFloat = AmpXMetrics.playlistRowHeight
    private static let fontSize: CGFloat = 12
    private static let inset: CGFloat = 6

    let title: String
    var counts: [LibraryFacetValue: Int] = [:] {
        didSet {
            self.values = Self.sorted(self.counts)
            if let index = self.focusedIndex, index >= self.values.count {
                self.focusedIndex = self.values.isEmpty ? nil : self.values.count - 1
            }
            self.scroll(to: self.scrollOffset)
        }
    }

    private(set) var values: [(LibraryFacetValue, Int)] = []
    var selected: Set<LibraryFacetValue> = [] {
        didSet { needsDisplay = true }
    }

    var onClick: ((LibraryFacetValue, _ command: Bool) -> Void)?
    /// The keyboard cursor: ↑↓ Home End move it, ↩ picks its value and ⌘↩ adds it (as a ⌘-click does).
    private(set) var focusedIndex: Int? {
        didSet { needsDisplay = true }
    }

    private let scrollbar: AmpXScrollbar
    private(set) var scrollOffset: CGFloat = 0

    init(skin: any AmpXSkin, title: String) {
        self.title = title
        self.scrollbar = AmpXScrollbar(skin: skin)
        super.init(skin: skin)
        self.confinesHitTestingToBounds = true
        self.scrollbar.fixedThumbLength = AmpXMetrics.playlistScrollbarThumbLength
        self.scrollbar.onScroll = { [weak self] offset in self?.scroll(to: offset) }
        addSubview(self.scrollbar)
        setAccessibilityRole(.list)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func sorted(_ counts: [LibraryFacetValue: Int]) -> [(LibraryFacetValue, Int)] {
        counts.sorted { lhs, rhs in
            switch (lhs.key, rhs.key) {
            case (.absent, _): false
            case (_, .absent): true
            case let (.text(a), .text(b)):
                a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .numeric]) == .orderedAscending
            }
        }
    }

    func label(for value: LibraryFacetValue) -> String {
        switch value {
        case let .text(text): text
        case .absent: "(No \(self.title.prefix(1))\(self.title.dropFirst().lowercased()))"
        }
    }

    var titleText: String {
        "\(self.title) \(self.values.count)"
    }

    // MARK: - Geometry and scrolling

    private var listViewport: CGRect {
        CGRect(
            x: 0, y: Self.titleHeight,
            width: max(0, bounds.width - AmpXMetrics.playlistScrollbar.width),
            height: max(0, bounds.height - Self.titleHeight)
        )
    }

    var visibleRange: Range<Int> {
        guard !self.values.isEmpty else { return 0 ..< 0 }
        let first = max(0, Int(floor(self.scrollOffset / Self.rowHeight)))
        let last = min(self.values.count, Int(ceil((self.scrollOffset + self.listViewport.height) / Self.rowHeight)))
        return first ..< max(first, last)
    }

    func scroll(to offset: CGFloat) {
        let content = CGFloat(self.values.count) * Self.rowHeight
        self.scrollOffset = AmpXControlMath.clampedScrollOffset(offset, contentLength: content, viewportLength: self.listViewport.height)
        self.scrollbar.contentLength = content
        self.scrollbar.viewportLength = self.listViewport.height
        self.scrollbar.offset = self.scrollOffset
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        self.scrollbar.frame = CGRect(
            x: bounds.width - AmpXMetrics.playlistScrollbar.width, y: Self.titleHeight,
            width: AmpXMetrics.playlistScrollbar.width, height: max(0, bounds.height - Self.titleHeight)
        )
        self.scroll(to: self.scrollOffset)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(skin.display.cgColor)
        context.fill(bounds)
        let titleBar = CGRect(x: 0, y: 0, width: bounds.width, height: Self.titleHeight)
        context.setFillColor(skin.panel.cgColor)
        context.fill(titleBar)
        context.setFillColor(skin.borderDark.cgColor)
        context.fill(CGRect(x: 0, y: titleBar.maxY - 1, width: titleBar.width, height: 1))
        let titleBaseline = titleBar.midY + 4
        AmpXLabel(text: self.title, color: skin.text, fontSize: Self.fontSize)
            .draw(x: Self.inset, baseline: titleBaseline, context: context, skin: skin)
        self.drawRight(
            String(self.values.count),
            maxX: bounds.width - Self.inset,
            baseline: titleBaseline,
            color: skin.text,
            context: context
        )

        let viewport = self.listViewport
        context.saveGState()
        context.clip(to: viewport)
        for index in self.visibleRange {
            let (value, count) = self.values[index]
            let rect = CGRect(
                x: 0, y: viewport.minY + CGFloat(index) * Self.rowHeight - self.scrollOffset,
                width: viewport.width, height: Self.rowHeight
            )
            if self.selected.contains(value) {
                context.setFillColor(skin.selection.cgColor)
                context.fill(rect)
            }
            if index == self.focusedIndex, window?.firstResponder === self {
                let backingScale = window?.backingScaleFactor ?? 1
                context.setStrokeColor(skin.green.withAlphaComponent(0.6).cgColor)
                context.setLineWidth(1 / backingScale)
                context.stroke(AmpXPixelGrid.strokeRect(rect.insetBy(dx: 0.5, dy: 0.5), lineWidth: 1, backingScale: backingScale))
            }
            let baseline = rect.minY + Self.rowHeight / 2 + 4
            let countText = String(count)
            let countWidth = LibraryTrackTableView.textWidth(countText, skin: skin)
            let color = value == .absent ? skin.textDim : skin.green
            let name = LibraryTrackTableView.fittedText(
                self.label(for: value), width: rect.width - Self.inset * 3 - countWidth, skin: skin
            )
            AmpXLabel(text: name, color: color, fontSize: Self.fontSize).draw(
                x: Self.inset,
                baseline: baseline,
                context: context,
                skin: skin
            )
            self.drawRight(countText, maxX: rect.maxX - Self.inset, baseline: baseline, color: color, context: context)
        }
        context.restoreGState()
    }

    private func drawRight(_ text: String, maxX: CGFloat, baseline: CGFloat, color: NSColor, context: CGContext) {
        let width = LibraryTrackTableView.textWidth(text, skin: skin)
        AmpXLabel(text: text, color: color, fontSize: Self.fontSize).draw(x: maxX - width, baseline: baseline, context: context, skin: skin)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point.y >= Self.titleHeight else { return }
        self.handleClick(atRowY: point.y - Self.titleHeight, command: event.modifierFlags.contains(.command))
    }

    /// `y` is measured from the top of the list area.
    func handleClick(atRowY y: CGFloat, command: Bool) {
        let index = Int(floor((y + self.scrollOffset) / Self.rowHeight))
        guard index >= 0, index < self.values.count else { return }
        self.onClick?(self.values[index].0, command)
    }

    /// Keys the Library routes here while the list has focus. Returns false for keys it does not use.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !self.values.isEmpty else { return false }
        let last = self.values.count - 1
        switch event.keyCode {
        case 125, 126:
            let delta = event.keyCode == 125 ? 1 : -1
            self.focusedIndex = self.focusedIndex.map { min(max($0 + delta, 0), last) } ?? (delta > 0 ? 0 : last)
        case 115, 119:
            self.focusedIndex = event.keyCode == 115 ? 0 : last
        case 116, 121:
            let page = max(1, Int(self.listViewport.height / Self.rowHeight))
            let delta = event.keyCode == 121 ? page : -page
            self.focusedIndex = min(max((self.focusedIndex ?? 0) + delta, 0), last)
        case 36, 76:
            guard let index = self.focusedIndex else { return false }
            self.onClick?(self.values[index].0, flags.contains(.command))
            return true
        default:
            return false
        }
        self.scrollToFocused()
        return true
    }

    private func scrollToFocused() {
        guard let index = self.focusedIndex else { return }
        let top = CGFloat(index) * Self.rowHeight
        let viewport = self.listViewport.height
        if top < self.scrollOffset {
            self.scroll(to: top)
        } else if top + Self.rowHeight > self.scrollOffset + viewport {
            self.scroll(to: top + Self.rowHeight - viewport)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        self.scroll(to: self.scrollOffset - event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8))
    }

    // MARK: - Accessibility

    override func accessibilityChildren() -> [Any]? {
        self.visibleRange.map { index in
            let (value, count) = self.values[index]
            let element = LibraryRowAccessibilityElement(
                isSelected: { [weak self] in self?.selected.contains(value) ?? false },
                select: { [weak self] in self?.onClick?(value, false) }
            )
            element.setAccessibilityRole(.row)
            element.setAccessibilityParent(self)
            element.setAccessibilityLabel("\(self.label(for: value)), \(count)")
            return element
        }
    }
}

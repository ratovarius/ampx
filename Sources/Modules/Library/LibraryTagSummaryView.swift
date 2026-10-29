import AppKit

/// What writing rekordbox data into file tags would do, drawn over the track table before the first write and before
/// a per-track write (DJ mode spec Revision 2 § Tag writing). WRITE TAGS or CANCEL; Esc cancels.
final class LibraryTagSummaryView: AmpXDrawingView {
    static let halfDoubleHeading = "TEMPO HALF OR DOUBLE: CHECK IN REKORDBOX"

    let writeButton: AmpXButton
    let cancelButton: AmpXButton
    var onWrite: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var summaryLines: [String] = []
    /// The heading and paths of the scrollable list.
    private(set) var entryLines: [String] = []

    private let scrollbar: AmpXScrollbar
    private var scrollOffset: CGFloat = 0
    private static let lineHeight: CGFloat = 18
    private static let summaryTop: CGFloat = 12
    private static let footerHeight: CGFloat = 44

    override init(skin: any AmpXSkin) {
        self.writeButton = AmpXButton(skin: skin)
        self.cancelButton = AmpXButton(skin: skin)
        self.scrollbar = AmpXScrollbar(skin: skin)
        super.init(skin: skin)
        self.writeButton.label = "WRITE TAGS"
        self.cancelButton.label = "CANCEL"
        for button in [self.writeButton, self.cancelButton] {
            button.applyKeyLabelStyle()
            addSubview(button)
        }
        self.writeButton.action = { [weak self] in self?.onWrite?() }
        self.cancelButton.action = { [weak self] in self?.onCancel?() }
        self.scrollbar.fixedThumbLength = AmpXMetrics.playlistScrollbarThumbLength
        self.scrollbar.onScroll = { [weak self] offset in self?.scroll(to: offset) }
        addSubview(self.scrollbar)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Tag writing summary")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func summary(_ summary: TagWriteSummary) -> [String] {
        let fields = TagField.allCases.map { "\($0.rawValue.uppercased()) \(LibraryFormatting.grouped(summary.perField[$0] ?? 0))" }
        return [
            "\(LibraryFormatting.grouped(summary.filesToUpdate)) files to update",
            fields.joined(separator: " · "),
            "Read-only, skipped: \(LibraryFormatting.grouped(summary.skippedReadOnly.count))",
            "Not readable now: \(LibraryFormatting.grouped(summary.unreadable))",
        ]
    }

    func show(_ summary: TagWriteSummary) {
        self.summaryLines = Self.summary(summary)
        self.entryLines = summary.halfDouble.isEmpty ? [] : [Self.halfDoubleHeading] + summary.halfDouble
        self.scrollOffset = 0
        needsLayout = true
        needsDisplay = true
    }

    /// Esc cancels.
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53 else { return false }
        self.onCancel?()
        return true
    }

    private var listViewport: CGRect {
        let top = Self.summaryTop + CGFloat(self.summaryLines.count) * Self.lineHeight + 10
        return CGRect(
            x: 0, y: top, width: max(0, bounds.width - AmpXMetrics.playlistScrollbar.width),
            height: max(0, bounds.height - top - Self.footerHeight)
        )
    }

    private func scroll(to offset: CGFloat) {
        let content = CGFloat(self.entryLines.count) * Self.lineHeight
        self.scrollOffset = min(max(0, offset), max(0, content - self.listViewport.height))
        self.scrollbar.offset = self.scrollOffset
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        self.scroll(to: self.scrollOffset - event.scrollingDeltaY)
    }

    override func layout() {
        super.layout()
        let viewport = self.listViewport
        self.scrollbar.frame = CGRect(
            x: bounds.width - AmpXMetrics.playlistScrollbar.width, y: viewport.minY,
            width: AmpXMetrics.playlistScrollbar.width, height: viewport.height
        )
        self.scrollbar.contentLength = CGFloat(self.entryLines.count) * Self.lineHeight
        self.scrollbar.viewportLength = viewport.height
        self.scrollbar.offset = self.scrollOffset
        self.writeButton.frame = CGRect(x: bounds.width - 222, y: bounds.height - 36, width: 112, height: 28)
        self.cancelButton.frame = CGRect(x: bounds.width - 106, y: bounds.height - 36, width: 96, height: 28)
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(skin.display.cgColor)
        context.fill(bounds)
        var baseline = Self.summaryTop + 13
        for (index, line) in self.summaryLines.enumerated() {
            let text = LibraryTrackTableView.fittedText(line, width: bounds.width - 24, skin: skin)
            AmpXLabel(text: text, color: index == 0 ? skin.text : skin.green, fontSize: 12, weight: index == 0 ? .medium : .regular)
                .draw(x: 12, baseline: baseline, context: context, skin: skin)
            baseline += Self.lineHeight
        }

        let viewport = self.listViewport
        context.saveGState()
        context.clip(to: viewport)
        let first = max(0, Int(self.scrollOffset / Self.lineHeight))
        let last = min(self.entryLines.count, first + Int(viewport.height / Self.lineHeight) + 2)
        if first < last {
            for index in first ..< last {
                let line = self.entryLines[index]
                let y = viewport.minY + CGFloat(index) * Self.lineHeight - self.scrollOffset + 13
                let isHeading = line == Self.halfDoubleHeading
                let x: CGFloat = isHeading ? 12 : 24
                let text = LibraryTrackTableView.fittedText(line, width: viewport.width - x - 8, skin: skin)
                AmpXLabel(text: text, color: isHeading ? skin.text : skin.textDim, fontSize: 11, weight: isHeading ? .medium : .regular)
                    .draw(x: x, baseline: y, context: context, skin: skin)
            }
        }
        context.restoreGState()
    }

    // MARK: - Accessibility

    override func accessibilityChildren() -> [Any]? {
        var children: [Any] = (self.summaryLines + self.entryLines).enumerated().map { index, line in
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.staticText)
            element.setAccessibilityValue(line)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(CGRect(
                x: 12, y: Self.summaryTop + CGFloat(index) * Self.lineHeight, width: max(0, bounds.width - 24), height: Self.lineHeight
            ))
            return element
        }
        children += [self.writeButton, self.cancelButton, self.scrollbar]
        return children
    }
}

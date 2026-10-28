import AppKit

/// MIXES WELL sidebar (Library Module spec § MIXES WELL in L2; DJ mode spec Revision 2 § MIXES WELL): the
/// PLAYING | SELECTED switch persists, the reference card follows it, and the list shows the tracks that mix well,
/// then a CHANGE CHAPTER group for half- and double-tempo matches. + QUEUE appends the selected match.
final class LibraryMixesSidebarView: AmpXDrawingView {
    static let width: CGFloat = 260
    static let chapterHeading = "CHANGE CHAPTER"

    let playingButton: AmpXButton
    let selectedButton: AmpXButton
    let queueButton: AmpXButton
    var onModeChange: ((Bool) -> Void)?
    var onQueue: ((LibraryRow) -> Void)?

    private(set) var referenceText = "No track"
    var followsSelection = false {
        didSet {
            self.playingButton.isActive = !self.followsSelection
            self.selectedButton.isActive = self.followsSelection
        }
    }

    var selectedMatchID: UUID? {
        didSet {
            self.queueButton.isEnabled = self.selectedMatch != nil
            needsDisplay = true
        }
    }

    private enum Entry {
        case heading
        case match(MixesWellMatch)
    }

    private var reference: LibraryRow?
    private var result: MixesWellResult?
    private var entries: [Entry] = []
    private let scrollbar: AmpXScrollbar
    private var scrollOffset: CGFloat = 0

    private static let titleHeight: CGFloat = 26
    private static let cardHeight: CGFloat = 46
    private static let rowHeight: CGFloat = 34
    private static let headingHeight: CGFloat = 22
    private static let queueAreaHeight: CGFloat = 40

    override init(skin: any AmpXSkin) {
        self.playingButton = AmpXButton(skin: skin)
        self.selectedButton = AmpXButton(skin: skin)
        self.queueButton = AmpXButton(skin: skin)
        self.scrollbar = AmpXScrollbar(skin: skin)
        super.init(skin: skin)
        self.playingButton.label = "PLAYING"
        self.selectedButton.label = "SELECTED"
        self.queueButton.label = "+ QUEUE"
        self.queueButton.isEnabled = false
        for button in [self.playingButton, self.selectedButton, self.queueButton] {
            button.applyKeyLabelStyle()
            addSubview(button)
        }
        self.scrollbar.fixedThumbLength = AmpXMetrics.playlistScrollbarThumbLength
        self.scrollbar.onScroll = { [weak self] offset in self?.scroll(to: offset) }
        addSubview(self.scrollbar)
        self.playingButton.isActive = true
        self.playingButton.action = { [weak self] in self?.setMode(followsSelection: false) }
        self.selectedButton.action = { [weak self] in self?.setMode(followsSelection: true) }
        self.queueButton.action = { [weak self] in self?.queueSelection() }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Mixes well")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// What the list area says instead of matches; nil while matches are shown.
    var placeholderText: String? {
        guard let reference = self.reference else { return "No track" }
        guard reference.bpm != nil, reference.camelotKey != nil else { return "This track has no BPM or key." }
        guard let result = self.result, !result.matches.isEmpty || !result.chapter.isEmpty else { return "No matches." }
        return nil
    }

    /// The drawn list as text, in order: per match its title line then its tags line, and the chapter heading.
    var lines: [String] {
        self.entries.flatMap { entry -> [String] in
            switch entry {
            case .heading: [Self.chapterHeading]
            case let .match(match): [Self.title(match.row), match.tags.joined(separator: "  ")]
            }
        }
    }

    private var selectedMatch: MixesWellMatch? {
        guard let id = self.selectedMatchID else { return nil }
        for case let .match(match) in self.entries where match.row.id == id {
            return match
        }
        return nil
    }

    private func setMode(followsSelection: Bool) {
        guard followsSelection != self.followsSelection else { return }
        self.followsSelection = followsSelection
        self.onModeChange?(followsSelection)
    }

    func updateReference(_ row: LibraryRow?) {
        self.reference = row
        guard let row else {
            self.referenceText = "No track"
            self.updateMatches(nil)
            return
        }
        var parts = [Self.title(row)]
        if let bpm = row.bpm {
            parts.append("\(Int(bpm.rounded())) BPM")
        }
        if let key = row.musicalKey {
            parts.append(key)
        }
        self.referenceText = parts.joined(separator: " · ")
        needsDisplay = true
    }

    func updateMatches(_ result: MixesWellResult?) {
        self.result = result
        var entries = (result?.matches ?? []).map(Entry.match)
        if let chapter = result?.chapter, !chapter.isEmpty {
            entries.append(.heading)
            entries += chapter.map(Entry.match)
        }
        self.entries = entries
        if self.selectedMatch == nil {
            self.selectedMatchID = nil
        }
        self.scroll(to: self.scrollOffset)
        needsLayout = true
        needsDisplay = true
    }

    private func queueSelection() {
        if let match = self.selectedMatch {
            self.onQueue?(match.row)
        }
    }

    private static func title(_ row: LibraryRow) -> String {
        "\(row.artist) – \(row.title)"
    }

    // MARK: - List geometry

    private var listViewport: CGRect {
        let top = Self.titleHeight + 6 + Self.cardHeight + 6
        return CGRect(
            x: 0, y: top, width: max(0, bounds.width - AmpXMetrics.playlistScrollbar.width),
            height: max(0, bounds.height - top - Self.queueAreaHeight)
        )
    }

    private func height(of entry: Entry) -> CGFloat {
        if case .heading = entry {
            return Self.headingHeight
        }
        return Self.rowHeight
    }

    private var contentHeight: CGFloat {
        self.entries.reduce(0) { $0 + self.height(of: $1) }
    }

    private func scroll(to offset: CGFloat) {
        self.scrollOffset = min(max(0, offset), max(0, self.contentHeight - self.listViewport.height))
        self.scrollbar.offset = self.scrollOffset
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        self.scroll(to: self.scrollOffset - event.scrollingDeltaY)
    }

    /// The entry under a point in view coordinates, with its frame.
    private func entry(at point: CGPoint) -> (Entry, CGRect)? {
        let viewport = self.listViewport
        guard viewport.contains(point) else { return nil }
        var y = viewport.minY - self.scrollOffset
        for entry in self.entries {
            let frame = CGRect(x: 0, y: y, width: viewport.width, height: self.height(of: entry))
            if frame.contains(point) {
                return (entry, frame)
            }
            y += frame.height
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let (entry, _) = self.entry(at: point), case let .match(match) = entry else {
            super.mouseDown(with: event)
            return
        }
        self.selectedMatchID = match.row.id
        if event.clickCount == 2 {
            self.onQueue?(match.row)
        }
    }

    override func layout() {
        super.layout()
        let buttonHeight: CGFloat = 22
        self.selectedButton.frame = CGRect(x: bounds.width - 86, y: 2, width: 84, height: buttonHeight)
        self.playingButton.frame = CGRect(x: bounds.width - 86 - 78, y: 2, width: 76, height: buttonHeight)
        self.queueButton.frame = CGRect(x: 6, y: bounds.height - 34, width: bounds.width - 12, height: 28)
        let viewport = self.listViewport
        self.scrollbar.frame = CGRect(
            x: bounds.width - AmpXMetrics.playlistScrollbar.width, y: viewport.minY,
            width: AmpXMetrics.playlistScrollbar.width, height: viewport.height
        )
        self.scrollbar.contentLength = self.contentHeight
        self.scrollbar.viewportLength = viewport.height
        self.scrollbar.isHidden = self.contentHeight <= viewport.height
        self.scroll(to: self.scrollOffset)
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(skin.display.cgColor)
        context.fill(bounds)
        context.setFillColor(skin.panel.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: Self.titleHeight))
        AmpXLabel(text: "MIXES WELL", color: skin.text, fontSize: 12, weight: .medium)
            .draw(x: 6, baseline: Self.titleHeight / 2 + 4, context: context, skin: skin)

        let card = CGRect(x: 6, y: Self.titleHeight + 6, width: bounds.width - 12, height: Self.cardHeight)
        context.setStrokeColor(skin.borderDark.cgColor)
        context.stroke(card.insetBy(dx: 0.5, dy: 0.5))
        let reference = LibraryTrackTableView.fittedText(self.referenceText, width: card.width - 12, skin: skin)
        AmpXLabel(text: reference, color: skin.green, fontSize: 12)
            .draw(x: card.minX + 6, baseline: card.midY + 4, context: context, skin: skin)

        if let placeholder = self.placeholderText {
            let message = CGRect(x: 12, y: card.maxY + 16, width: bounds.width - 24, height: 60)
            AmpXLabel(text: placeholder, color: skin.textDim, fontSize: 11).draw(in: message, context: context, skin: skin)
            return
        }
        self.drawList(context)
    }

    private func drawList(_ context: CGContext) {
        let viewport = self.listViewport
        context.saveGState()
        context.clip(to: viewport)
        var y = viewport.minY - self.scrollOffset
        for entry in self.entries {
            let height = self.height(of: entry)
            defer { y += height }
            guard y + height >= viewport.minY, y <= viewport.maxY else { continue }
            switch entry {
            case .heading:
                AmpXLabel(text: Self.chapterHeading, color: skin.text, fontSize: 11, weight: .medium)
                    .draw(x: 8, baseline: y + 15, context: context, skin: skin)
            case let .match(match):
                if match.row.id == self.selectedMatchID {
                    context.setFillColor(skin.selection.cgColor)
                    context.fill(CGRect(x: 0, y: y, width: viewport.width, height: height))
                }
                let title = LibraryTrackTableView.fittedText(Self.title(match.row), width: viewport.width - 16, skin: skin)
                AmpXLabel(text: title, color: skin.green, fontSize: 12).draw(x: 8, baseline: y + 14, context: context, skin: skin)
                AmpXLabel(text: match.tags.joined(separator: "  "), color: skin.textDim, fontSize: 10)
                    .draw(x: 8, baseline: y + 28, context: context, skin: skin)
            }
        }
        context.restoreGState()
    }

    // MARK: - Accessibility

    /// The buttons, then each visible match (title and tags) and the chapter heading as static text.
    override func accessibilityChildren() -> [Any]? {
        var children: [Any] = [self.playingButton, self.selectedButton]
        let viewport = self.listViewport
        var y = viewport.minY - self.scrollOffset
        for entry in self.entries {
            let height = self.height(of: entry)
            defer { y += height }
            let frame = CGRect(x: 0, y: y, width: viewport.width, height: height).intersection(viewport)
            guard !frame.isEmpty else { continue }
            let text: String = switch entry {
            case .heading: Self.chapterHeading
            case let .match(match): "\(Self.title(match.row)), \(match.tags.joined(separator: ", "))"
            }
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.staticText)
            element.setAccessibilityValue(text)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(frame)
            children.append(element)
        }
        children.append(self.queueButton)
        return children
    }
}

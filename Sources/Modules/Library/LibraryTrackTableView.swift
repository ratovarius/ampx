import AppKit

/// Custom-drawn track table (Library Module spec § Layout): a sortable header, 22 pt rows drawn for the
/// visible range only, show/hide columns from the header's context menu, click/⇧/⌘ selection, double-click
/// activation, file-URL drags to the Playlist, and an `AmpXScrollbar`.
final class LibraryTrackTableView: AmpXControlView, NSDraggingSource {
    static let headerHeight: CGFloat = 22
    static let rowHeight: CGFloat = AmpXMetrics.playlistRowHeight
    static let fontSize: CGFloat = 12
    private static let cellInset: CGFloat = 6
    private static let dragThreshold: CGFloat = 4

    var rows: [LibraryRow] = [] {
        didSet {
            self.scroll(to: self.scrollOffset)
            self.needsDisplay = true
        }
    }

    var columns = LibraryColumnSet.default {
        didSet { needsDisplay = true }
    }

    var selection = LibrarySelection() {
        didSet { needsDisplay = true }
    }

    var sort: (column: LibrarySortColumn, ascending: Bool) = (.artist, true) {
        didSet { needsDisplay = true }
    }

    var onSelectionChange: ((LibrarySelection) -> Void)?

    /// Centred message over the empty rows area: the Library's empty state or its error.
    var placeholder: String? {
        didSet { needsDisplay = true }
    }

    var placeholderIsError = false
    var onSortClick: ((LibrarySortColumn) -> Void)?
    var onColumnsChange: ((LibraryColumnSet) -> Void)?
    var onActivate: ((UUID) -> Void)?
    /// Called as a drag starts, with the rows being dragged (to register their roots' bookmarks).
    var onDragBegan: (([LibraryRow]) -> Void)?

    private let scrollbar: AmpXScrollbar
    private(set) var scrollOffset: CGFloat = 0
    private var dragStart: (point: CGPoint, index: Int)?

    override init(skin: any AmpXSkin) {
        self.scrollbar = AmpXScrollbar(skin: skin)
        super.init(skin: skin)
        self.confinesHitTestingToBounds = true
        self.scrollbar.fixedThumbLength = AmpXMetrics.playlistScrollbarThumbLength
        self.scrollbar.onScroll = { [weak self] offset in self?.scroll(to: offset) }
        addSubview(self.scrollbar)
        setAccessibilityRole(.table)
        setAccessibilityLabel("Library tracks")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Geometry

    private var scrollbarWidth: CGFloat {
        AmpXMetrics.playlistScrollbar.width
    }

    private var rowsViewport: CGRect {
        CGRect(
            x: 0,
            y: Self.headerHeight,
            width: max(0, bounds.width - self.scrollbarWidth),
            height: max(0, bounds.height - Self.headerHeight)
        )
    }

    private var contentLength: CGFloat {
        CGFloat(self.rows.count) * Self.rowHeight
    }

    func columnFrames() -> [(LibraryColumn, CGRect)] {
        self.columns.frames(width: self.rowsViewport.width)
    }

    var visibleRowRange: Range<Int> {
        guard !self.rows.isEmpty else { return 0 ..< 0 }
        let first = max(0, Int(floor(self.scrollOffset / Self.rowHeight)))
        let last = min(self.rows.count, Int(ceil((self.scrollOffset + self.rowsViewport.height) / Self.rowHeight)))
        return first ..< max(first, last)
    }

    override func layout() {
        super.layout()
        self.scrollbar.frame = CGRect(
            x: bounds.width - self.scrollbarWidth,
            y: Self.headerHeight,
            width: self.scrollbarWidth,
            height: max(0, bounds.height - Self.headerHeight)
        )
        self.syncScrollbar()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
        self.scroll(to: self.scrollOffset)
    }

    func scroll(to offset: CGFloat) {
        let clamped = AmpXControlMath.clampedScrollOffset(
            offset, contentLength: self.contentLength, viewportLength: self.rowsViewport.height
        )
        self.scrollOffset = clamped
        self.syncScrollbar()
        needsDisplay = true
    }

    private func syncScrollbar() {
        self.scrollbar.contentLength = self.contentLength
        self.scrollbar.viewportLength = self.rowsViewport.height
        self.scrollbar.offset = self.scrollOffset
    }

    /// Scrolls the focused row into view (keyboard navigation).
    func scrollToFocused() {
        guard let focused = self.selection.focused, let index = self.rows.firstIndex(where: { $0.id == focused }) else { return }
        let top = CGFloat(index) * Self.rowHeight
        let viewport = self.rowsViewport.height
        if top < self.scrollOffset {
            self.scroll(to: top)
        } else if top + Self.rowHeight > self.scrollOffset + viewport {
            self.scroll(to: top + Self.rowHeight - viewport)
        }
    }

    var visibleRowCount: Int {
        max(1, Int(self.rowsViewport.height / Self.rowHeight))
    }

    // MARK: - Text

    static func textWidth(_ text: String, skin: any AmpXSkin) -> CGFloat {
        AmpXLabel(text: text, color: .white, fontSize: self.fontSize).measuredSize(skin: skin).width
    }

    /// `text` truncated with "…" to fit `width`; empty when not even the ellipsis fits.
    static func fittedText(_ text: String, width: CGFloat, skin: any AmpXSkin) -> String {
        if self.textWidth(text, skin: skin) <= width {
            return text
        }
        guard self.textWidth("…", skin: skin) <= width else { return "" }
        let characters = Array(text)
        var low = 0
        var high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if self.textWidth(String(characters[0 ..< mid]) + "…", skin: skin) <= width {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return String(characters[0 ..< low]) + "…"
    }

    func cellText(_ column: LibraryColumn, row: LibraryRow, index: Int) -> String {
        switch column {
        case .number: return String(index + 1)
        case .artist: return row.artist
        case .title: return row.title
        case .genre: return row.genre ?? ""
        case .time: return AmpXTimeFormatting.format(row.duration)
        case .bpm:
            guard let bpm = row.bpm else { return "—" }
            return bpm.rounded() == bpm ? String(Int(bpm)) : String(format: "%.1f", bpm)
        case .key: return row.musicalKey ?? "—"
        case .camelot: return row.camelotKey ?? "—"
        case .kbps:
            guard row.bitrate > 0 else { return "—" }
            let kbps = String(Int((Double(row.bitrate) / 1000).rounded()))
            return row.bitrateIsDerived ? "~" + kbps : kbps
        case .format: return row.codec.uppercased()
        case .label: return row.label ?? ""
        case .remixer: return row.remixer ?? ""
        case .composer: return row.composer ?? ""
        case .grouping: return row.grouping ?? ""
        case .mix: return row.mix ?? ""
        }
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1
        context.setFillColor(skin.display.cgColor)
        context.fill(bounds)
        let frames = self.columnFrames()
        self.drawHeader(frames: frames, context: context)

        let viewport = self.rowsViewport
        if let placeholder = self.placeholder {
            let rect = CGRect(x: viewport.minX + 16, y: viewport.midY - 26, width: max(0, viewport.width - 32), height: 20)
            AmpXLabel(
                text: placeholder,
                color: self.placeholderIsError ? skin.orange : skin.textDim,
                fontSize: 13,
                alignment: .center
            ).draw(in: rect, context: context, skin: skin)
        }
        context.saveGState()
        context.clip(to: viewport)
        for index in self.visibleRowRange {
            let row = self.rows[index]
            let rect = CGRect(
                x: 0, y: viewport.minY + CGFloat(index) * Self.rowHeight - self.scrollOffset,
                width: viewport.width, height: Self.rowHeight
            )
            if self.selection.ids.contains(row.id) {
                context.setFillColor(skin.selection.cgColor)
                context.fill(rect)
            }
            if self.selection.focused == row.id {
                context.setStrokeColor(skin.green.withAlphaComponent(0.6).cgColor)
                context.setLineWidth(1 / backingScale)
                context.stroke(AmpXPixelGrid.strokeRect(rect.insetBy(dx: 0.5, dy: 0.5), lineWidth: 1, backingScale: backingScale))
            }
            let baseline = rect.minY + Self.rowHeight / 2 + 4
            for (column, frame) in frames {
                let text = self.cellText(column, row: row, index: index)
                let isDash = text == "—"
                let color = !row.isAvailable || isDash ? skin.textDim : skin.green
                self.drawCell(text, column: column, frame: frame, baseline: baseline, color: color, context: context)
            }
        }
        context.restoreGState()
        drawFocusRing(in: context, backingScale: backingScale)
    }

    private func drawHeader(frames: [(LibraryColumn, CGRect)], context: CGContext) {
        let header = CGRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight)
        context.setFillColor(skin.panel.cgColor)
        context.fill(header)
        context.setFillColor(skin.borderDark.cgColor)
        context.fill(CGRect(x: 0, y: header.maxY - 1, width: header.width, height: 1))
        let baseline = header.midY + 4
        for (column, frame) in frames {
            var title = column.title
            if column.sortColumn == self.sort.column {
                title += self.sort.ascending ? " ▲" : " ▼"
            }
            self.drawCell(title, column: column, frame: frame, baseline: baseline, color: skin.text, context: context)
            context.setFillColor(skin.borderDark.cgColor)
            context.fill(CGRect(x: frame.maxX - 1, y: 4, width: 1, height: header.height - 8))
        }
    }

    private func drawCell(_ text: String, column: LibraryColumn, frame: CGRect, baseline: CGFloat, color: NSColor, context: CGContext) {
        let available = max(0, frame.width - Self.cellInset * 2)
        let fitted = Self.fittedText(text, width: available, skin: skin)
        guard !fitted.isEmpty else { return }
        let width = Self.textWidth(fitted, skin: skin)
        let x = column.isRightAligned ? frame.maxX - Self.cellInset - width : frame.minX + Self.cellInset
        AmpXLabel(text: fitted, color: color, fontSize: Self.fontSize).draw(x: x, baseline: baseline, context: context, skin: skin)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if point.y < Self.headerHeight {
            self.handleHeaderClick(atX: point.x)
            return
        }
        let flags = event.modifierFlags.intersection([.shift, .command])
        self.handleRowClick(atY: point.y - Self.headerHeight, modifiers: flags, clickCount: event.clickCount)
        if let index = self.rowIndex(atRowY: point.y - Self.headerHeight) {
            self.dragStart = (point, index)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = self.dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.point.x, point.y - start.point.y) > Self.dragThreshold else { return }
        self.dragStart = nil
        let dragged = self.draggedRows(fromRowAt: start.index)
        guard !dragged.isEmpty else { return }
        self.onDragBegan?(dragged)
        let items = dragged.map { row -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: row.url as NSURL)
            item.setDraggingFrame(CGRect(origin: point, size: CGSize(width: 160, height: Self.rowHeight)), contents: nil)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with _: NSEvent) {
        self.dragStart = nil
    }

    override func cancelInteraction() {
        self.dragStart = nil
    }

    override func scrollWheel(with event: NSEvent) {
        self.scroll(to: self.scrollOffset - event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8))
    }

    override var acceptsFirstResponder: Bool {
        isEnabled
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return point.y < Self.headerHeight ? self.headerMenu() : nil
    }

    func handleHeaderClick(atX x: CGFloat) {
        guard let column = self.columnFrames().first(where: { $0.1.minX <= x && x < $0.1.maxX })?.0,
              let sort = column.sortColumn
        else { return }
        self.onSortClick?(sort)
    }

    /// `y` is measured from the top of the rows area.
    func handleRowClick(atY y: CGFloat, modifiers: NSEvent.ModifierFlags, clickCount: Int) {
        guard let index = self.rowIndex(atRowY: y) else { return }
        let id = self.rows[index].id
        let order = self.rows.map(\.id)
        var selection = self.selection
        if modifiers.contains(.shift) {
            selection.shiftClick(id, order: order)
        } else if modifiers.contains(.command) {
            selection.commandClick(id)
        } else {
            selection.click(id, order: order)
        }
        self.selection = selection
        self.onSelectionChange?(selection)
        if clickCount >= 2 {
            self.onActivate?(id)
        }
    }

    private func rowIndex(atRowY y: CGFloat) -> Int? {
        let index = Int(floor((y + self.scrollOffset) / Self.rowHeight))
        return index >= 0 && index < self.rows.count ? index : nil
    }

    /// The available rows a drag carries: the selection when the dragged row is in it, else that row alone.
    func draggedRows(fromRowAt index: Int) -> [LibraryRow] {
        guard index >= 0, index < self.rows.count else { return [] }
        let row = self.rows[index]
        let rows = self.selection.ids.contains(row.id) ? self.rows.filter { self.selection.ids.contains($0.id) } : [row]
        return rows.filter(\.isAvailable)
    }

    func headerMenu() -> NSMenu {
        let menu = NSMenu(title: "Columns")
        for column in LibraryColumn.allCases where column.isHideable {
            let item = NSMenuItem(title: column.title, action: #selector(self.toggleColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.rawValue
            item.state = self.columns.visible.contains(column) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let column = LibraryColumn(rawValue: raw) else { return }
        var columns = self.columns
        columns.toggle(column)
        self.columns = columns
        self.onColumnsChange?(columns)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    // MARK: - Accessibility

    override func accessibilityChildren() -> [Any]? {
        self.visibleRowRange.map { index in
            let row = self.rows[index]
            let element = LibraryRowAccessibilityElement(
                isSelected: { [weak self] in self?.selection.ids.contains(row.id) ?? false },
                select: { [weak self] in
                    guard let self else { return }
                    var selection = self.selection
                    selection.click(row.id, order: self.rows.map(\.id))
                    self.selection = selection
                    self.onSelectionChange?(selection)
                }
            )
            element.setAccessibilityRole(.row)
            element.setAccessibilityParent(self)
            element.setAccessibilityLabel(
                "\(row.artist), \(row.title), \(AmpXTimeFormatting.format(row.duration))" +
                    (row.bpm.map { ", \(Int($0.rounded())) BPM" } ?? "")
            )
            element.setAccessibilityFrameInParentSpace(CGRect(
                x: 0, y: Self.headerHeight + CGFloat(index) * Self.rowHeight - self.scrollOffset,
                width: self.rowsViewport.width, height: Self.rowHeight
            ))
            return element
        }
    }

    override func accessibilitySelectedRows() -> [Any]? {
        self.accessibilityChildren()?.filter { ($0 as? NSAccessibilityElement)?.isAccessibilitySelected() == true }
    }
}

/// A table row for VoiceOver whose selection reads and writes the table's `LibrarySelection`.
final class LibraryRowAccessibilityElement: NSAccessibilityElement {
    private let isSelected: () -> Bool
    private let select: () -> Void

    init(isSelected: @escaping () -> Bool, select: @escaping () -> Void) {
        self.isSelected = isSelected
        self.select = select
        super.init()
    }

    override func isAccessibilitySelected() -> Bool {
        self.isSelected()
    }

    override func setAccessibilitySelected(_ selected: Bool) {
        if selected {
            self.select()
        }
    }
}

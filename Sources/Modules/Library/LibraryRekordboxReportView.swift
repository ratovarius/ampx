import AppKit

/// The last rekordbox import's report, drawn over the track table (rekordbox sync spec § UI). Read-only: one
/// Close button; Esc and ↩ close it. It never shows errors: failures go to the console log only.
final class LibraryRekordboxReportView: AmpXDrawingView {
    let closeButton: AmpXButton
    var onClose: (() -> Void)?

    private(set) var report: RekordboxSyncReport?
    private(set) var summaryLines: [String] = []
    /// Headings and paths of the scrollable list, in display order.
    private(set) var entryLines: [String] = []

    private let scrollbar: AmpXScrollbar
    private var scrollOffset: CGFloat = 0
    private static let lineHeight: CGFloat = 18
    private static let summaryTop: CGFloat = 12
    private static let footerHeight: CGFloat = 44

    override init(skin: any AmpXSkin) {
        self.closeButton = AmpXButton(skin: skin)
        self.scrollbar = AmpXScrollbar(skin: skin)
        super.init(skin: skin)
        self.closeButton.label = "CLOSE"
        self.closeButton.applyKeyLabelStyle()
        self.closeButton.action = { [weak self] in self?.onClose?() }
        self.scrollbar.fixedThumbLength = AmpXMetrics.playlistScrollbarThumbLength
        self.scrollbar.onScroll = { [weak self] offset in self?.scroll(to: offset) }
        addSubview(self.closeButton)
        addSubview(self.scrollbar)
        setAccessibilityRole(.group)
        setAccessibilityLabel("rekordbox report")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func summary(_ report: RekordboxSyncReport) -> [String] {
        let listed = report.matched + report.unmatched.count + report.ambiguous.count
        var lines = [
            report.fileName,
            "\(LibraryFormatting.grouped(report.matched)) of \(LibraryFormatting.grouped(listed)) tracks matched",
            "\(LibraryFormatting.grouped(report.updated)) updated",
        ]
        for (count, text) in [
            (report.unmatched.count, "not in any library folder"),
            (report.ambiguous.count, "ambiguous"),
            (report.ratingConflicts.count, "rating conflicts"),
            (report.noLongerInRekordbox.count, "no longer in rekordbox"),
        ] where count > 0 {
            lines.append("\(LibraryFormatting.grouped(count)) \(text)")
        }
        return lines
    }

    private static func entries(_ report: RekordboxSyncReport) -> [String] {
        let groups: [(String, [String])] = [
            ("NOT IN ANY LIBRARY FOLDER", report.unmatched),
            ("AMBIGUOUS", report.ambiguous.map(\.path)),
            ("RATING CONFLICTS", report.ratingConflicts.map(\.path)),
            ("NO LONGER IN REKORDBOX", report.noLongerInRekordbox),
        ]
        return groups.filter { !$0.1.isEmpty }.flatMap { [$0.0] + $0.1 }
    }

    func show(_ report: RekordboxSyncReport) {
        self.report = report
        self.summaryLines = Self.summary(report)
        self.entryLines = Self.entries(report)
        self.scrollOffset = 0
        needsLayout = true
        needsDisplay = true
    }

    /// Esc or ↩ close the report.
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 76 else { return false }
        self.onClose?()
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
        self.closeButton.frame = CGRect(x: bounds.width - 106, y: bounds.height - 36, width: 96, height: 28)
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
        let headings = Set(["NOT IN ANY LIBRARY FOLDER", "AMBIGUOUS", "RATING CONFLICTS", "NO LONGER IN REKORDBOX"])
        let first = max(0, Int(self.scrollOffset / Self.lineHeight))
        let last = min(self.entryLines.count, first + Int(viewport.height / Self.lineHeight) + 2)
        if first < last {
            for index in first ..< last {
                let line = self.entryLines[index]
                let y = viewport.minY + CGFloat(index) * Self.lineHeight - self.scrollOffset + 13
                let isHeading = headings.contains(line)
                let x: CGFloat = isHeading ? 12 : 24
                let text = LibraryTrackTableView.fittedText(line, width: viewport.width - x - 8, skin: skin)
                AmpXLabel(text: text, color: isHeading ? skin.text : skin.textDim, fontSize: 11, weight: isHeading ? .medium : .regular)
                    .draw(x: x, baseline: y, context: context, skin: skin)
            }
        }
        context.restoreGState()
    }
}

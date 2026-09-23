import AppKit
import UniformTypeIdentifiers

@MainActor
final class PlaylistRowsView: AmpXControlView {
    private static let dragThreshold: CGFloat = 6

    weak var manager: PlaylistManager?
    weak var keyboardAdapter: PlaylistKeyboardAdapter?

    var scrollOffset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var onScrollOffsetChange: ((CGFloat) -> Void)?

    private var pressedIndex: Int?
    private var draggedTrackIndex: Int?
    private var dragStartPoint: NSPoint?

    override init(skin: any AmpXSkin) {
        super.init(skin: skin)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Playlist tracks")
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func revealCursor() {
        guard let adapter = keyboardAdapter,
              let cursorID = adapter.selection.cursorID,
              let index = manager?.tracks.firstIndex(where: { $0.id == cursorID })
        else { return }

        let rowTop = CGFloat(index) * PlaylistRowLayout.rowHeight
        let rowBottom = rowTop + PlaylistRowLayout.rowHeight
        let viewport = bounds.height

        if rowTop < self.scrollOffset {
            self.onScrollOffsetChange?(rowTop)
        } else if rowBottom > self.scrollOffset + viewport {
            self.onScrollOffsetChange?(rowBottom - viewport)
        }
    }

    /// Display-only rows for deterministic reference presentation; `nil` draws the live playlist.
    var reference: PlaylistReferencePresentation? {
        didSet { needsDisplay = true }
    }

    private struct DisplayRow {
        var title: String
        var duration: String
        var isSelected: Bool
        var isCurrent: Bool
    }

    private func displayRows() -> [DisplayRow] {
        if let reference {
            return reference.rows.enumerated().map { index, row in
                DisplayRow(
                    title: row.title,
                    duration: row.duration,
                    isSelected: index == reference.selectedIndex,
                    isCurrent: index == reference.currentIndex
                )
            }
        }
        guard let manager else { return [] }
        let selection = self.keyboardAdapter?.selection ?? PlaylistSelectionModel()
        return manager.tracks.enumerated().map { index, track in
            DisplayRow(
                title: "\(track.artist) - \(track.title)",
                duration: AmpXTimeFormatting.format(track.duration),
                isSelected: selection.selectedIDs.contains(track.id),
                isCurrent: index == manager.currentIndex
            )
        }
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1
        context.setFillColor(skin.display.cgColor)
        context.fill(bounds)

        let rows = self.displayRows()
        let offset = self.reference == nil ? self.scrollOffset : 0
        let range = PlaylistRowLayout.visibleRange(offset: offset, viewport: bounds.height, count: rows.count)

        // Partially scrolled rows must not spill over the well lip (views don't clip by default on macOS 14+).
        context.saveGState()
        context.clip(to: bounds)
        for index in range {
            let item = rows[index]
            let row = PlaylistRowLayout.rowRect(index: index, width: bounds.width).offsetBy(dx: 0, dy: -offset)
            guard row.intersects(bounds) else { continue }

            if item.isSelected {
                context.setFillColor(skin.selection.cgColor)
                context.fill(row)
            }

            let color = PlaylistRowLayout.textColor(isSelected: item.isSelected, isCurrent: item.isCurrent, skin: skin)
            let text = PlaylistRowLayout.textLayout(number: index + 1, title: item.title, duration: item.duration, in: row, skin: skin)
            let size = AmpXMetrics.playlistRowFontSize
            AmpXLabel(text: "\(index + 1).", color: color, fontSize: size)
                .draw(x: text.numberRect.minX, baseline: text.baseline, context: context, skin: skin)
            context.saveGState()
            context.clip(to: text.titleRect)
            AmpXLabel(text: item.title, color: color, fontSize: size)
                .draw(x: text.titleRect.minX, baseline: text.baseline, context: context, skin: skin)
            context.restoreGState()
            AmpXLabel(text: item.duration, color: color, fontSize: size)
                .draw(x: text.durationRect.minX, baseline: text.baseline, context: context, skin: skin)
        }
        context.restoreGState()

        drawFocusRing(in: context, backingScale: backingScale)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        self.pressedIndex = self.trackIndex(at: point)
        self.dragStartPoint = point
        self.draggedTrackIndex = nil
    }

    override func cancelInteraction() {
        self.pressedIndex = nil
        self.draggedTrackIndex = nil
        self.dragStartPoint = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)

        if self.draggedTrackIndex == nil, let start = dragStartPoint, let pressedIndex {
            let distance = hypot(point.x - start.x, point.y - start.y)
            if distance >= Self.dragThreshold {
                self.draggedTrackIndex = pressedIndex
            }
        }

        guard let from = draggedTrackIndex,
              let to = trackIndex(at: point),
              from != to
        else { return }

        self.manager?.moveTrack(from: from, to: to)
        self.draggedTrackIndex = to
        pressedIndex = to
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        defer {
            pressedIndex = nil
            draggedTrackIndex = nil
            dragStartPoint = nil
        }

        guard self.draggedTrackIndex == nil,
              let index = pressedIndex,
              let manager,
              index >= 0,
              index < manager.tracks.count
        else { return }

        let track = manager.tracks[index]
        if event.clickCount >= 2 {
            manager.playTrack(at: index)
            return
        }

        self.applyClickSelection(to: track.id)
    }

    // MARK: - Row context menu

    /// Replaces the Trash confirmation alert; tests use it to avoid a modal.
    var confirmDiskRemoval: ((URL) -> Bool)?

    /// Right-clicking an unselected row selects it first, like Finder and Winamp.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard isEnabled, self.reference == nil else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = trackIndex(at: point) else { return nil }
        return self.contextMenu(forTrackAt: index)
    }

    func contextMenu(forTrackAt index: Int) -> NSMenu? {
        guard let manager, manager.tracks.indices.contains(index) else { return nil }
        let id = manager.tracks[index].id
        if let adapter = keyboardAdapter, !adapter.selection.selectedIDs.contains(id) {
            adapter.selection.selectOnly(id)
            adapter.onSelectionChanged?()
            needsDisplay = true
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = id
            menu.addItem(item)
        }
        add("Play", #selector(self.playFromMenu(_:)))
        add("Get Info", #selector(self.getInfoFromMenu(_:)))
        menu.addItem(.separator())
        add("Remove from Playlist", #selector(self.removeFromPlaylistFromMenu(_:)))
        add("Remove from Disk…", #selector(self.removeFromDiskFromMenu(_:)))
        return menu
    }

    private func menuTrackIndex(_ sender: NSMenuItem) -> Int? {
        guard let id = sender.representedObject as? UUID else { return nil }
        return self.manager?.tracks.firstIndex(where: { $0.id == id })
    }

    @objc private func playFromMenu(_ sender: NSMenuItem) {
        guard let index = menuTrackIndex(sender) else { return }
        self.manager?.playTrack(at: index)
    }

    @objc private func getInfoFromMenu(_ sender: NSMenuItem) {
        guard let index = menuTrackIndex(sender) else { return }
        self.manager?.presentTrackInfo(at: index)
    }

    /// Removes every selected row; the right-clicked row is always part of the selection.
    @objc private func removeFromPlaylistFromMenu(_ sender: NSMenuItem) {
        guard let index = menuTrackIndex(sender), let manager else { return }
        if let adapter = keyboardAdapter {
            adapter.removeSelectedTracks()
        } else {
            manager.removeTrack(at: index)
        }
        needsDisplay = true
    }

    @objc private func removeFromDiskFromMenu(_ sender: NSMenuItem) {
        guard let index = menuTrackIndex(sender), let manager else { return }
        guard manager.removeTrackFromDisk(at: index, confirm: self.confirmDiskRemoval) else { return }
        if let adapter = keyboardAdapter {
            adapter.selection.prune(toValidIDs: Set(manager.tracks.map(\.id)))
            adapter.onSelectionChanged?()
        }
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else {
            nextResponder?.scrollWheel(with: event)
            return
        }
        let next = AmpXControlMath.clampedScrollOffset(
            self.scrollOffset - event.deltaY * 8,
            contentLength: self.contentLength,
            viewportLength: bounds.height
        )
        guard next != self.scrollOffset else { return }
        self.scrollOffset = next
        self.onScrollOffsetChange?(next)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let manager else { return false }
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !urls.isEmpty
        else { return false }

        for url in urls {
            manager.importDroppedURL(url)
        }
        return true
    }

    override func isAccessibilityElement() -> Bool {
        false
    }

    override func accessibilityValue() -> Any? {
        guard let manager, let adapter = keyboardAdapter else { return nil }
        let tracks = manager.tracks
        let range = PlaylistRowLayout.visibleRange(
            offset: self.scrollOffset,
            viewport: bounds.height,
            count: tracks.count
        )
        let visible = range.map { index in
            let track = tracks[index]
            return "\(index + 1). \(track.artist) - \(track.title)"
        }
        let selected = tracks.enumerated().compactMap { index, track -> String? in
            guard adapter.selection.selectedIDs.contains(track.id) else { return nil }
            return "\(index + 1). \(track.artist) - \(track.title)"
        }
        return "Visible rows: \(visible.joined(separator: "; ")). Selected rows: \(selected.joined(separator: "; "))"
    }

    private var contentLength: CGFloat {
        CGFloat(self.manager?.tracks.count ?? 0) * PlaylistRowLayout.rowHeight
    }

    private func trackIndex(at point: NSPoint) -> Int? {
        guard let manager, !manager.tracks.isEmpty else { return nil }
        let contentY = point.y + self.scrollOffset
        let index = Int(contentY / PlaylistRowLayout.rowHeight)
        guard index >= 0, index < manager.tracks.count else { return nil }
        return index
    }

    private func applyClickSelection(to id: UUID) {
        guard let adapter = keyboardAdapter else { return }
        let flags = NSEvent.modifierFlags.intersection([.command, .shift])
        let ordered = self.manager?.tracks.map(\.id) ?? []
        if flags.contains(.shift) {
            adapter.selection.selectRange(to: id, orderedIDs: ordered)
        } else if flags.contains(.command) {
            adapter.selection.toggle(id)
        } else {
            adapter.selection.selectOnly(id)
        }
        self.keyboardAdapter?.onSelectionChanged?()
        needsDisplay = true
    }
}

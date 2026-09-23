import AppKit
import Combine
import CoreGraphics

/// Display-only Playlist values for deterministic reference captures. Never written to the playlist model.
struct PlaylistReferencePresentation: Equatable {
    struct Row: Equatable {
        var title: String
        var duration: String
    }

    var rows: [Row]
    var selectedIndex: Int?
    var currentIndex: Int?
    var elapsedTotalText: String
    var remainingText: String
}

final class PlaylistModuleContent: AmpXModuleContent {
    private let manager: PlaylistManager
    private let audioPlayer: AudioPlayer
    private let keyboardAdapter: PlaylistKeyboardAdapter
    let listOptionsMenu: PlaylistListOptionsMenu
    private let rowsView: PlaylistRowsView
    private let footerView: PlaylistFooterView
    private let scrollbar: AmpXScrollbar

    private var rowViewportHeight = AmpXMetrics.playlistRows.height
    private var cancellables = Set<AnyCancellable>()
    private var playlistIsActive = false

    /// When set, rows and footer readouts render these values instead of live playlist state.
    var referencePresentation: PlaylistReferencePresentation? {
        didSet {
            self.rowsView.reference = self.referencePresentation
            self.footerView.setReferenceReadouts(
                elapsedTotal: self.referencePresentation?.elapsedTotalText,
                remaining: self.referencePresentation?.remainingText
            )
        }
    }

    let resizeHandle: PlaylistResizeHandleView

    /// Receives handle drags; the host owns the preferred viewport height.
    var onResizeViewport: ((PlaylistResizeHandleView.Phase) -> Void)? {
        get { self.resizeHandle.onResize }
        set { self.resizeHandle.onResize = newValue }
    }

    var canScrollVertically: Bool {
        self.scrollbar.contentLength > self.scrollbar.viewportLength
    }

    init(
        skin: any AmpXSkin,
        manager: PlaylistManager,
        audioPlayer: AudioPlayer
    ) {
        self.manager = manager
        self.audioPlayer = audioPlayer
        self.keyboardAdapter = PlaylistKeyboardAdapter(manager: manager)
        self.listOptionsMenu = PlaylistListOptionsMenu(manager: manager, keyboardAdapter: self.keyboardAdapter)
        self.rowsView = PlaylistRowsView(skin: skin)
        self.footerView = PlaylistFooterView(
            skin: skin,
            manager: manager,
            audioPlayer: audioPlayer,
            keyboardAdapter: self.keyboardAdapter,
            listOptionsMenu: self.listOptionsMenu
        )
        self.scrollbar = AmpXScrollbar(skin: skin)
        self.resizeHandle = PlaylistResizeHandleView(skin: skin)
        super.init(skin: skin)
        self.configureControls()
        self.bindModels()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            if playlistIsActive {
                AmpXPlaylistKeyboard.unregister(keyboardAdapter)
            }
        }
    }

    override func setEffectivelyVisible(_ visible: Bool) {
        super.setEffectivelyVisible(visible)
        self.footerView.setEffectivelyVisible(visible)
        guard visible != self.playlistIsActive else { return }
        self.playlistIsActive = visible
        if visible {
            AmpXPlaylistKeyboard.register(self.keyboardAdapter)
        } else {
            AmpXPlaylistKeyboard.unregister(self.keyboardAdapter)
        }
    }

    func setRowViewportHeight(_ height: CGFloat) {
        self.rowViewportHeight = max(height, AmpXMetrics.minimumPlaylistViewportHeight)
        self.scrollbar.viewportLength = self.rowViewportHeight
        self.layoutControls()
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if self.canScrollVertically {
            self.scrollbar.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        self.layoutControls()
    }

    private func configureControls() {
        self.rowsView.manager = self.manager
        self.rowsView.keyboardAdapter = self.keyboardAdapter
        self.rowsView.onScrollOffsetChange = { [weak self] offset in
            self?.setScrollOffset(offset)
        }

        self.keyboardAdapter.onSelectionChanged = { [weak self] in
            self?.rowsView.needsDisplay = true
        }
        self.keyboardAdapter.onRevealCursor = { [weak self] in
            self?.rowsView.revealCursor()
        }

        self.scrollbar.fixedThumbLength = AmpXMetrics.playlistScrollbarThumbLength
        self.scrollbar.onScroll = { [weak self] offset in
            self?.setScrollOffset(offset)
        }

        addSubview(self.rowsView)
        addSubview(self.footerView)
        addSubview(self.scrollbar)
        // Last, so the bottom strip and grip win hit testing over the footer.
        addSubview(self.resizeHandle)
        self.updateScrollbarMetrics()
        self.layoutControls()
    }

    private func bindModels() {
        self.manager.$tracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in
                guard let self else { return }
                self.keyboardAdapter.selection.prune(toValidIDs: Set(tracks.map(\.id)))
                self.updateScrollbarMetrics()
                self.rowsView.needsDisplay = true
            }
            .store(in: &self.cancellables)

        self.manager.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                guard let self else { return }
                self.revealPlayingRow(index)
                self.rowsView.needsDisplay = true
            }
            .store(in: &self.cancellables)
    }

    private func setScrollOffset(_ offset: CGFloat) {
        self.scrollbar.offset = offset
        self.rowsView.scrollOffset = offset
    }

    /// Follows the playing track like Winamp: scrolls only when its row is not fully visible.
    private func revealPlayingRow(_ index: Int) {
        guard let offset = PlaylistRowLayout.revealOffset(
            forRow: index,
            offset: self.scrollbar.offset,
            viewport: self.rowViewportHeight,
            count: self.manager.tracks.count
        ) else { return }
        self.setScrollOffset(offset)
    }

    private func updateScrollbarMetrics() {
        self.scrollbar.contentLength = CGFloat(self.manager.tracks.count) * PlaylistRowLayout.rowHeight
        self.scrollbar.viewportLength = self.rowViewportHeight
        let clamped = AmpXControlMath.clampedScrollOffset(
            self.scrollbar.offset,
            contentLength: self.scrollbar.contentLength,
            viewportLength: self.scrollbar.viewportLength
        )
        if clamped != self.scrollbar.offset {
            self.setScrollOffset(clamped)
        }
    }

    var scrollOffset: CGFloat {
        self.scrollbar.offset
    }

    // MARK: - Layout

    struct Frames {
        var rows: CGRect
        var scrollbar: CGRect
        var footer: CGRect
    }

    /// Row area, scrollbar and footer for a viewport height and content width; the footer always follows the
    /// rows. Extra width stretches the row area and keeps the scrollbar on the right edge (spec Revision 9).
    static func layout(viewportHeight: CGFloat, width: CGFloat = AmpXMetrics.defaultPlaylistWidth) -> Frames {
        let contentWidth = max(AmpXMetrics.minimumPlaylistWidth, width)
        let rowsTrailingInset = AmpXMetrics.compositionWidth - AmpXMetrics.playlistRows.maxX
        let scrollbarTrailingInset = AmpXMetrics.compositionWidth - AmpXMetrics.playlistScrollbar.minX
        let rows = CGRect(
            x: AmpXMetrics.playlistRows.minX,
            y: AmpXMetrics.playlistRows.minY,
            width: contentWidth - rowsTrailingInset - AmpXMetrics.playlistRows.minX,
            height: viewportHeight
        )
        let scrollbarTop = AmpXMetrics.playlistRows.minY - AmpXMetrics.playlistScrollbar.minY
        let scrollbarShortfall = AmpXMetrics.playlistRows.height - AmpXMetrics.playlistScrollbar.height
        let scrollbar = CGRect(
            x: contentWidth - scrollbarTrailingInset,
            y: rows.minY - scrollbarTop,
            width: AmpXMetrics.playlistScrollbar.width,
            height: max(0, viewportHeight - scrollbarShortfall)
        )
        let footer = CGRect(
            x: 0,
            y: rows.maxY + AmpXMetrics.playlistFooterGap,
            width: contentWidth,
            height: AmpXMetrics.playlistFooterHeight
        )
        return Frames(rows: rows, scrollbar: scrollbar, footer: footer)
    }

    static func rowsWellRect(for rows: CGRect) -> CGRect {
        let outsets = AmpXMetrics.playlistRowsWellOutsets
        return CGRect(
            x: rows.minX - outsets.left,
            y: rows.minY - outsets.top,
            width: rows.width + outsets.left + outsets.right,
            height: rows.height + outsets.top + outsets.bottom
        )
    }

    private func layoutControls() {
        let width = max(AmpXMetrics.minimumPlaylistWidth, bounds.width)
        let frames = Self.layout(viewportHeight: self.rowViewportHeight, width: width)
        self.rowsView.frame = frames.rows
        self.scrollbar.frame = frames.scrollbar
        self.footerView.frame = frames.footer
        self.resizeHandle.frame = CGRect(x: 0, y: 0, width: width, height: frames.footer.maxY)
        needsDisplay = true
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1
        skin.displayWell(Self.rowsWellRect(for: self.rowsView.frame), in: context, backingScale: backingScale)
    }
}

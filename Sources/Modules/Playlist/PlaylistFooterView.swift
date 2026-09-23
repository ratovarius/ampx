import AppKit

@MainActor
final class PlaylistFooterView: AmpXDrawingView {
    private static let miniTransportIcons: [AmpXIcon] = [.previous, .play, .pause, .stop, .next]

    private let manager: PlaylistManager
    private let audioPlayer: AudioPlayer
    private let keyboardAdapter: PlaylistKeyboardAdapter
    let listOptionsMenu: PlaylistListOptionsMenu

    private var footerButtonsViews: [AmpXButton] = []
    private var miniTransportButtons: [AmpXButton] = []
    private let elapsedTotalReadout: PlaylistFooterTimeReadout
    private let remainingReadout: PlaylistFooterRemainingReadout

    init(
        skin: any AmpXSkin,
        manager: PlaylistManager,
        audioPlayer: AudioPlayer,
        keyboardAdapter: PlaylistKeyboardAdapter,
        listOptionsMenu: PlaylistListOptionsMenu? = nil
    ) {
        self.manager = manager
        self.audioPlayer = audioPlayer
        self.keyboardAdapter = keyboardAdapter
        self.listOptionsMenu = listOptionsMenu ?? PlaylistListOptionsMenu(manager: manager, keyboardAdapter: keyboardAdapter)
        self.elapsedTotalReadout = PlaylistFooterTimeReadout(skin: skin)
        self.remainingReadout = PlaylistFooterRemainingReadout(skin: skin)
        super.init(skin: skin)
        self.configureControls()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setEffectivelyVisible(_ visible: Bool) {
        self.elapsedTotalReadout.setEffectivelyVisible(visible)
        self.remainingReadout.setEffectivelyVisible(visible)
    }

    /// Display-only readout texts for deterministic reference presentation; `nil` shows live time.
    func setReferenceReadouts(elapsedTotal: String?, remaining: String?) {
        self.elapsedTotalReadout.referenceText = elapsedTotal
        self.remainingReadout.referenceText = remaining
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        self.layoutControls()
    }

    private func configureControls() {
        self.elapsedTotalReadout.audioPlayer = self.audioPlayer
        self.elapsedTotalReadout.playlistManager = self.manager
        self.remainingReadout.audioPlayer = self.audioPlayer

        for (label, _) in AmpXMetrics.playlistFooterButtons {
            let button = AmpXButton(skin: skin)
            button.label = label
            button.applyKeyLabelStyle()
            button.accessibilityTitle = label
            button.action = { [weak self, weak button] in
                guard let button else { return }
                self?.showMenu(for: label, button: button)
            }
            self.footerButtonsViews.append(button)
            addSubview(button)
        }

        for (index, icon) in Self.miniTransportIcons.enumerated() {
            let button = AmpXButton(skin: skin)
            button.icon = icon
            button.iconRect = AmpXMetrics.playlistFooterTransport[index].glyph
            button.accessibilityTitle = self.miniTransportLabel(for: icon)
            button.action = self.transportAction(for: icon)
            if icon == .play {
                button.iconColor = skin.green
                button.isActive = true
            }
            self.miniTransportButtons.append(button)
            addSubview(button)
        }

        addSubview(self.elapsedTotalReadout)
        addSubview(self.remainingReadout)
        self.layoutControls()
    }

    /// Extra width beyond the reference; the right group keeps its trailing anchor (spec Revision 9).
    private var rightAnchorOffset: CGFloat {
        max(0, bounds.width - AmpXMetrics.compositionWidth)
    }

    /// Left-anchored controls keep their reference x; the right group shifts with the trailing edge.
    private func anchored(_ rect: CGRect) -> CGRect {
        rect.minX >= AmpXMetrics.playlistFooterRightGroupMinX
            ? rect.offsetBy(dx: self.rightAnchorOffset, dy: 0)
            : rect
    }

    private func layoutControls() {
        for (index, item) in AmpXMetrics.playlistFooterButtons.enumerated() where index < self.footerButtonsViews.count {
            footerButtonsViews[index].frame = self.anchored(item.rect)
        }
        for (index, item) in AmpXMetrics.playlistFooterTransport.enumerated() where index < self.miniTransportButtons.count {
            miniTransportButtons[index].frame = self.anchored(item.frame)
        }
        self.elapsedTotalReadout.frame = self.anchored(AmpXMetrics.playlistFooterCounterWell)
        self.remainingReadout.frame = self.anchored(AmpXMetrics.playlistFooterRemainingWell)
    }

    private func showMenu(for label: String, button: AmpXButton) {
        let menu = NSMenu()
        switch label {
        case "ADD":
            menu.addItem(self.menuItem(title: "Add File…", action: #selector(PlaylistFooterMenuActions.addFile)))
            menu.addItem(self.menuItem(title: "Add Directory…", action: #selector(PlaylistFooterMenuActions.addDirectory)))
        case "REM":
            menu.addItem(self.menuItem(title: "Remove", action: #selector(PlaylistFooterMenuActions.removeSelected)))
            menu.addItem(self.menuItem(title: "Crop", action: #selector(PlaylistFooterMenuActions.cropSelected)))
            menu.addItem(self.menuItem(title: "Clear Playlist", action: #selector(PlaylistFooterMenuActions.clearPlaylist)))
        case "SEL":
            menu.addItem(self.menuItem(title: "Select All", action: #selector(PlaylistFooterMenuActions.selectAll)))
            menu.addItem(self.menuItem(title: "Select None", action: #selector(PlaylistFooterMenuActions.selectNone)))
            menu.addItem(self.menuItem(title: "Invert Selection", action: #selector(PlaylistFooterMenuActions.invertSelection)))
        case "MISC":
            menu.addItem(self.menuItem(title: "Sort by Title", action: #selector(PlaylistFooterMenuActions.sortByTitle)))
            menu.addItem(self.menuItem(title: "Sort by Filename", action: #selector(PlaylistFooterMenuActions.sortByFilename)))
            menu.addItem(self.menuItem(title: "Sort by Path", action: #selector(PlaylistFooterMenuActions.sortByPath)))
            menu.addItem(.separator())
            menu.addItem(self.menuItem(title: "Reverse", action: #selector(PlaylistFooterMenuActions.reverseTracks)))
            menu.addItem(self.menuItem(title: "Randomize", action: #selector(PlaylistFooterMenuActions.randomizeTracks)))
            menu.addItem(.separator())
            menu.addItem(self.menuItem(title: "File Info", action: #selector(PlaylistFooterMenuActions.fileInfo)))
        case "LIST OPTS":
            self.listOptionsMenu.show(relativeTo: button)
            return
        default:
            return
        }

        let actions = PlaylistFooterMenuActions(
            manager: manager,
            keyboardAdapter: keyboardAdapter
        )
        menu.items.forEach { $0.target = actions }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: "")
    }

    private func miniTransportLabel(for icon: AmpXIcon) -> String {
        switch icon {
        case .previous: "Previous"
        case .play: "Play"
        case .pause: "Pause"
        case .stop: "Stop"
        case .next: "Next"
        default: "Transport"
        }
    }

    private func transportAction(for icon: AmpXIcon) -> (() -> Void)? {
        switch icon {
        case .previous:
            { [weak manager] in manager?.previous() }
        case .play:
            { [weak audioPlayer] in audioPlayer?.playOrResume() }
        case .pause:
            { [weak audioPlayer] in audioPlayer?.pause() }
        case .stop:
            { [weak audioPlayer] in audioPlayer?.stop() }
        case .next:
            { [weak manager] in manager?.next() }
        default:
            nil
        }
    }
}

@MainActor
private final class PlaylistFooterMenuActions: NSObject {
    private let manager: PlaylistManager
    private let keyboardAdapter: PlaylistKeyboardAdapter

    init(manager: PlaylistManager, keyboardAdapter: PlaylistKeyboardAdapter) {
        self.manager = manager
        self.keyboardAdapter = keyboardAdapter
    }

    @objc func addFile() {
        self.manager.showFilePicker()
    }

    @objc func addDirectory() {
        self.manager.showFolderPicker()
    }

    @objc func removeSelected() {
        self.keyboardAdapter.removeSelectedTracks()
    }

    @objc func cropSelected() {
        self.keyboardAdapter.cropToSelection()
    }

    @objc func clearPlaylist() {
        PlaylistChromeActions.clearList(manager: self.manager, selection: &self.keyboardAdapter.selection)
        self.keyboardAdapter.onSelectionChanged?()
    }

    @objc func selectAll() {
        self.keyboardAdapter.selectAll()
    }

    @objc func selectNone() {
        PlaylistChromeActions.selectNone(selection: &self.keyboardAdapter.selection); self.keyboardAdapter.onSelectionChanged?()
    }

    @objc func invertSelection() {
        self.keyboardAdapter.invertSelection()
    }

    @objc func sortByTitle() {
        self.manager.sortTracks(by: .title)
    }

    @objc func sortByFilename() {
        self.manager.sortTracks(by: .fileName)
    }

    @objc func sortByPath() {
        self.manager.sortTracks(by: .path)
    }

    @objc func reverseTracks() {
        self.manager.reverseTracks()
    }

    @objc func randomizeTracks() {
        self.manager.randomizeTracks()
    }

    @objc func fileInfo() {
        PlaylistChromeActions.presentFileInfo(manager: self.manager, selection: self.keyboardAdapter.selection)
    }
}

@MainActor
private final class PlaylistFooterTimeReadout: AmpXContinuousView {
    weak var audioPlayer: AudioPlayer?
    weak var playlistManager: PlaylistManager?

    var referenceText: String? {
        didSet { needsDisplay = true }
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1
        skin.displayWell(bounds, in: context, backingScale: backingScale)

        let text: String
        if let referenceText {
            text = referenceText
        } else {
            guard let audioPlayer else { return }
            let total = self.playlistManager?.tracks.reduce(0) { $0 + $1.duration } ?? audioPlayer.duration
            let current = audioPlayer.playbackClock.currentTime
            text = "\(AmpXTimeFormatting.format(current))/\(AmpXTimeFormatting.format(total))"
        }
        let label = AmpXLabel(text: text, color: skin.green, fontSize: AmpXMetrics.playlistFooterReadoutFontSize)
        let ink = label.inkBounds(skin: skin)
        let origin = AmpXMetrics.playlistFooterCounterInk
        // Measured ink start, kept inside the well when the live text is wider than the reference.
        let x = min(origin.x - ink.minX, bounds.maxX - 3 - ink.maxX)
        label.draw(x: max(bounds.minX + 3, x), baseline: origin.y, context: context, skin: skin)
    }
}

@MainActor
private final class PlaylistFooterRemainingReadout: AmpXContinuousView {
    weak var audioPlayer: AudioPlayer?

    var referenceText: String? {
        didSet { needsDisplay = true }
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1
        skin.displayWell(bounds, in: context, backingScale: backingScale)

        let text: String
        if let referenceText {
            text = referenceText
        } else {
            guard let audioPlayer else { return }
            let remaining = max(0, audioPlayer.duration - audioPlayer.playbackClock.currentTime)
            text = AmpXTimeFormatting.format(-remaining, showNegative: true)
        }
        let label = AmpXLabel(text: text, color: skin.green, fontSize: AmpXMetrics.playlistFooterReadoutFontSize)
        let ink = label.inkBounds(skin: skin)
        label.draw(
            x: bounds.midX - ink.midX,
            baseline: AmpXMetrics.playlistFooterRemainingBaseline,
            context: context,
            skin: skin
        )
    }
}

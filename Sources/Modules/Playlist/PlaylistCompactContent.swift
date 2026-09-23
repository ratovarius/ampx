import AppKit
import Combine

final class PlaylistCompactContent: AmpXCompactModuleView {
    private(set) var summary = AmpXCompactPlaylistSummary(title: "NO TRACK", duration: "--:--")
    let listOptionsButton: AmpXButton
    private let manager: PlaylistManager
    private let audioPlayer: AudioPlayer
    private let listOptionsMenu: PlaylistListOptionsMenu
    private let readout: AmpXCompactPlaylistReadout
    private var cancellables = Set<AnyCancellable>()
    private var observedTrackID: UUID?
    private var decodedDurationTrackID: UUID?
    private var refreshPending = false

    /// Display-only capture fixture; never changes playlist or playback state.
    var referencePresentation: AmpXCompactPlaylistSummary? {
        didSet { self.updateReadout() }
    }

    override var protectedRects: [CGRect] {
        super.protectedRects + [
            AmpXCompactMetrics.playlistLayout(width: self.bounds.width).well,
            AmpXCompactMetrics.playlistLayout(width: self.bounds.width).listOptions,
        ]
    }

    init(skin: any AmpXSkin, manager: PlaylistManager, audioPlayer: AudioPlayer, listOptionsMenu: PlaylistListOptionsMenu) {
        self.listOptionsButton = AmpXButton(skin: skin)
        self.manager = manager
        self.audioPlayer = audioPlayer
        self.listOptionsMenu = listOptionsMenu
        self.readout = AmpXCompactPlaylistReadout(skin: skin)
        self.observedTrackID = audioPlayer.currentTrack?.id
        self.decodedDurationTrackID = audioPlayer.currentTrack?.id
        super.init(moduleID: .playlist, skin: skin)
        self.addSubview(self.readout)
        self.addSubview(self.listOptionsButton)
        self.listOptionsButton.icon = .menu
        self.listOptionsButton.iconColor = skin.faceInk
        self.listOptionsButton.confinesHitTestingToBounds = true
        self.listOptionsButton.focusRingInset = 1
        self.listOptionsButton.accessibilityTitle = "List Options"
        self.listOptionsButton.setAccessibilityElement(true)
        self.listOptionsButton.action = { [weak self] in
            guard let self else { return }
            self.listOptionsMenu.show(relativeTo: self.listOptionsButton)
        }
        self.bindModels()
        self.refreshSummary()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let layout = AmpXCompactMetrics.playlistLayout(width: self.bounds.width)
        self.readout.frame = layout.well
        self.listOptionsButton.frame = layout.listOptions
        self.listOptionsButton.iconRect = self.listOptionsButton.bounds.insetBy(dx: 4, dy: 4)
    }

    private func bindModels() {
        self.audioPlayer.$currentTrack.dropFirst().sink { [weak self] track in
            guard let self else { return }
            if self.observedTrackID != track?.id {
                self.decodedDurationTrackID = nil
                self.observedTrackID = track?.id
            }
            self.scheduleRefresh()
        }.store(in: &self.cancellables)
        // Do not deduplicate: two tracks can publish the same decoded duration.
        self.audioPlayer.$duration.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.decodedDurationTrackID = self.audioPlayer.currentTrack?.id
            self.scheduleRefresh()
        }.store(in: &self.cancellables)
        self.manager.$tracks.dropFirst().sink { [weak self] _ in
            self?.scheduleRefresh()
        }.store(in: &self.cancellables)
    }

    private func scheduleRefresh() {
        guard !self.refreshPending else { return }
        self.refreshPending = true
        // @Published emits before storage changes. Read the complete snapshot next turn.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.refreshSummary()
        }
    }

    private func refreshSummary() {
        self.summary = .make(
            loadedTrack: self.audioPlayer.currentTrack,
            tracks: self.manager.tracks,
            loadedDuration: self.decodedDurationTrackID == self.audioPlayer.currentTrack?.id
                ? self.audioPlayer.duration : 0
        )
        self.updateReadout()
    }

    private func updateReadout() {
        self.readout.summary = self.referencePresentation ?? self.summary
    }
}

private final class AmpXCompactPlaylistReadout: AmpXDrawingView {
    var summary = AmpXCompactPlaylistSummary(title: "NO TRACK", duration: "--:--") {
        didSet {
            self.setAccessibilityValue("\(self.summary.title), \(self.summary.duration)")
            self.needsDisplay = true
        }
    }

    override init(skin: any AmpXSkin) {
        super.init(skin: skin)
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.staticText)
        self.setAccessibilityLabel("Loaded track")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        self.skin.displayWell(self.bounds, in: context, backingScale: self.window?.backingScaleFactor ?? 1)
        let duration = AmpXLabel(text: self.summary.duration, color: self.skin.green, fontSize: 11, alignment: .right)
        let title = AmpXLabel(text: self.summary.title, color: self.skin.green, fontSize: 11)
        let columns = AmpXCompactPlaylistSummary.textRects(
            in: self.bounds.insetBy(dx: 5, dy: 2),
            durationWidth: duration.measuredSize(skin: self.skin).width
        )
        let font = title.font(skin: self.skin)
        let baseline = self.bounds.midY + (font.ascender + font.descender) / 2
        context.saveGState()
        context.clip(to: columns.title)
        title.draw(x: columns.title.minX, baseline: baseline, context: context, skin: self.skin)
        context.restoreGState()
        context.saveGState()
        context.clip(to: columns.duration)
        duration.draw(x: columns.duration.maxX, baseline: baseline, context: context, skin: self.skin)
        context.restoreGState()
    }
}

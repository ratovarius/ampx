import AppKit
import Combine

final class PlayerCompactContent: AmpXCompactModuleView {
    let spectrumWell: SpectrumWellView
    let timeDisplay: TimeDisplayView
    let transportButtons: [AmpXButton]
    private var cancellables = Set<AnyCancellable>()

    init(
        skin: any AmpXSkin,
        audioPlayer: AudioPlayer,
        playlistManager: PlaylistManager,
        presentationState: AmpXPlayerPresentationState,
        onToggleModule: @escaping (AmpXModuleID) -> Void
    ) {
        self.spectrumWell = SpectrumWellView(skin: skin)
        self.timeDisplay = TimeDisplayView(skin: skin, presentationState: presentationState)
        self.transportButtons = (0 ..< 5).map { _ in AmpXButton(skin: skin) }
        super.init(moduleID: .player, skin: skin)
        self.spectrumWell.geometry = .compact
        self.spectrumWell.onDoubleClick = { onToggleModule(.enthea) }
        self.timeDisplay.style = .compact
        self.timeDisplay.audioPlayer = audioPlayer
        self.addSubview(self.spectrumWell)
        self.addSubview(self.timeDisplay)
        let icons: [AmpXIcon] = [.previous, .play, .pause, .stop, .next]
        let names = ["Previous", "Play", "Pause", "Stop", "Next"]
        for index in self.transportButtons.indices {
            let button = self.transportButtons[index]
            button.setAccessibilityElement(true)
            button.icon = icons[index]
            button.accessibilityTitle = names[index]
            button.confinesHitTestingToBounds = true
            button.focusRingInset = 1
            button.action = AmpXTransportActions.make(for: icons[index], audioPlayer: audioPlayer, playlistManager: playlistManager)
            self.addSubview(button)
        }
        self.transportButtons[1].iconColor = skin.green
        presentationState.$visualizerSettings
            .removeDuplicates()
            .sink { [weak spectrumWell] settings in spectrumWell?.settings = settings }
            .store(in: &self.cancellables)
        self.spectrumWell.onSettingsChanged = { [weak presentationState] settings in
            presentationState?.setVisualizerSettings(settings)
        }
        audioPlayer.$isPlaying.removeDuplicates().sink { [weak self] playing in
            self?.transportButtons[1].isActive = playing
            self?.spectrumWell.playbackStateDidChange(isPlaying: playing)
        }.store(in: &self.cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var protectedRects: [CGRect] {
        let layout = AmpXCompactMetrics.playerLayout()
        return super.protectedRects + [layout.well] + layout.transport
    }

    override func layout() {
        super.layout()
        let layout = AmpXCompactMetrics.playerLayout()
        self.spectrumWell.frame = layout.visualizer
        self.timeDisplay.frame = layout.timer
        for index in self.transportButtons.indices {
            let button = self.transportButtons[index]
            button.frame = layout.transport[index]
            button.iconRect = layout.transportGlyphs[index].offsetBy(dx: -button.frame.minX, dy: -button.frame.minY)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        self.skin.displayWell(AmpXCompactMetrics.playerLayout().well, in: context, backingScale: self.window?.backingScaleFactor ?? 1)
        self.drawSeparator(AmpXCompactMetrics.source(796, 287, 6, 65), in: context)
    }

    override func focusableControls() -> [NSView] {
        ([self.spectrumWell, self.timeDisplay] + self.transportButtons
            + [self.minimizeButton, self.expandButton, self.closeButton].compactMap { $0 })
            .filter { !$0.isHidden && $0.acceptsFirstResponder }
            .sorted { $0.frame.minX < $1.frame.minX }
    }
}

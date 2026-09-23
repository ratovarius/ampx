import AppKit
import Combine
import CoreGraphics

/// Display-only values for deterministic reference captures. Never written to audio, playlist, or layout state.
struct PlayerReferencePresentation: Equatable {
    var trackTitle: String
    var timeText: String
    var bitrateText: String
    var sampleRateText: String
    var isMono: Bool
    var isStereo: Bool
    var isPlaying: Bool
    var spectrumLevels: [Float]
    var spectrumPeaks: [Float]
    var volume: Double
    var balance: Double
    var position: Double
    var equalizerOpen: Bool
    var playlistOpen: Bool
    var shuffleEnabled: Bool
    var repeatEnabled: Bool
}

final class PlayerModuleContent: AmpXModuleContent {
    private let audioPlayer: AudioPlayer
    private let playlistManager: PlaylistManager
    private let onToggleModule: (AmpXModuleID) -> Void
    var menuAction: ((AmpXButton) -> Void)?

    /// When set, rendering uses these values instead of live model state.
    var referencePresentation: PlayerReferencePresentation? {
        didSet { self.applyReferencePresentation() }
    }

    let presentationState: AmpXPlayerPresentationState

    /// Internal so the host and tests can park or wake the display-rate spectrum rendering.
    let spectrumWell: SpectrumWellView
    private let timeDisplay: TimeDisplayView
    /// Internal so tests can read the marquee's title and layout.
    let trackTitleView: TrackTitleMarqueeView
    private let volumeSlider: AmpXSlider
    private let balanceSlider: AmpXSlider
    private let positionBar: PositionBarView
    private let eqToggle: AmpXButton
    private let plToggle: AmpXButton
    private var transportButtons: [AmpXButton] = []
    private var cancellables = Set<AnyCancellable>()

    private var isPlaying = false
    private var trackTitle = ""
    private var bitrateText = "128"
    private var sampleRateText = "48"
    private var isMono = false
    private var isStereo = true

    init(
        skin: any AmpXSkin,
        audioPlayer: AudioPlayer,
        playlistManager: PlaylistManager,
        onToggleModule: @escaping (AmpXModuleID) -> Void,
        settingsStore: AmpXMiniVisualizerSettingsStore = AmpXMiniVisualizerSettingsStore(),
        presentationState: AmpXPlayerPresentationState? = nil
    ) {
        self.audioPlayer = audioPlayer
        self.playlistManager = playlistManager
        self.onToggleModule = onToggleModule
        let presentationState = presentationState ?? AmpXPlayerPresentationState(store: settingsStore)
        self.presentationState = presentationState
        self.spectrumWell = SpectrumWellView(skin: skin)
        self.timeDisplay = TimeDisplayView(skin: skin, presentationState: presentationState)
        self.trackTitleView = TrackTitleMarqueeView(skin: skin)
        self.volumeSlider = AmpXSlider(skin: skin)
        self.balanceSlider = AmpXSlider(skin: skin)
        self.positionBar = PositionBarView(skin: skin)
        self.eqToggle = AmpXButton(skin: skin)
        self.plToggle = AmpXButton(skin: skin)
        super.init(skin: skin)
        self.configureControls()
        self.bindModels()
        self.refreshStaticDisplayState()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateModuleToggleStates(eqOpen: Bool, plOpen: Bool) {
        self.eqToggle.isActive = eqOpen
        self.plToggle.isActive = plOpen
    }

    private func configureControls() {
        self.timeDisplay.audioPlayer = self.audioPlayer
        self.positionBar.audioPlayer = self.audioPlayer

        self.presentationState.$visualizerSettings
            .removeDuplicates()
            .sink { [weak spectrumWell] settings in spectrumWell?.settings = settings }
            .store(in: &self.cancellables)
        self.spectrumWell.onSettingsChanged = { [weak presentationState] settings in
            presentationState?.setVisualizerSettings(settings)
        }
        self.spectrumWell.onDoubleClick = { [weak self] in
            self?.onToggleModule(.enthea)
        }

        for slider in [self.volumeSlider, self.balanceSlider] {
            slider.range = 0 ... 1
            slider.thumbSize = AmpXMetrics.playerSliderThumbSize
            slider.thumbCrossOffset = AmpXMetrics.playerSliderThumbOffset
        }
        self.volumeSlider.artwork = .pill(.volume)
        self.volumeSlider.accessibilityTitle = "Volume"
        self.volumeSlider.onChange = { [weak audioPlayer] value in
            audioPlayer?.setVolume(Float(value))
        }

        self.balanceSlider.artwork = .pill(.balance)
        self.balanceSlider.accessibilityTitle = "Balance"
        self.balanceSlider.onChange = { [weak audioPlayer] value in
            audioPlayer?.setBalance(Float(value * 2 - 1))
        }

        self.positionBar.onChange = { [weak audioPlayer] seconds in
            audioPlayer?.seek(to: seconds)
        }

        self.configureToggle(
            self.eqToggle,
            label: "EQ",
            title: "Equalizer",
            indicator: AmpXMetrics.playerEQIndicator,
            labelInk: AmpXMetrics.playerEQLabelInk
        )
        self.eqToggle.action = { [weak self] in
            self?.onToggleModule(.equalizer)
        }
        self.configureToggle(
            self.plToggle,
            label: "PL",
            title: "Playlist",
            indicator: AmpXMetrics.playerPLIndicator,
            labelInk: AmpXMetrics.playerPLLabelInk
        )
        self.plToggle.action = { [weak self] in
            self?.onToggleModule(.playlist)
        }

        self.configureTransportButtons()

        for control in [
            self.spectrumWell,
            self.trackTitleView,
            self.timeDisplay,
            self.volumeSlider,
            self.balanceSlider,
            self.positionBar,
            self.eqToggle,
            self.plToggle,
        ] {
            addSubview(control)
        }
        self.layoutControls()
    }

    private func configureTransportButtons() {
        let transportIcons: [AmpXIcon?] = [
            .previous, .play, .pause, .stop, .next, .eject, nil, .repeat, .menu,
        ]
        for (index, frame) in AmpXMetrics.playerTransport.enumerated() {
            let button = AmpXButton(skin: skin)
            button.frame = frame
            if let glyph = AmpXMetrics.playerTransportGlyphs[index] {
                button.iconRect = glyph.offsetBy(dx: -frame.minX, dy: -frame.minY)
            }
            if index == 6 {
                button.label = "SHUFFLE"
                button.applyKeyLabelStyle()
                button.labelBaselineOrigin = self.labelOrigin("SHUFFLE", ink: AmpXMetrics.playerShuffleLabelInk)
                button.showsActiveIndicator = true
                button.indicatorRect = AmpXMetrics.playerShuffleIndicator
                button.accessibilityTitle = "Shuffle"
                button.action = { [weak self] in
                    guard let self else { return }
                    self.playlistManager.shuffleEnabled.toggle()
                }
            } else if index == 8 {
                button.style = .menu
                button.icon = .menu
                button.iconColor = skin.text
                button.accessibilityTitle = "Menu"
                button.action = { [weak self] in
                    guard let self, let button = self.transportButtons[safe: 8] else { return }
                    self.menuAction?(button)
                }
            } else if let icon = transportIcons[index] {
                button.icon = icon
                button.accessibilityTitle = self.transportLabel(for: icon)
                button.action = self.transportAction(for: icon)
            }
            self.transportButtons.append(button)
            addSubview(button)
        }
    }

    private func configureToggle(
        _ button: AmpXButton,
        label: String,
        title: String,
        indicator: CGRect,
        labelInk: CGPoint
    ) {
        button.label = label
        button.applyKeyLabelStyle()
        button.labelBaselineOrigin = self.labelOrigin(label, ink: labelInk)
        button.showsActiveIndicator = true
        button.indicatorRect = indicator
        button.accessibilityTitle = title
    }

    /// Label origin that puts the key label's ink left edge at `ink.x`, on the `ink.y` baseline.
    private func labelOrigin(_ text: String, ink: CGPoint) -> CGPoint {
        let bounds = AmpXLabel(text: text, color: skin.text, fontSize: AmpXMetrics.keyLabelFontSize, weight: AmpXButton.keyLabelWeight)
            .inkBounds(skin: skin)
        return CGPoint(x: ink.x - bounds.minX, y: ink.y)
    }

    private func bindModels() {
        self.audioPlayer.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                self?.isPlaying = isPlaying
                self?.transportButtons[safe: 1]?.isActive = isPlaying
                // A stop while already paused also clears retained waterfall history.
                self?.spectrumWell.playbackStateDidChange(isPlaying: isPlaying)
                self?.needsDisplay = true
            }
            .store(in: &self.cancellables)

        self.audioPlayer.$volume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                self?.volumeSlider.setValue(Double(volume), sendChange: false)
            }
            .store(in: &self.cancellables)

        self.audioPlayer.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] balance in
                self?.balanceSlider.setValue(Double((balance + 1) / 2), sendChange: false)
            }
            .store(in: &self.cancellables)

        self.audioPlayer.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPlaybackDisplay()
            }
            .store(in: &self.cancellables)

        self.audioPlayer.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshTrackTitle()
                self?.needsDisplay = true
            }
            .store(in: &self.cancellables)

        self.audioPlayer.$currentBitrate
            .combineLatest(self.audioPlayer.$currentSampleRate, self.audioPlayer.$currentChannels)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bitrate, sampleRate, channels in
                self?.bitrateText = "\(bitrate)"
                self?.sampleRateText = AudioFormatInfo.sampleRateDisplayKHz(sampleRate)
                self?.isMono = channels == 1
                self?.isStereo = channels >= 2
                self?.needsDisplay = true
            }
            .store(in: &self.cancellables)

        self.playlistManager.$currentIndex
            .combineLatest(self.playlistManager.$tracks)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refreshTrackTitle()
                self?.needsDisplay = true
            }
            .store(in: &self.cancellables)

        self.playlistManager.$shuffleEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.transportButtons[safe: 6]?.isActive = enabled
            }
            .store(in: &self.cancellables)

        self.playlistManager.$repeatEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.transportButtons[safe: 7]?.isActive = enabled
            }
            .store(in: &self.cancellables)
    }

    private func refreshStaticDisplayState() {
        self.volumeSlider.setValue(Double(self.audioPlayer.volume), sendChange: false)
        self.balanceSlider.setValue(Double((self.audioPlayer.balance + 1) / 2), sendChange: false)
        self.transportButtons[safe: 6]?.isActive = self.playlistManager.shuffleEnabled
        self.transportButtons[safe: 7]?.isActive = self.playlistManager.repeatEnabled
        self.isPlaying = self.audioPlayer.isPlaying
        self.transportButtons[safe: 1]?.isActive = self.isPlaying
        self.refreshTrackTitle()
        self.refreshPlaybackDisplay()
    }

    private func applyReferencePresentation() {
        let reference = self.referencePresentation
        self.timeDisplay.referenceText = reference?.timeText
        self.spectrumWell.reference = reference.map { SpectrumWellView.Reference(levels: $0.spectrumLevels, peaks: $0.spectrumPeaks) }
        self.volumeSlider.displayValueOverride = reference?.volume
        self.balanceSlider.displayValueOverride = reference?.balance
        self.positionBar.referenceFraction = reference?.position
        self.trackTitleView.title = reference?.trackTitle ?? self.trackTitle
        self.trackTitleView.isScrollingSuppressed = reference != nil
        self.eqToggle.displayActiveOverride = reference?.equalizerOpen
        self.plToggle.displayActiveOverride = reference?.playlistOpen
        self.transportButtons[safe: 1]?.displayActiveOverride = reference?.isPlaying
        self.transportButtons[safe: 6]?.displayActiveOverride = reference?.shuffleEnabled
        self.transportButtons[safe: 7]?.displayActiveOverride = reference?.repeatEnabled
        needsDisplay = true
    }

    private func refreshPlaybackDisplay() {
        self.positionBar.updatePlayback(
            current: self.audioPlayer.playbackClock.currentTime,
            duration: self.audioPlayer.duration
        )
    }

    private func refreshTrackTitle() {
        defer { trackTitleView.title = referencePresentation?.trackTitle ?? trackTitle }
        let displayTrack = self.playlistManager.currentTrack ?? self.audioPlayer.currentTrack
        guard let displayTrack else {
            self.trackTitle = ""
            return
        }

        let artist = displayTrack.artist.isEmpty ? "Unknown Artist" : displayTrack.artist
        let title = displayTrack.title.isEmpty ? "Unknown Title" : displayTrack.title
        var text = "\(artist) - \(title)"
        if self.playlistManager.currentIndex >= 0 {
            text = "\(self.playlistManager.currentIndex + 1). " + text
        }
        if displayTrack.duration > 0 {
            text += " (\(AmpXTimeFormatting.format(displayTrack.duration)))"
        }
        self.trackTitle = text
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        self.layoutControls()
    }

    // MARK: - Layout

    /// Measured `01:51` timer ink; digit cells are right-aligned to its trailing edge.
    static var timerFrame: CGRect {
        AmpXMetrics.playerTimer
    }

    /// Timer view extends left of the reference ink so remaining-time signs fit without stretching.
    static var timerViewFrame: CGRect {
        let timer = timerFrame
        let minX = playGlyphFrame.maxX + 3
        return CGRect(x: minX, y: timer.minY, width: timer.maxX - minX, height: timer.height)
    }

    /// Inside the track well's bevel; the marquee clips to it.
    static var trackTitleFrame: CGRect {
        AmpXMetrics.playerTrackWell.insetBy(dx: 2, dy: 2)
    }

    /// Left edge and baseline of the unscrolled title in content coordinates.
    /// Baseline from the parenthesis descent (0.2256 em) below the measured ink bottom.
    static var trackTitleOrigin: CGPoint {
        let ink = AmpXMetrics.playerTrackTextInk
        return CGPoint(x: ink.minX - 0.44, y: ink.maxY - TrackTitleMarqueeView.fontSize * 0.2256)
    }

    static var playGlyphFrame: CGRect {
        AmpXMetrics.playerPlayGlyph
    }

    private func layoutControls() {
        self.spectrumWell.frame = AmpXMetrics.playerDisplayWell
        // Whole-point frame so the layer never sits on a half pixel; the draw clips to the exact interior.
        let titleFrame = Self.trackTitleFrame.integral
        self.trackTitleView.frame = titleFrame
        self.trackTitleView.textClip = Self.trackTitleFrame.offsetBy(dx: -titleFrame.minX, dy: -titleFrame.minY)
        self.trackTitleView.textOrigin = CGPoint(
            x: Self.trackTitleOrigin.x - titleFrame.minX,
            y: Self.trackTitleOrigin.y - titleFrame.minY
        )
        self.timeDisplay.frame = Self.timerViewFrame
        self.volumeSlider.frame = AmpXMetrics.playerVolume
        self.volumeSlider.trackSize = CGSize(width: AmpXMetrics.playerVolume.width, height: AmpXMetrics.playerSliderTrackHeight)
        self.balanceSlider.frame = AmpXMetrics.playerBalance
        self.balanceSlider.trackSize = CGSize(width: AmpXMetrics.playerBalance.width, height: AmpXMetrics.playerSliderTrackHeight)
        self.positionBar.frame = AmpXMetrics.playerPosition
        self.eqToggle.frame = AmpXMetrics.playerEQToggle
        self.plToggle.frame = AmpXMetrics.playerPLToggle
        for (index, frame) in AmpXMetrics.playerTransport.enumerated() where index < self.transportButtons.count {
            transportButtons[index].frame = frame
        }
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let backingScale = window?.backingScaleFactor ?? 1

        skin.displayWell(AmpXMetrics.playerDisplayWell, in: context, backingScale: backingScale)
        skin.dotGrid(AmpXMetrics.playerDisplayInterior, in: context)
        skin.displayWell(AmpXMetrics.playerTrackWell, in: context, backingScale: backingScale)
        skin.displayWell(AmpXMetrics.playerBitrateWell, in: context, backingScale: backingScale)
        skin.displayWell(AmpXMetrics.playerSampleRateWell, in: context, backingScale: backingScale)

        if self.referencePresentation?.isPlaying ?? self.isPlaying {
            AmpXIcon.play.draw(in: Self.playGlyphFrame, context: context, skin: skin, color: skin.green)
        }

        // The track title is drawn by `trackTitleView`.
        self.drawMetadata(in: context)
    }

    private func drawMetadata(in context: CGContext) {
        let reference = self.referencePresentation
        let layout = Self.metadataLayout(
            bitrate: reference?.bitrateText ?? self.bitrateText,
            sampleRate: reference?.sampleRateText ?? self.sampleRateText
        )
        let mono = reference?.isMono ?? self.isMono
        let stereo = reference?.isStereo ?? self.isStereo
        for item in layout.items {
            let color: NSColor = switch item.role {
            case .mono: mono ? skin.green : skin.textDim
            case .stereo: stereo ? skin.green : skin.textDim
            case .kbps, .kHz: skin.text
            case .bitrate, .sampleRate: skin.green
            }
            AmpXLabel(text: item.text, color: color, fontSize: item.fontSize, weight: item.weight)
                .draw(x: item.rect.minX, baseline: item.baseline, context: context, skin: skin)
        }
    }
}

// MARK: - Transport actions and metadata layout

extension PlayerModuleContent {
    private func transportAction(for icon: AmpXIcon) -> (() -> Void)? {
        switch icon {
        case .previous, .play, .pause, .stop, .next:
            AmpXTransportActions.make(for: icon, audioPlayer: self.audioPlayer, playlistManager: self.playlistManager)
        case .eject:
            { [weak playlistManager] in playlistManager?.showFilePicker() }
        case .repeat:
            { [weak self] in
                self?.playlistManager.repeatEnabled.toggle()
            }
        default:
            nil
        }
    }

    private func transportLabel(for icon: AmpXIcon) -> String {
        switch icon {
        case .previous: "Previous"
        case .play: "Play"
        case .pause: "Pause"
        case .stop: "Stop"
        case .next: "Next"
        case .eject: "Eject"
        case .repeat: "Repeat"
        default: "Transport"
        }
    }

    /// Single-line metadata layout. Numeric readouts center in their wells and shrink only when a
    /// value is wider than the well; channel labels are right-aligned to the reference ink.
    static func metadataLayout(bitrate: String, sampleRate: String, skin: any AmpXSkin = ClassicModernSkin()) -> PlayerMetadataLayout {
        let baseline: CGFloat = 64.5

        func item(
            _ role: PlayerMetadataLayout.Role,
            _ text: String,
            size: CGFloat,
            weight: NSFont.Weight,
            x: (CGFloat) -> CGFloat
        ) -> PlayerMetadataLayout.Item {
            let label = AmpXLabel(text: text, color: skin.text, fontSize: size, weight: weight)
            let rect = label.lineRect(x: 0, baseline: baseline, skin: skin)
            return PlayerMetadataLayout.Item(
                role: role, text: text, fontSize: size, weight: weight, baseline: baseline,
                rect: rect.offsetBy(dx: x(rect.width), dy: 0)
            )
        }

        func numeric(_ role: PlayerMetadataLayout.Role, _ text: String, well: CGRect) -> PlayerMetadataLayout.Item {
            let preferred: CGFloat = 14.5
            let width = AmpXLabel(text: text, color: skin.text, fontSize: preferred, weight: .regular)
                .measuredSize(skin: skin).width
            let available = well.width - 3
            let size = width > available ? (preferred * available / width).rounded(.down) : preferred
            return item(role, text, size: size, weight: .regular) { well.midX - $0 / 2 }
        }

        return PlayerMetadataLayout(items: [
            numeric(.bitrate, bitrate, well: AmpXMetrics.playerBitrateWell),
            item(.kbps, "kbps", size: 12.5, weight: .regular) { _ in AmpXMetrics.playerKbpsInk.minX - 1.07 },
            numeric(.sampleRate, sampleRate, well: AmpXMetrics.playerSampleRateWell),
            item(.kHz, "kHz", size: 12.5, weight: .regular) { _ in AmpXMetrics.playerKHzInk.minX - 1.07 },
            item(.mono, "mono", size: 12.5, weight: .regular) { AmpXMetrics.playerMonoInk.maxX + 0.75 - $0 },
            item(.stereo, "stereo", size: 12.5, weight: .regular) { AmpXMetrics.playerStereoInk.maxX + 0.75 - $0 },
        ])
    }
}

struct PlayerMetadataLayout {
    enum Role {
        case bitrate, kbps, sampleRate, kHz, mono, stereo
    }

    struct Item {
        var role: Role
        var text: String
        var fontSize: CGFloat
        var weight: NSFont.Weight
        var baseline: CGFloat
        /// Typographic line box.
        var rect: CGRect
    }

    var items: [Item]

    func item(_ role: Role) -> Item? {
        self.items.first { $0.role == role }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

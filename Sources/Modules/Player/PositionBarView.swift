import AppKit

/// Playback position slider that pulls `PlaybackClock.currentTime` on display-link ticks.
final class PositionBarView: AmpXContinuousView {
    weak var audioPlayer: AudioPlayer?
    var onChange: ((TimeInterval) -> Void)?

    /// Display-only position for deterministic reference presentation; `nil` follows playback.
    var referenceFraction: Double? {
        didSet { self.slider.displayValueOverride = self.referenceFraction }
    }

    private let slider: AmpXSlider
    private var playbackDuration: TimeInterval = 0

    override init(skin: any AmpXSkin) {
        self.slider = AmpXSlider(skin: skin)
        super.init(skin: skin)
        self.slider.range = 0 ... 1
        self.slider.artwork = .seek
        self.slider.trackSize = AmpXMetrics.playerPositionTrackSize
        self.slider.thumbSize = AmpXMetrics.playerPositionThumbSize
        self.slider.thumbCrossOffset = AmpXMetrics.playerPositionThumbOffset
        self.slider.onChange = { [weak self] fraction in
            guard let self else { return }
            self.onChange?(self.playbackDuration * fraction)
        }
        addSubview(self.slider)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        self.slider.frame = bounds
    }

    override func layout() {
        super.layout()
        self.slider.frame = bounds
    }

    override func tick(at _: TimeInterval) {
        guard let audioPlayer else { return }
        self.updatePlayback(
            current: audioPlayer.playbackClock.currentTime,
            duration: audioPlayer.duration
        )
    }

    func updatePlayback(current: TimeInterval, duration: TimeInterval) {
        self.playbackDuration = duration
        let fraction = duration > 0 ? current / duration : 0
        self.slider.setValue(fraction, sendChange: false)
    }
}

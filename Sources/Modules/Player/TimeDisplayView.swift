import AppKit
import Combine
import CoreGraphics

/// Segment timer that pulls `PlaybackClock.currentTime` on display-link ticks.
final class TimeDisplayView: AmpXContinuousView {
    enum Style { case expanded, compact }
    var style: Style = .expanded {
        didSet {
            self.setAccessibilityElement(self.style == .compact)
            self.setAccessibilityRole(.button)
            self.setAccessibilityLabel("Playback time")
            self.needsDisplay = true
        }
    }

    @discardableResult
    func performKeyboardPress() -> Bool {
        self.presentationState.toggleTimeMode()
        return true
    }

    override func accessibilityPerformPress() -> Bool {
        self.performKeyboardPress()
    }

    override var acceptsFirstResponder: Bool {
        self.style == .compact && AmpXControlView.acceptsFocus(isEnabled: true, currentEventType: NSApp.currentEvent?.type)
    }

    weak var audioPlayer: AudioPlayer? {
        didSet { self.bindLoadedDuration() }
    }

    var showRemainingTime: Bool {
        get { self.presentationState.showRemainingTime }
        set { self.presentationState.setRemainingTime(newValue) }
    }

    /// Display-only text for deterministic reference presentation; `nil` shows the playback clock.
    var referenceText: String? {
        didSet { needsDisplay = true }
    }

    private let segmentDigits: AmpXSegmentDigits
    private let presentationState: AmpXPlayerPresentationState
    private var modeSubscription: AnyCancellable?
    private var blinkOff = false
    private var lastBlinkToggle: TimeInterval = 0
    private var decodedDurationTrackID: UUID?
    private var durationSubscriptions = Set<AnyCancellable>()

    private func bindLoadedDuration() {
        self.durationSubscriptions.removeAll()
        self.decodedDurationTrackID = self.audioPlayer?.currentTrack?.id
        guard let audioPlayer else { return }
        audioPlayer.$currentTrack.dropFirst().sink { [weak self] track in
            guard let self else { return }
            if track?.id != self.audioPlayer?.currentTrack?.id {
                self.decodedDurationTrackID = nil
            }
        }.store(in: &self.durationSubscriptions)
        audioPlayer.$duration.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.decodedDurationTrackID = self.audioPlayer?.currentTrack?.id
        }.store(in: &self.durationSubscriptions)
    }

    init(skin: any AmpXSkin, presentationState: AmpXPlayerPresentationState) {
        self.presentationState = presentationState
        self.segmentDigits = AmpXSegmentDigits(skin: skin)
        super.init(skin: skin)
        self.modeSubscription = presentationState.$showRemainingTime
            .removeDuplicates()
            .sink { [weak self] remaining in
                guard let self else { return }
                self.setNeedsDisplay(self.bounds)
                self.setAccessibilityValue(remaining ? "Remaining" : "Elapsed")
            }
    }

    override convenience init(skin: any AmpXSkin) {
        self.init(skin: skin, presentationState: AmpXPlayerPresentationState())
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tick(at time: TimeInterval) {
        self.updateBlinkState(at: time)
        setNeedsDisplay(bounds)
    }

    override func mouseDown(with _: NSEvent) {
        self.performKeyboardPress()
    }

    var compactText: String {
        self.referenceText ?? AmpXCompactTimeLayout.text(
            current: self.audioPlayer?.playbackClock.currentTime ?? 0,
            duration: self.decodedDurationTrackID == self.audioPlayer?.currentTrack?.id ? self.audioPlayer?.duration ?? 0 : 0,
            remaining: self.showRemainingTime,
            hasLoadedTrack: self.audioPlayer?.currentTrack != nil
        )
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if self.style == .compact {
            let text = self.compactText
            // Malformed/extreme reference strings cannot escape the timer's reserved cell.
            context.saveGState()
            context.clip(to: self.bounds)
            if self.referenceText != nil || !self.blinkOff {
                AmpXSegmentDigits(skin: self.skin, metrics: AmpXCompactTimeLayout.metrics(for: text, in: self.bounds))
                    .draw(text, in: self.bounds, context: context)
            }
            context.restoreGState()
            self.drawCompactFocusRing(in: context)
            return
        }
        if let referenceText {
            self.segmentDigits.draw(referenceText, in: bounds, context: context)
            return
        }
        guard let audioPlayer else { return }

        let duration = audioPlayer.duration
        let current = audioPlayer.playbackClock.currentTime
        let displayTime: TimeInterval = if self.showRemainingTime {
            duration > 0 ? -(duration - current) : 0
        } else {
            current
        }

        let text = AmpXTimeFormatting.format(displayTime, showNegative: self.showRemainingTime)
        if self.blinkOff {
            return
        }
        self.segmentDigits.draw(text, in: bounds, context: context)
    }

    private func updateBlinkState(at time: TimeInterval) {
        guard let audioPlayer else {
            self.blinkOff = false
            return
        }
        let paused = !audioPlayer.isPlaying && audioPlayer.duration > 0
        guard paused else {
            self.blinkOff = false
            return
        }
        if time - self.lastBlinkToggle >= 0.5 {
            self.blinkOff.toggle()
            self.lastBlinkToggle = time
        }
    }
}

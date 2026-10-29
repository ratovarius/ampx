import AppKit
import AVFoundation
import Combine
import Foundation
import MediaPlayer
import os
import QuartzCore
import UniformTypeIdentifiers

private let audioLogger = Logger(subsystem: "com.ampx.macos", category: "AudioEngine")

/// Holds the high-frequency playback position on its own observable so the ~10 Hz timer
/// updates only invalidate the small time/seek readouts that observe it — not every view
/// that observes `AudioPlayer`. Keeps the main thread (shared with the Metal visualizer's
/// `draw(in:)`) free of full player-chrome re-renders while a track plays.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var currentTime: TimeInterval = 0
}

@MainActor
class AudioPlayer: NSObject, ObservableObject {
    static let shared = AudioPlayer()

    @Published var isPlaying = false
    /// Playback position lives on a dedicated observable so its ~10 Hz updates re-render
    /// only the time readouts that observe `playbackClock`, not every view that observes
    /// the player. `currentTime` forwards to it so existing call sites are unchanged.
    let playbackClock = PlaybackClock()
    var currentTime: TimeInterval {
        get { self.playbackClock.currentTime }
        set { self.playbackClock.currentTime = newValue }
    }

    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.75
    @Published var balance: Float = 0
    @Published var currentTrack: Track?
    @Published var currentBitrate: Int = 128
    @Published var currentSampleRate: Double = 44100
    @Published var currentChannels: Int = 2
    @Published var eqBandValues: [Float] = Array(repeating: 0, count: EQSettings.bandCount)
    @Published var eqPreampValue: Float = 0
    @Published var eqEnabled: Bool = true
    @Published var eqAutoEnabled: Bool = false
    /// Bumps whenever the stored preset list changes, so EQ views re-read `eqPresets()`.
    @Published private(set) var eqPresetsRevision = 0
    @Published private(set) var engineIsRunning = false
    /// Volume normalization (ReplayGain). Off by default; opt in via `setVolumeNormalizationEnabled`.
    @Published var volumeNormalizationEnabled = false
    /// Prefer album gain over track gain when both ReplayGain tags are present.
    @Published var volumeNormalizationPreferAlbum = false
    /// ReplayGain tags read from the current track (empty when none / not yet read).
    @Published private(set) var currentReplayGain = ReplayGain()
    private var manualPreampValue: Float = 0
    /// ReplayGain per deck; the live deck's is also `currentReplayGain`.
    private var deckReplayGains = [ReplayGain(), ReplayGain()]
    /// MainActor mirror of the graph's live deck, switched once per Automix transition.
    private(set) var liveDeckIndex = 0
    /// The track loaded on each deck, so a late ReplayGain read never lands on a deck that moved on.
    private var deckTrackIDs: [UUID?] = [nil, nil]

    // MARK: Automix transitions (DJ mode spec Revision 2 § Clock, completion and transport)

    /// True from A's mix-out until the blend ends: Next then completes the transition instead of skipping.
    @Published private(set) var isBlending = false
    /// The live deck's tempo rate (1 = original); MainActor mirror for the Automix coordinator.
    private(set) var liveRate: Double = 1
    /// Fires once per transition, at the transport switch, with the incoming track.
    var onAutomixTrackChanged: (@MainActor @Sendable (Track) -> Void)?
    /// Fires when a seek, a load, a stop or a pause before the mix-out drops a prepared or armed transition.
    var onTransitionCancelled: (@MainActor @Sendable () -> Void)?
    /// The transition being prepared, armed or blended; `audioQueue` only.
    private nonisolated(unsafe) var transition: ActiveTransition?
    private nonisolated(unsafe) var blendTimer: DispatchSourceTimer?
    /// Set at the transport switch: the incoming deck's completion then behaves as the live deck's.
    private nonisolated(unsafe) var liveTransitionToken: UUID?
    private nonisolated(unsafe) var liveTransitionGeneration = 0
    /// Tests drive the blend with `testing_tick(outgoingFileTime:)` instead of the 10 ms ticker.
    nonisolated(unsafe) var testing_manualBlendTicks = false

    private nonisolated(unsafe) var audioGraph: AudioGraph?
    private nonisolated(unsafe) var audioEngine: AVAudioEngine?
    /// Per-deck playback state; read and written on `audioQueue` only.
    private nonisolated(unsafe) var deckStates = [DeckPlayback(), DeckPlayback()]

    /// The live deck's player node (the graph's `source`).
    private nonisolated var playerNode: AVAudioPlayerNode? {
        self.audioGraph?.source
    }

    private nonisolated var liveIndexOnQueue: Int {
        self.audioGraph?.liveDeckIndex ?? 0
    }

    private nonisolated var audioFile: AVAudioFile? {
        get { self.deckStates[self.liveIndexOnQueue].file }
        set { self.deckStates[self.liveIndexOnQueue].file = newValue }
    }

    /// The AmpX EQ stage of the processing graph (preamp + parametric EQ).
    private nonisolated(unsafe) var eqEffect: EQAudioEffect?
    private nonisolated(unsafe) var spectrumAnalyzer: FFTSpectrumAnalyzer?
    private nonisolated(unsafe) var spectrumTapInstalled = false
    /// Cached preamp linear gain for spectrum debug logging (tap already includes preamp in the audio path).
    private nonisolated(unsafe) var spectrumDebugPreampLinear: Float = 1.0

    /// Called when scheduled audio reaches the end and auto-advance is enabled.
    var onTrackFinished: (@MainActor @Sendable () -> Void)?
    /// Wired from the app shell for system media keys (`MPRemoteCommandCenter`).
    var onNextTrackRequested: (@MainActor @Sendable () -> Void)?
    var onPreviousTrackRequested: (@MainActor @Sendable () -> Void)?
    private let eqSettingsStore: EQSettingsStore
    private let remoteCommandController = RemoteCommandController()
    private var timer: Timer?
    private nonisolated(unsafe) var shouldAutoAdvance = true
    private let playStateLock = OSAllocatedUnfairLock()
    private nonisolated(unsafe) var isPlayingInternalStorage = false
    /// Audio-queue state: the node holds a paused position that `resume()` can continue.
    /// Distinguishes paused from stopped so Pause can toggle back to playing.
    private nonisolated(unsafe) var isPausedInternal = false
    /// Written only on `audioQueue`; lock-guarded so the MainActor half of track completion
    /// can re-check it before committing UI state.
    private nonisolated(unsafe) var playbackGenerationStorage = 0
    private nonisolated(unsafe) var loadGeneration = 0
    /// Absolute file time at the start of the live deck's scheduled player segment.
    /// `AVAudioPlayerNode.playerTime.sampleTime` is relative to that segment, so UI
    /// position is `playbackSegmentStartTime + sampleTime/sampleRate`.
    private nonisolated var playbackSegmentStartTime: TimeInterval {
        get { self.deckStates[self.liveIndexOnQueue].segmentStart }
        set { self.deckStates[self.liveIndexOnQueue].segmentStart = newValue }
    }

    private let audioQueue = DispatchQueue(label: "com.ampx.audio", qos: .userInteractive)

    private nonisolated var playbackGeneration: Int {
        get {
            self.playStateLock.lock()
            defer { self.playStateLock.unlock() }
            return self.playbackGenerationStorage
        }
        set {
            self.playStateLock.lock()
            self.playbackGenerationStorage = newValue
            self.playStateLock.unlock()
        }
    }

    private nonisolated var isPlayingInternal: Bool {
        get {
            self.playStateLock.lock()
            defer { self.playStateLock.unlock() }
            return self.isPlayingInternalStorage
        }
        set {
            self.playStateLock.lock()
            self.isPlayingInternalStorage = newValue
            self.playStateLock.unlock()
        }
    }

    private nonisolated func runOnMainActor(_ action: @escaping @MainActor @Sendable () -> Void) {
        Task { @MainActor in
            action()
        }
    }

    private nonisolated func runOnMainActor(weak player: AudioPlayer?, _ action: @escaping @MainActor @Sendable (AudioPlayer) -> Void) {
        Task { @MainActor in
            guard let player else { return }
            action(player)
        }
    }

    private nonisolated func startEngineIfNeeded(_ engine: AVAudioEngine) -> Bool {
        if engine.isRunning {
            return true
        }
        do {
            try engine.start()
            return true
        } catch {
            audioLogger.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private nonisolated func publishEngineRunningState(_ isRunning: Bool, on player: AudioPlayer) {
        player.runOnMainActor(weak: player) { mainPlayer in
            mainPlayer.engineIsRunning = isRunning
        }
    }

    override init() {
        self.installRemoteCommands = true
        self.eqSettingsStore = EQSettingsStore()
        super.init()
        self.setupAudioEngine()
        self.restoreEQSettings()
        self.setupRemoteCommands()
    }

    init(installRemoteCommands: Bool, eqSettingsStore: EQSettingsStore = EQSettingsStore()) {
        self.installRemoteCommands = installRemoteCommands
        self.eqSettingsStore = eqSettingsStore
        super.init()
        self.setupAudioEngine()
        self.restoreEQSettings()
        if installRemoteCommands {
            self.setupRemoteCommands()
        }
    }

    private let installRemoteCommands: Bool

    private func setupAudioEngine() {
        var engineStarted = false
        self.audioQueue.sync {
            // The processing pipeline is declared as an ordered effect chain rather than
            // hand-wired here, so future DSP modules are inserted via `AudioGraph`, not by
            // editing this method. Today the chain is a single stage: the AmpX EQ, fed by
            // the two Automix decks (only the live one plays outside a transition).
            let eqEffect = EQAudioEffect()
            let graph = AudioGraph.twoDeck()
            graph.build(effects: [eqEffect])

            self.audioGraph = graph
            self.eqEffect = eqEffect
            self.audioEngine = graph.engine

            engineStarted = self.startEngineIfNeeded(graph.engine)

            self.installSpectrumTapIfNeeded()
        }
        self.engineIsRunning = engineStarted
        self.applyPlayerVolume()
    }

    private func installSpectrumTapIfNeeded() {
        guard !self.spectrumTapInstalled, let graph = self.audioGraph else { return }

        let analyzer = FFTSpectrumAnalyzer(bandCount: AudioFeatures.spectrumBandCount)
        analyzer.onSpectrumFrames = { [weak self] frames, batchDuration in
            guard let self else { return }
            AudioFeatureBus.shared.publishSpectrumFrames(
                frames,
                arrivalTime: CACurrentMediaTime(),
                batchDuration: batchDuration,
                isPlaying: self.isPlayingInternal
            )
        }
        analyzer.onRawBins = { bins, sampleRate in
            AudioFeatureBus.shared.publishRawBins(bins, sampleRate: sampleRate)
        }
        analyzer.onAnalysisUpdate = { [weak self] bands, _, _ in
            guard let self else { return }
            // Build the diagnostic context lazily: the probe throttles to ~1 Hz, so the
            // string and its log10 only run when it actually emits, not on every callback.
            SpectrumAnalyzerDebugProbe.log(
                stage: "publish",
                bands: bands,
                context: String(format: "preamp=%.1fdB tap=effectChain", 20 * log10(max(self.spectrumDebugPreampLinear, 0.000_01)))
            )
        }
        analyzer.installTap(on: graph.tapPoint)
        self.spectrumAnalyzer = analyzer
        self.spectrumTapInstalled = true
    }

    private func restoreEQSettings() {
        let settings = self.eqSettingsStore.loadSettings()
        self.eqBandValues = settings.bandGainsDB.map { $0 / 12 }
        self.manualPreampValue = settings.preampGainDB / 12
        self.eqPreampValue = self.manualPreampValue
        self.eqEnabled = settings.eqEnabled
        self.eqAutoEnabled = settings.autoEnabled
        self.audioQueue.async { [weak self] in
            self?.applyEQSettings(settings)
        }
        if self.eqAutoEnabled {
            self.applyAutoPreampCompensation()
        }
    }

    private func persistEQSettings() {
        let settings = self.currentEQSettings()
        self.eqSettingsStore.saveSettings(settings)
    }

    private func currentEQSettings() -> EQSettings {
        EQSettings(
            bandGainsDB: self.eqBandValues.map { $0 * 12 },
            preampGainDB: self.manualPreampValue * 12,
            eqEnabled: self.eqEnabled,
            autoEnabled: self.eqAutoEnabled
        )
    }

    private nonisolated func applyEQSettings(_ settings: EQSettings) {
        guard let eqEffect = self.eqEffect else { return }
        // Bit-perfect passthrough (bypass + unity preamp when flat/disabled) lives in the
        // EQ effect so the policy is testable without an engine; cache the applied gain
        // for the spectrum-debug context string.
        self.spectrumDebugPreampLinear = eqEffect.apply(settings)
    }

    private func setupRemoteCommands() {
        self.remoteCommandController.setHandlers(RemoteCommandController.Handlers(
            play: { [weak self] in self?.playOrResume() },
            pause: { [weak self] in
                guard let self, self.isPlaying else { return }
                self.pause()
            },
            toggle: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.onNextTrackRequested?() },
            previous: { [weak self] in self?.onPreviousTrackRequested?() }
        ))
        self.remoteCommandController.installCommandTargets()
    }

    func loadTrack(_ track: Track, completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        let generation = self.loadGeneration + 1
        self.loadGeneration = generation
        self.resetMainActorStateForNewTrack(track)

        self.audioQueue.async { [weak self] in
            guard let self else {
                Task { @MainActor in completion?(false) }
                return
            }

            guard generation == self.loadGeneration else {
                self.deliverSupersededLoadCompletion(completion)
                return
            }

            self.isPlayingInternal = false
            self.isPausedInternal = false
            self.shouldAutoAdvance = false
            self.audioFile = nil
            self.playbackGeneration += 1
            self.playbackSegmentStartTime = 0

            self.cancelTransitionOnQueue(notify: true)
            self.preparePlayerNodeForNewTrack()

            guard let url = track.url else {
                self.runOnMainActor(weak: self) { player in
                    guard generation == player.loadGeneration else {
                        completion?(false)
                        return
                    }
                    player.clearFailedLoadState()
                    completion?(false)
                }
                return
            }

            do {
                let newFile = try AVAudioFile(forReading: url)
                guard generation == self.loadGeneration else {
                    self.deliverSupersededLoadCompletion(completion)
                    return
                }

                let newDuration = Double(newFile.length) / newFile.fileFormat.sampleRate
                let formatDetails = AudioFormatInfo.read(from: url, duration: newDuration)
                let sampleRate = formatDetails?.sampleRateHz ?? newFile.fileFormat.sampleRate
                let channels = formatDetails?.channelCount ?? Int(newFile.fileFormat.channelCount)
                let bitrate = formatDetails?.bitrateKbps ?? 128

                self.audioFile = newFile

                // ReplayGain metadata I/O must not block the serial audio queue.
                Task { [weak self] in
                    let replayGain = await ReplayGainReader.read(from: url)
                    guard let self else { return }
                    self.audioQueue.async { [weak self] in
                        guard let self, generation == self.loadGeneration else { return }
                        self.runOnMainActor(weak: self) { player in
                            guard generation == player.loadGeneration else { return }
                            player.currentReplayGain = replayGain
                            player.deckReplayGains[player.liveDeckIndex] = replayGain
                            if player.volumeNormalizationEnabled {
                                player.applyPlayerVolume()
                            }
                        }
                    }
                }

                self.runOnMainActor(weak: self) { player in
                    guard generation == player.loadGeneration else {
                        completion?(false)
                        return
                    }
                    player.duration = newDuration
                    player.currentSampleRate = sampleRate
                    player.currentChannels = channels
                    player.currentBitrate = bitrate
                    player.updateNowPlayingInfo()
                    if player.eqAutoEnabled {
                        player.applyAutoPreampCompensation()
                    }
                    completion?(true)
                }
            } catch {
                guard generation == self.loadGeneration else {
                    self.deliverSupersededLoadCompletion(completion)
                    return
                }
                self.audioFile = nil
                self.runOnMainActor(weak: self) { player in
                    guard generation == player.loadGeneration else {
                        completion?(false)
                        return
                    }
                    player.clearFailedLoadState()
                    completion?(false)
                }
            }
        }
    }

    private func resetMainActorStateForNewTrack(_ track: Track) {
        self.stopTimer()
        self.isPlaying = false
        self.currentTime = 0
        self.currentTrack = track
        // A loaded track always starts at its original tempo, on the live deck alone.
        self.liveRate = 1
        self.deckTrackIDs = [nil, nil]
        self.deckTrackIDs[self.liveDeckIndex] = track.id
        self.deckReplayGains[1 - self.liveDeckIndex] = ReplayGain()
    }

    private func clearFailedLoadState() {
        self.currentTrack = nil
        self.duration = 0
        self.currentTime = 0
        self.isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private nonisolated func deliverSupersededLoadCompletion(_ completion: (@MainActor @Sendable (Bool) -> Void)?) {
        guard let completion else { return }
        Task { @MainActor in
            completion(false)
        }
    }

    /// Stops both decks and returns them to rate 1, no cut and full fade, so a loaded track
    /// always starts at its original tempo. The idle deck's state is cleared too.
    private nonisolated func preparePlayerNodeForNewTrack() {
        // Invalidate analysis only after stopping/resetting the old source. Opening
        // the new epoch on the main actor beforehand could stamp old PCM as new.
        defer { self.spectrumAnalyzer?.resetMiniAnalysis() }

        for deck in self.audioGraph?.decks ?? [] {
            deck.player.stop()
            deck.player.reset()
            deck.reset()
        }
        self.deckStates[1 - self.liveIndexOnQueue] = DeckPlayback()
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let info = NowPlayingInfo(
            title: track.title,
            artist: track.artist,
            duration: self.duration,
            elapsedTime: self.currentTime,
            isPlaying: self.isPlaying
        )
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info.dictionary
    }

    func play() {
        self.testing_lastTransportAction = .play
        let playerGain = self.playerGain(deck: self.liveDeckIndex)
        let mixerGain = VolumeModel.taper(self.volume)
        let balance = self.balance
        self.audioQueue.async { [weak self] in
            guard let self,
                  let player = self.playerNode,
                  let file = self.audioFile,
                  let engine = self.audioEngine
            else {
                return
            }

            if self.isPlayingInternal {
                return
            }

            guard self.startEngineIfNeeded(engine) else {
                self.publishEngineRunningState(false, on: self)
                return
            }
            self.publishEngineRunningState(true, on: self)

            // Stopping the node fires the completion of any segment still scheduled (e.g. by
            // a seek while stopped); the new generation makes that completion a no-op.
            self.playbackGeneration += 1
            player.stop()
            player.reset()

            self.shouldAutoAdvance = true
            self.playbackSegmentStartTime = 0
            let generation = self.playbackGeneration

            // `.dataPlayedBack` fires once the last frame has left the output device, so
            // completion handling can stop the node without clipping the tail. The default
            // `.dataConsumed` fires as soon as the file has been read into the render pipeline.
            player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.handleTrackCompletion(generation: generation)
            }

            player.volume = playerGain
            engine.mainMixerNode.outputVolume = mixerGain
            player.pan = balance
            player.play()
            self.isPlayingInternal = true
            self.isPausedInternal = false

            self.runOnMainActor(weak: self) { player in
                player.isPlaying = true
                player.currentTime = 0
                player.startTimer()
                player.updateNowPlayingInfo()
            }
        }
    }

    /// Pauses playback; pressing Pause again while paused resumes (Winamp behavior).
    /// Does nothing while stopped.
    func pause() {
        self.testing_lastTransportAction = .pause
        self.audioQueue.async { [weak self] in
            guard let self else { return }
            if self.isPausedInternal {
                self.resumeOnAudioQueue()
                return
            }
            guard self.isPlayingInternal else { return }
            self.playerNode?.pause()
            self.pauseTransitionOnQueue()
            self.isPlayingInternal = false
            self.isPausedInternal = true

            self.runOnMainActor(weak: self) { player in
                player.isPlaying = false
                player.stopTimer()
                player.updateNowPlayingInfo()
            }
        }
    }

    func resume() {
        self.testing_lastTransportAction = .resume
        self.audioQueue.async { [weak self] in
            self?.resumeOnAudioQueue()
        }
    }

    private nonisolated func resumeOnAudioQueue() {
        guard let player = self.playerNode,
              let engine = self.audioEngine,
              !self.isPlayingInternal else { return }

        guard self.startEngineIfNeeded(engine) else {
            self.publishEngineRunningState(false, on: self)
            return
        }
        self.publishEngineRunningState(true, on: self)

        // A seek while paused/stopped disarms auto-advance; playing again re-arms it.
        self.shouldAutoAdvance = true
        player.play()
        if let transition = self.transition, transition.blending {
            self.audioGraph?.idleDeck?.player.play()
        }
        self.isPlayingInternal = true
        self.isPausedInternal = false

        self.runOnMainActor(weak: self) { player in
            player.isPlaying = true
            player.startTimer()
            player.updateNowPlayingInfo()
        }
    }

    func stop() {
        self.audioQueue.async { [weak self] in
            guard let self else { return }
            self.cancelTransitionOnQueue(notify: true)
            self.shouldAutoAdvance = false
            self.playbackGeneration += 1
            self.playbackSegmentStartTime = 0
            self.playerNode?.stop()
            self.spectrumAnalyzer?.resetMiniAnalysis()
            self.isPlayingInternal = false
            self.isPausedInternal = false

            self.runOnMainActor(weak: self) { player in
                player.isPlaying = false
                player.currentTime = 0
                player.stopTimer()
                player.updateNowPlayingInfo()
            }
        }
    }

    func togglePlayPause() {
        if self.isPlaying {
            self.pause()
        } else {
            self.playOrResume()
        }
    }

    /// Starts playback from the beginning, or resumes from the current position when paused.
    func playOrResume() {
        if self.isPlaying {
            return
        }
        if self.currentTime > 0, self.currentTrack != nil {
            self.resume()
        } else {
            self.play()
        }
    }

    /// Winamp Play (X): restarts a playing track, resumes a paused one, starts a stopped one.
    func playOrRestart() {
        if self.isPlaying {
            self.seek(to: 0)
        } else {
            self.playOrResume()
        }
    }

    func seek(to time: TimeInterval) {
        self.audioQueue.async { [weak self] in
            guard let self,
                  let file = self.audioFile,
                  let player = self.playerNode else { return }

            // A seek aborts any transition and applies to the live deck.
            self.cancelTransitionOnQueue(notify: true)
            let wasPlaying = self.isPlayingInternal
            self.shouldAutoAdvance = false
            self.playbackGeneration += 1
            player.stop()
            player.reset()
            self.isPlayingInternal = false
            self.spectrumAnalyzer?.resetMiniAnalysis()

            let sampleRate = file.fileFormat.sampleRate
            let durationSeconds = sampleRate > 0 ? Double(file.length) / sampleRate : 0
            let clampedTime = max(0, min(time, max(durationSeconds - 0.001, 0)))
            var startFrame = AVAudioFramePosition(clampedTime * sampleRate)
            if file.length > 0 {
                startFrame = min(startFrame, file.length - 1)
            }
            guard startFrame >= 0, startFrame < file.length else {
                self.runOnMainActor(weak: self) { player in
                    player.isPlaying = false
                    player.stopTimer()
                    player.updateNowPlayingInfo()
                }
                return
            }

            let generation = self.playbackGeneration
            self.playbackSegmentStartTime = clampedTime

            player.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: AVAudioFrameCount(file.length - startFrame),
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                self?.handleTrackCompletion(generation: generation)
            }

            if wasPlaying {
                self.shouldAutoAdvance = true
                player.play()
                self.isPlayingInternal = true
                self.isPausedInternal = false
            }

            self.runOnMainActor(weak: self) { player in
                player.currentTime = clampedTime
                player.isPlaying = wasPlaying
                if wasPlaying {
                    player.startTimer()
                } else {
                    player.stopTimer()
                }
                player.updateNowPlayingInfo()
            }
        }
    }

    func setVolume(_ newVolume: Float) {
        let clamped = max(0, min(1, newVolume))
        self.volume = clamped
        self.applyPlayerVolume()
    }

    /// Applies each deck's ReplayGain on its own player node (two gain stages: the Automix
    /// fade envelope lives on the deck's mixer) and the tapered fader on the main mixer,
    /// so the analysis tap (post-EQ) does not see the listening volume.
    private func applyPlayerVolume() {
        let playerGains = self.deckReplayGains.indices.map { self.playerGain(deck: $0) }
        let mixerGain = VolumeModel.taper(self.volume)
        self.audioQueue.async { [weak self] in
            guard let self else { return }
            for (deck, gain) in zip(self.audioGraph?.decks ?? [], playerGains) {
                deck.player.volume = gain
            }
            self.audioEngine?.mainMixerNode.outputVolume = mixerGain
        }
    }

    /// Linear normalization gain for a deck's player node (1.0 when normalization is off).
    private func playerGain(deck: Int) -> Float {
        VolumeModel.playerNormalizationGain(
            normalizationEnabled: self.volumeNormalizationEnabled,
            normalizationGain: self.deckReplayGains[deck].normalizationGain(preferAlbum: self.volumeNormalizationPreferAlbum)
        )
    }

    func setBalance(_ newBalance: Float) {
        let clamped = max(-1, min(1, newBalance))
        self.balance = clamped
        self.audioQueue.async { [weak self] in
            for deck in self?.audioGraph?.decks ?? [] {
                deck.player.pan = clamped
            }
        }
    }

    /// Enables/disables ReplayGain volume normalization. Off by default.
    func setVolumeNormalizationEnabled(_ enabled: Bool) {
        self.volumeNormalizationEnabled = enabled
        self.applyPlayerVolume()
    }

    /// Chooses album vs. track ReplayGain when both are present.
    func setVolumeNormalizationPreferAlbum(_ preferAlbum: Bool) {
        self.volumeNormalizationPreferAlbum = preferAlbum
        if self.volumeNormalizationEnabled {
            self.applyPlayerVolume()
        }
    }

    func setEQBand(_ band: Int, gain: Float) {
        guard band >= 0, band < self.eqBandValues.count else { return }
        self.eqBandValues[band] = gain / 12
        self.persistEQSettings()
        if self.eqAutoEnabled {
            // AUTO recomputes preamp; bands are never effectively flat here so apply directly.
            self.audioQueue.async { [weak self] in
                self?.eqEffect?.setBandGain(band, decibels: gain)
            }
            self.applyAutoPreampCompensation()
            return
        }
        // Re-apply the whole EQ so bit-perfect passthrough engages when the user returns to flat.
        let settings = self.currentEQSettings()
        self.audioQueue.async { [weak self] in
            self?.applyEQSettings(settings)
        }
    }

    func setEQPreamp(_ normalizedValue: Float) {
        self.manualPreampValue = normalizedValue
        self.eqPreampValue = normalizedValue
        self.persistEQSettings()
        if self.eqAutoEnabled {
            self.applyAutoPreampCompensation()
            return
        }
        // Re-apply the whole EQ so passthrough engages/disengages as the preamp crosses 0 dB.
        let settings = self.currentEQSettings()
        self.audioQueue.async { [weak self] in
            self?.applyEQSettings(settings)
        }
    }

    func setEQEnabled(_ enabled: Bool) {
        self.eqEnabled = enabled
        self.persistEQSettings()
        let settings = self.currentEQSettings()
        self.audioQueue.async { [weak self] in
            self?.applyEQSettings(settings)
        }
        if self.eqAutoEnabled {
            // applyEQSettings wrote the manual preamp; restore AUTO compensation on top.
            self.applyAutoPreampCompensation()
        }
    }

    func setEQAutoEnabled(_ enabled: Bool) {
        self.eqAutoEnabled = enabled
        self.persistEQSettings()
        if enabled {
            self.applyAutoPreampCompensation()
        } else {
            self.eqPreampValue = self.manualPreampValue
            self.applyPreampGainToEngine(decibels: self.manualPreampValue * 12)
        }
    }

    /// AmpX AUTO: reduce preamp when bands are boosted to limit clipping.
    private func applyAutoPreampCompensation() {
        guard self.eqAutoEnabled, self.eqEnabled else { return }
        let bandGainsDB = self.eqBandValues.map { $0 * 12 }
        let compensationDB = EQAudioEffect.autoPreampCompensationDB(forBandGainsDB: bandGainsDB)
        self.eqPreampValue = compensationDB / 12
        self.applyPreampGainToEngine(decibels: compensationDB)
    }

    private func applyPreampGainToEngine(decibels: Float) {
        let linearGain = EQAudioEffect.linearGain(fromDecibels: decibels)
        self.spectrumDebugPreampLinear = linearGain
        self.audioQueue.async { [weak self] in
            self?.eqEffect?.setPreampGain(decibels: decibels)
        }
    }

    func applyEQPreset(_ preset: EQPreset) {
        self.eqBandValues = preset.bandGainsDB.map { $0 / 12 }
        self.manualPreampValue = preset.preampGainDB / 12
        self.eqPreampValue = self.manualPreampValue
        self.persistEQSettings()
        let settings = self.currentEQSettings()
        self.audioQueue.async { [weak self] in
            self?.applyEQSettings(settings)
        }
        if self.eqAutoEnabled {
            self.applyAutoPreampCompensation()
        }
    }

    func resetEQ() {
        self.applyEQPreset(EQPreset.builtIn[0])
        self.eqEnabled = true
        self.eqAutoEnabled = false
        self.persistEQSettings()
        self.audioQueue.async { [weak self] in
            self?.eqEffect?.setBypass(false)
        }
    }

    func eqPresets() -> [EQPreset] {
        self.eqSettingsStore.loadPresets()
    }

    /// Present an open panel for `.eqf`/`.q1` files, import their presets, persist
    /// them alongside the existing list, and apply the first imported preset.
    func importEQFPresets() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["eqf", "q1"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        panel.message = "Choose an AmpX equalizer preset file (.eqf or .q1)"

        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.importEQF(from: url)
            }
        }
    }

    /// Import presets from an `.eqf`/`.q1` file URL (no UI). Returns the imported presets.
    @discardableResult
    func importEQF(from url: URL) -> [EQPreset] {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url),
              let imported = try? EQFParser.parse(data), !imported.isEmpty
        else {
            audioLogger.error("Failed to import .eqf presets from \(url.lastPathComponent, privacy: .public)")
            return []
        }

        // Merge: keep existing presets, append imported ones (dedupe by name).
        var presets = self.eqSettingsStore.loadPresets()
        let existingNames = Set(presets.map { $0.name.lowercased() })
        let fresh = imported.filter { !existingNames.contains($0.name.lowercased()) }
        presets.append(contentsOf: fresh)
        self.eqSettingsStore.savePresets(presets)
        self.eqPresetsRevision += 1

        if let first = imported.first {
            self.applyEQPreset(first)
        }
        return imported
    }

    private func startTimer() {
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            // A real `Task`, not `MainActor.assumeIsolated`: the timer fires with no Swift task and
            // on macOS 26 the executor check inside `assumeIsolated` crashes (see commit 5562af8).
            Task { @MainActor in
                self?.tickPlaybackUI()
            }
        }
    }

    private func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
    }

    private func tickPlaybackUI() {
        if self.isPlaying {
            self.refreshCurrentTimeFromEngine()
        } else {
            self.decaySpectrumDisplay()
        }
    }

    private func refreshCurrentTimeFromEngine() {
        self.audioQueue.async { [weak self] in
            guard let self, let time = self.playbackTimeSnapshot() else { return }
            self.runOnMainActor(weak: self) { player in
                guard player.isPlaying else { return }
                player.currentTime = time
            }
        }
    }

    private nonisolated func playbackTimeSnapshot() -> TimeInterval? {
        guard let player = playerNode,
              let lastRenderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: lastRenderTime),
              let file = audioFile
        else {
            return nil
        }
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        let relative = Double(playerTime.sampleTime) / sampleRate
        return max(0, self.playbackSegmentStartTime + relative)
    }

    private func decaySpectrumDisplay() {
        AudioFeatureBus.shared.setPlaying(false)
    }

    /// Runs when the scheduled audio has played back to its end. Leaves the player in the
    /// same stopped state as `stop()` before notifying the delegate: a finished
    /// `AVAudioPlayerNode` otherwise keeps its sample clock running with nothing scheduled,
    /// so a later `resume()` would show wall-clock time, play silence and never finish.
    ///
    /// `generation` is checked on `audioQueue`, where `playbackGeneration` is written, so a
    /// completion that races a newer play/seek/load/stop is dropped instead of stopping the
    /// new playback. The MainActor task re-checks it: a seek/load/stop can land on
    /// `audioQueue` after the first check but before that task runs, and must not have its
    /// UI state cleared or trigger an auto-advance. `nil` skips both checks (test hook only).
    private nonisolated func handleTrackCompletion(generation: Int?) {
        self.audioQueue.async { [weak self] in
            guard let self else { return }
            if let generation, generation != self.playbackGeneration {
                return
            }
            if let transition = self.transition {
                // Automix owns the outgoing deck's end once B is scheduled; the Playlist advances
                // at the switch instead. A transition only prepared is dropped: A ends as usual.
                if transition.armed, !transition.switched {
                    return
                }
                self.cancelTransitionOnQueue(notify: true)
            }
            self.playerNode?.stop()
            self.playbackSegmentStartTime = 0
            self.spectrumAnalyzer?.resetMiniAnalysis()
            self.isPlayingInternal = false
            self.isPausedInternal = false
            let shouldAdvance = self.shouldAutoAdvance

            self.runOnMainActor(weak: self) { player in
                if let generation, generation != player.playbackGeneration {
                    return
                }
                player.isPlaying = false
                player.currentTime = 0
                player.stopTimer()
                player.updateNowPlayingInfo()
                if shouldAdvance {
                    player.onTrackFinished?()
                }
            }
        }
    }

    private(set) var testing_lastTransportAction: TestingTransportAction?
}

// MARK: - Automix transitions

/// A transition the coordinator has planned: the incoming track, its mix plan, and both grids for per-bar rate
/// updates (DJ mode spec Revision 2 § Audio graph, Drifting class).
struct PreparedTransition: Sendable {
    let token: UUID
    let track: Track
    let plan: MixPlan
    let incomingGrid: MixGrid?
    let outgoingGrid: MixGrid?
}

/// A transition on the audio queue: prepared (B loaded on the idle deck), armed (B scheduled), blending (A past its
/// mix-out) and switched (B is live).
struct ActiveTransition {
    let prepared: PreparedTransition
    let curve: BlendCurve
    let outgoing: Int
    let incoming: Int
    let duration: Double
    let sampleRate: Double
    let channels: Int
    let bitrate: Int
    var armed = false
    var blending = false
    var switched = false
    var lastBar: Int?
}

extension AudioPlayer {
    /// Loads B onto the idle deck at fade 0 without scheduling it; `false` if the file does not open, and A plays on.
    func prepareTransition(_ prepared: PreparedTransition, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let url = prepared.track.url else {
            completion(false)
            return
        }
        let incoming = 1 - self.liveDeckIndex
        self.deckTrackIDs[incoming] = prepared.track.id
        self.deckReplayGains[incoming] = ReplayGain()
        self.applyPlayerVolume()
        self.audioQueue.async { [weak self] in
            guard let self, let graph = self.audioGraph else { return }
            self.cancelTransitionOnQueue(notify: false)
            let outgoing = graph.liveDeckIndex
            let incoming = 1 - outgoing
            guard let file = try? AVAudioFile(forReading: url) else {
                self.runOnMainActor { completion(false) }
                return
            }
            let duration = Double(file.length) / file.fileFormat.sampleRate
            let format = AudioFormatInfo.read(from: url, duration: duration)
            let deck = graph.decks[incoming]
            deck.player.stop()
            deck.player.reset()
            deck.reset()
            deck.fade.outputVolume = 0
            self.deckStates[incoming] = DeckPlayback(file: file, segmentStart: prepared.plan.incomingStart)
            self.transition = ActiveTransition(
                prepared: prepared,
                curve: BlendCurve(plan: prepared.plan),
                outgoing: outgoing,
                incoming: incoming,
                duration: duration,
                sampleRate: format?.sampleRateHz ?? file.fileFormat.sampleRate,
                channels: format?.channelCount ?? Int(file.fileFormat.channelCount),
                bitrate: format?.bitrateKbps ?? 128
            )
            self.runOnMainActor { completion(true) }

            let trackID = prepared.track.id
            Task { [weak self] in
                let replayGain = await ReplayGainReader.read(from: url)
                await MainActor.run { [weak self] in
                    guard let self, self.deckTrackIDs[incoming] == trackID else { return }
                    self.deckReplayGains[incoming] = replayGain
                    if incoming == self.liveDeckIndex {
                        self.currentReplayGain = replayGain
                    }
                    self.applyPlayerVolume()
                }
            }
        }
    }

    /// Schedules B from its mix-in point to start at the host time where A reaches its mix-out, and starts the
    /// 10 ms blend ticker.
    func armTransition(token: UUID) {
        self.audioQueue.async { [weak self] in
            guard let self, var transition = self.transition, transition.prepared.token == token, !transition.armed,
                  let graph = self.audioGraph, let file = self.deckStates[transition.incoming].file
            else { return }
            let plan = transition.prepared.plan
            let outgoing = graph.decks[transition.outgoing]
            let incoming = graph.decks[transition.incoming]

            let sampleRate = file.fileFormat.sampleRate
            let startFrame = min(max(AVAudioFramePosition(plan.incomingStart * sampleRate), 0), max(file.length - 1, 0))
            incoming.player.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: AVAudioFrameCount(file.length - startFrame),
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                self?.handleIncomingCompletion(token: token)
            }
            if case let .beatmatched(rate, _) = plan.kind {
                incoming.setRate(Float(rate))
            }
            incoming.fade.outputVolume = 0
            incoming.setLowCut(transition.curve.lowCut(atOutgoingTime: plan.outgoingStart).incoming)

            if let render = outgoing.player.lastRenderTime, render.isHostTimeValid,
               let playerTime = outgoing.player.playerTime(forNodeTime: render), playerTime.sampleRate > 0
            {
                let now = self.deckStates[transition.outgoing].segmentStart + Double(playerTime.sampleTime) / playerTime.sampleRate
                let start = DeckSync.startHostTime(
                    nowHostTime: render.hostTime,
                    outgoingNow: now,
                    outgoingTarget: plan.outgoingStart,
                    outgoingRate: Double(outgoing.timePitch.rate),
                    ticksPerSecond: Double(AVAudioTime.hostTime(forSeconds: 1))
                )
                incoming.player.play(at: AVAudioTime(hostTime: start))
            } else {
                incoming.player.play()
            }
            transition.armed = true
            self.transition = transition
            if !self.testing_manualBlendTicks {
                self.startBlendTimer()
            }
        }
    }

    /// Drops a prepared or armed transition; a running blend is cut and the live deck returns to full level.
    func cancelTransition() {
        self.audioQueue.async { [weak self] in
            self?.cancelTransitionOnQueue(notify: false)
        }
    }

    /// During a blend: B to full gain, A stopped, the transport switched if it had not yet. `false` outside a blend.
    func completeTransitionNow() -> Bool {
        guard self.isBlending else { return false }
        self.isBlending = false
        self.audioQueue.async { [weak self] in
            self?.finishTransitionOnQueue()
        }
        return true
    }

    /// Sets the live deck's tempo rate (the glide back).
    func setLiveRate(_ rate: Double) {
        self.liveRate = rate
        self.audioQueue.async { [weak self] in
            self?.audioGraph?.liveDeck?.setRate(Float(rate))
        }
    }

    /// The live track's position and rate, for the coordinator.
    func liveEffectiveState() -> (fileTime: Double, rate: Double)? {
        self.currentTrack == nil ? nil : (self.currentTime, self.liveRate)
    }

    // MARK: Audio queue

    private nonisolated func startBlendTimer() {
        self.blendTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: self.audioQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self, let transition = self.transition,
                  let time = self.deckFileTime(transition.outgoing) else { return }
            self.blendTick(outgoingTime: time)
        }
        self.blendTimer = timer
        timer.resume()
    }

    private nonisolated func stopBlendTimer() {
        self.blendTimer?.cancel()
        self.blendTimer = nil
    }

    /// A deck's file position from its own sample clock; nil while it is not rendering.
    private nonisolated func deckFileTime(_ index: Int) -> Double? {
        guard let player = self.audioGraph?.decks[index].player, let render = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: render), playerTime.sampleRate > 0
        else { return nil }
        return self.deckStates[index].segmentStart + Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    /// One step of the blend, from A's file time: envelopes, Bass Swap cut, per-bar rate, the switch and the end.
    private nonisolated func blendTick(outgoingTime time: Double) {
        guard var transition = self.transition, transition.armed, let graph = self.audioGraph else { return }
        let plan = transition.prepared.plan
        let curve = transition.curve
        let outgoing = graph.decks[transition.outgoing]
        let incoming = graph.decks[transition.incoming]

        if time >= plan.outgoingStart, !transition.blending {
            transition.blending = true
            self.runOnMainActor(weak: self) { $0.isBlending = true }
        }
        let gains = curve.gains(at: curve.progress(atOutgoingTime: time))
        outgoing.fade.outputVolume = gains.outgoing
        incoming.fade.outputVolume = gains.incoming
        let cut = curve.lowCut(atOutgoingTime: time)
        outgoing.setLowCut(cut.outgoing)
        incoming.setLowCut(cut.incoming)

        if case .beatmatched = plan.kind, transition.blending,
           let gridA = transition.prepared.outgoingGrid, let gridB = transition.prepared.incomingGrid
        {
            let bar = Int(floor(gridA.bar(at: time)))
            if bar != transition.lastBar {
                transition.lastBar = bar
                let incomingTime = self.deckFileTime(transition.incoming) ?? plan.incomingStart
                if let rate = TempoPlan.matchRate(
                    outgoingEffectiveBPM: gridA.localBPM(at: time) * Double(outgoing.timePitch.rate),
                    incomingLocalBPM: gridB.localBPM(at: incomingTime)
                ) {
                    incoming.setRate(Float(rate))
                }
            }
        }
        self.transition = transition

        if !transition.switched, curve.isPastSwitch(atOutgoingTime: time) {
            self.performSwitchOnQueue()
        }
        if curve.progress(atOutgoingTime: time) >= 1 {
            self.finishTransitionOnQueue()
        }
    }

    /// B becomes the live deck: transport, Now Playing and the Playlist follow it, once.
    private nonisolated func performSwitchOnQueue() {
        guard var transition = self.transition, !transition.switched, let graph = self.audioGraph else { return }
        transition.switched = true
        self.transition = transition
        graph.setLiveDeck(transition.incoming)
        // A's scheduled completion is now stale; B's completion acts as the live deck's.
        self.playbackGeneration += 1
        self.liveTransitionGeneration = self.playbackGeneration
        self.liveTransitionToken = transition.prepared.token
        self.shouldAutoAdvance = true
        let incoming = transition.incoming
        let track = transition.prepared.track
        let rate = Double(graph.decks[incoming].timePitch.rate)
        let time = self.playbackTimeSnapshot() ?? transition.prepared.plan.incomingStart
        let format = (transition.duration, transition.sampleRate, transition.channels, transition.bitrate)
        self.runOnMainActor(weak: self) { player in
            player.liveDeckIndex = incoming
            player.liveRate = rate
            player.currentTrack = track
            player.currentReplayGain = player.deckReplayGains[incoming]
            player.duration = format.0
            player.currentSampleRate = format.1
            player.currentChannels = format.2
            player.currentBitrate = format.3
            player.currentTime = time
            player.updateNowPlayingInfo()
            player.onAutomixTrackChanged?(track)
        }
    }

    /// Ends the blend: switches if needed, stops A, and leaves B alone at full level.
    private nonisolated func finishTransitionOnQueue() {
        guard let transition = self.transition, let graph = self.audioGraph else { return }
        if !transition.switched {
            self.performSwitchOnQueue()
        }
        let outgoing = graph.decks[transition.outgoing]
        outgoing.player.stop()
        outgoing.player.reset()
        outgoing.reset()
        self.deckStates[transition.outgoing] = DeckPlayback()
        graph.decks[transition.incoming].fade.outputVolume = 1
        graph.decks[transition.incoming].setLowCut(false)
        self.stopBlendTimer()
        self.transition = nil
        let outgoingIndex = transition.outgoing
        self.runOnMainActor(weak: self) { player in
            player.isBlending = false
            player.deckTrackIDs[outgoingIndex] = nil
        }
    }

    /// Stops the idle deck and returns the live deck to full level with no cut.
    private nonisolated func cancelTransitionOnQueue(notify: Bool) {
        guard self.transition != nil, let graph = self.audioGraph, let live = graph.liveDeck, let idle = graph.idleDeck else { return }
        self.stopBlendTimer()
        self.transition = nil
        let idleIndex = 1 - graph.liveDeckIndex
        idle.player.stop()
        idle.player.reset()
        idle.reset()
        self.deckStates[idleIndex] = DeckPlayback()
        live.fade.outputVolume = 1
        live.setLowCut(false)
        self.runOnMainActor(weak: self) { player in
            player.isBlending = false
            player.deckTrackIDs[idleIndex] = nil
            if notify {
                player.onTransitionCancelled?()
            }
        }
    }

    /// Pause mid-blend freezes both decks; before the mix-out, an armed transition is dropped and re-planned.
    private nonisolated func pauseTransitionOnQueue() {
        guard let transition = self.transition, transition.armed else { return }
        if transition.blending {
            self.audioGraph?.idleDeck?.player.pause()
        } else {
            self.cancelTransitionOnQueue(notify: true)
        }
    }

    private nonisolated func handleIncomingCompletion(token: UUID) {
        self.audioQueue.async { [weak self] in
            guard let self, self.liveTransitionToken == token else { return }
            self.handleTrackCompletion(generation: self.liveTransitionGeneration)
        }
    }

    func testing_tick(outgoingFileTime time: Double) {
        self.audioQueue.async { [weak self] in
            self?.blendTick(outgoingTime: time)
        }
    }
}

// MARK: - Test hooks

///
/// Kept in an extension so the class body above stays focused on playback. Same file,
/// not a separate one, because these hooks reach into the engine's `private` state.
extension AudioPlayer {
    enum TestingTransportAction: Equatable {
        case play
        case resume
        case pause
        case stop
    }

    func testing_simulateTrackCompletion() {
        self.handleTrackCompletion(generation: nil)
    }

    func testing_afterAudioQueueFlush(completion: @escaping @Sendable () -> Void) {
        self.audioQueue.async {
            completion()
        }
    }

    func testing_shouldAutoAdvance(completion: @escaping @Sendable (Bool) -> Void) {
        self.audioQueue.async { [weak self] in
            completion(self?.shouldAutoAdvance ?? false)
        }
    }

    func testing_markAsPlayingForTests() {
        self.audioQueue.async { [weak self] in
            guard let self else { return }
            self.isPlayingInternal = true
            self.shouldAutoAdvance = true
            self.runOnMainActor(weak: self) { player in
                player.isPlaying = true
            }
        }
    }

    func testing_isPlayingInternal(completion: @escaping @Sendable (Bool) -> Void) {
        self.audioQueue.async { [weak self] in
            completion(self?.isPlayingInternal ?? false)
        }
    }

    func testing_setPlaybackUIStateForTests(isPlaying: Bool, currentTime: TimeInterval) {
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self.audioQueue.async { [weak self] in
            self?.isPlayingInternal = isPlaying
        }
    }

    func testing_playerNodeIdentity(completion: @escaping @Sendable (ObjectIdentifier?) -> Void) {
        self.audioQueue.async { [weak self] in
            completion(self?.playerNode.map { ObjectIdentifier($0) })
        }
    }

    func testing_stopEngineForTests(completion: @escaping @Sendable () -> Void) {
        self.audioQueue.async { [weak self] in
            self?.audioEngine?.stop()
            guard let self else {
                completion()
                return
            }
            self.runOnMainActor(weak: self) { player in
                player.engineIsRunning = false
                completion()
            }
        }
    }

    func testing_playbackTimeSnapshot(completion: @escaping @Sendable (TimeInterval?) -> Void) {
        self.audioQueue.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            let snapshot = self.playbackTimeSnapshot()
            completion(snapshot)
        }
    }

    struct DeckSnapshot: Equatable, Sendable {
        let rate: Float
        let lowCut: Bool
        let fade: Float
        let playerVolume: Float
        let pan: Float
        let isPlaying: Bool
        let isLive: Bool
    }

    func testing_deckSnapshot(completion: @escaping @Sendable ([DeckSnapshot]) -> Void) {
        self.audioQueue.async { [weak self] in
            guard let graph = self?.audioGraph else {
                completion([])
                return
            }
            completion(graph.decks.enumerated().map { index, deck in
                DeckSnapshot(
                    rate: deck.timePitch.rate,
                    lowCut: !deck.lowCut.bypass,
                    fade: deck.fade.outputVolume,
                    playerVolume: deck.player.volume,
                    pan: deck.player.pan,
                    isPlaying: deck.player.isPlaying,
                    isLive: index == graph.liveDeckIndex
                )
            })
        }
    }

    func testing_configureDeck(_ index: Int, rate: Float, fade: Float, lowCut: Bool) {
        self.audioQueue.async { [weak self] in
            guard let deck = self?.audioGraph?.decks[index] else { return }
            deck.setRate(rate)
            deck.fade.outputVolume = fade
            deck.setLowCut(lowCut)
        }
    }

    func testing_setReplayGain(_ replayGain: ReplayGain, deck: Int) {
        self.deckReplayGains[deck] = replayGain
        if deck == self.liveDeckIndex {
            self.currentReplayGain = replayGain
        }
        self.applyPlayerVolume()
    }
}

/// One deck's playback state on the audio queue: the scheduled file and where its segment starts.
struct DeckPlayback {
    var file: AVAudioFile?
    /// Absolute file time at the start of the deck's scheduled segment.
    var segmentStart: TimeInterval = 0
}

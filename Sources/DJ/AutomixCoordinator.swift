import Combine
import Foundation

/// The surface of `AudioPlayer` Automix drives (a seam for tests).
@MainActor
protocol AutomixDeckControlling: AnyObject {
    var currentTrack: Track? { get }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    var isBlending: Bool { get }
    var onAutomixTrackChanged: (@MainActor @Sendable (Track) -> Void)? { get set }
    var onTransitionCancelled: (@MainActor @Sendable () -> Void)? { get set }
    func prepareTransition(_ prepared: PreparedTransition, completion: @escaping @MainActor @Sendable (Bool) -> Void)
    func armTransition(token: UUID)
    func cancelTransition()
    func completeTransitionNow() -> Bool
    func setLiveRate(_ rate: Double)
    func liveEffectiveState() -> (fileTime: Double, rate: Double)?
}

extension AudioPlayer: AutomixDeckControlling {}

/// Drives the coordinator's ticks: a 250 ms timer in the app, nothing in tests (they call `tick()`).
struct AutomixClock {
    let start: @MainActor (@escaping @MainActor @Sendable () -> Void) -> AnyCancellable?

    static var live: AutomixClock {
        AutomixClock { fire in
            let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
                // A real `Task`, not `MainActor.assumeIsolated` (see AudioPlayer.startTimer).
                Task { @MainActor in fire() }
            }
            // `.common`, so ticks continue while a menu is open or a window is dragged.
            RunLoop.main.add(timer, forMode: .common)
            return AnyCancellable { timer.invalidate() }
        }
    }

    static var manual: AutomixClock {
        AutomixClock { _ in nil }
    }
}

/// Plays the Playlist as a continuous set (DJ mode spec Revision 2 § Delivery 2: Automix): decides what plays next,
/// continues with MIXES WELL when the Playlist runs out, plans each transition and prepares and arms it on the
/// decks at the right moment, glides the tempo back between transitions, and moves the Playlist at each switch.
@MainActor
final class AutomixCoordinator: ObservableObject {
    /// B is loaded this long before A's mix-out.
    static let prepareLead = 10.0
    /// After this point (seconds before the mix-out) the plan stands; only removing B drops it.
    static let freezeLead = 5.0
    /// B is scheduled this long before the mix-out.
    static let armLead = 1.0

    /// The live deck's local BPM × its rate; nil when unknown. MIXES WELL and the continuation match against it.
    @Published private(set) var effectiveTempo: Double?
    /// Library rows played since Automix was turned on: never picked again.
    private(set) var playedRowIDs: Set<UUID> = []

    private struct Context {
        let trackID: UUID
        let row: LibraryRow?
        let track: AutomixTrack
    }

    private enum Phase {
        case idle
        case preparing(token: UUID, trackID: UUID)
        case prepared(token: UUID, trackID: UUID, plan: MixPlan)
        case armed
    }

    private let settings: AutomixSettingsStore
    private let playlist: PlaylistManager
    private let deck: AutomixDeckControlling
    private let library: @MainActor () -> AutomixLibrary?
    private var clockCancellable: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []

    private var live: Context?
    private var next: Context?
    private var phase = Phase.idle
    private var continuationTriedFor: UUID?
    private var lastGlideBar: Int?
    private var isTicking = false

    init(
        settings: AutomixSettingsStore,
        playlist: PlaylistManager,
        deck: AutomixDeckControlling,
        library: @escaping @MainActor () -> AutomixLibrary?,
        clock: AutomixClock = .live
    ) {
        self.settings = settings
        self.playlist = playlist
        self.deck = deck
        self.library = library

        deck.onAutomixTrackChanged = { [weak self] track in self?.trackChanged(track) }
        deck.onTransitionCancelled = { [weak self] in self?.phase = .idle }
        playlist.nextInterceptor = { [weak deck] in deck?.completeTransitionNow() ?? false }
        playlist.playlistChanged
            .sink { [weak self] in self?.continuationTriedFor = nil }
            .store(in: &self.cancellables)
        settings.$settings
            .map(\.enabled)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in self?.enabledChanged(enabled) }
            .store(in: &self.cancellables)
        self.clockCancellable = clock.start { [weak self] in
            Task { await self?.tick() }
        }
    }

    // MARK: - Tick

    func tick() async {
        guard !self.isTicking else { return }
        self.isTicking = true
        defer { self.isTicking = false }

        guard self.settings.settings.enabled, self.deck.isPlaying, let liveTrack = self.deck.currentTrack,
              let state = self.deck.liveEffectiveState()
        else { return }
        if self.live?.trackID != liveTrack.id {
            await self.liveTrackStarted(liveTrack)
        }
        guard let live = self.live else { return }
        self.effectiveTempo = self.tempo(of: live, at: state.fileTime, rate: state.rate)
        guard !self.deck.isBlending else { return }

        if self.playlist.nextTrackIndex() == nil {
            await self.continueWithMixesWellIfNeeded(liveTrackID: liveTrack.id)
        }
        await self.planNext(live: live, state: state)

        if case .idle = self.phase {
            self.glide(live: live, state: state)
        }
    }

    private func liveTrackStarted(_ track: Track) async {
        let context = await self.context(for: track)
        self.live = context
        self.next = nil
        self.lastGlideBar = nil
        if let rowID = context.row?.id {
            self.playedRowIDs.insert(rowID)
        }
    }

    private func context(for track: Track) async -> Context {
        let duration = track.duration > 0 ? track.duration : self.deck.duration
        guard let url = track.url, let library = self.library() else {
            return Context(trackID: track.id, row: nil, track: .unknown(duration: duration))
        }
        let (row, automix) = await library.track(url: url, duration: duration)
        return Context(trackID: track.id, row: row, track: automix)
    }

    private func tempo(of context: Context, at time: Double, rate: Double) -> Double? {
        if let grid = context.track.grid {
            return grid.localBPM(at: time) * rate
        }
        return context.row?.bpm.map { $0 * rate }
    }

    // MARK: - What plays next

    private func continueWithMixesWellIfNeeded(liveTrackID: UUID) async {
        let settings = self.settings.settings
        guard settings.continueWithMixesWell, !self.playlist.repeatEnabled, self.continuationTriedFor != liveTrackID,
              let reference = self.live?.row, let tempo = self.effectiveTempo ?? reference.bpm, let library = self.library()
        else { return }
        self.continuationTriedFor = liveTrackID
        let pool = await library.pool(settings.pickFrom, filter: self.settings.pickFilter)
        let queued = Set(self.playlist.tracks.compactMap(\.url))
        let removed = self.playlist.removedAutoURLs
        let excluded = self.playedRowIDs.union(pool.filter { removed.contains($0.url) || queued.contains($0.url) }.map(\.id))
        guard self.playlist.nextTrackIndex() == nil,
              let pick = MixesWell.nextPick(reference: reference, tempo: tempo, pool: pool, excluded: excluded)
        else { return }
        self.playlist.appendAutoTrack(pick.makeTrack())
        // The append itself is a playlist change; the pick for this track is done.
        self.continuationTriedFor = liveTrackID
    }

    private func planNext(live: Context, state: (fileTime: Double, rate: Double)) async {
        guard let index = self.playlist.nextTrackIndex() else {
            self.dropPrepared()
            return
        }
        let nextTrack = self.playlist.tracks[index]
        if case .armed = self.phase {
            return
        }
        if self.next?.trackID != nextTrack.id {
            self.next = await self.context(for: nextTrack)
        }
        guard let next = self.next, let plan = MixPoints.plan(
            outgoing: live.track,
            incoming: next.track,
            outgoingRate: state.rate,
            outgoingPosition: state.fileTime,
            settings: self.settings.settings
        ) else {
            self.dropPrepared()
            return
        }
        let lead = (plan.outgoingStart - state.fileTime) / max(state.rate, 0.000_1)

        switch self.phase {
        case let .prepared(token, trackID, preparedPlan):
            if trackID != nextTrack.id || preparedPlan != plan {
                let stillQueued = self.playlist.tracks.contains { $0.id == trackID }
                guard lead > Self.freezeLead || !stillQueued else {
                    // Frozen: the plan stands while B is still in the Playlist.
                    if lead <= Self.armLead {
                        self.arm(token)
                    }
                    return
                }
                self.deck.cancelTransition()
                self.phase = .idle
            } else if lead <= Self.armLead {
                self.arm(token)
                return
            } else {
                return
            }
        case .preparing, .armed:
            return
        case .idle:
            break
        }

        guard lead <= Self.prepareLead else { return }
        let token = UUID()
        self.phase = .preparing(token: token, trackID: nextTrack.id)
        let prepared = PreparedTransition(
            token: token, track: nextTrack, plan: plan, incomingGrid: next.track.grid, outgoingGrid: live.track.grid
        )
        self.deck.prepareTransition(prepared) { [weak self] ok in
            guard let self, case let .preparing(current, _) = self.phase, current == token else { return }
            self.phase = ok ? .prepared(token: token, trackID: nextTrack.id, plan: plan) : .idle
            // Arm without waiting for the next tick when the prepare finished inside the arm window.
            if ok {
                Task { await self.tick() }
            }
        }
        if case .prepared = self.phase, lead <= Self.armLead {
            self.arm(token)
        }
    }

    private func arm(_ token: UUID) {
        self.deck.armTransition(token: token)
        self.phase = .armed
    }

    /// Drops a prepared transition when there is no next track any more (B removed) or no plan.
    private func dropPrepared() {
        switch self.phase {
        case .prepared, .preparing:
            self.deck.cancelTransition()
            self.phase = .idle
        case .idle, .armed:
            break
        }
    }

    private func trackChanged(_ track: Track) {
        if let index = self.playlist.tracks.firstIndex(where: { $0.id == track.id }) {
            self.playlist.advanceToIncoming(index: index)
        }
        if let next = self.next, next.trackID == track.id {
            self.live = next
            if let rowID = next.row?.id {
                self.playedRowIDs.insert(rowID)
            }
        }
        self.next = nil
        self.phase = .idle
        self.lastGlideBar = nil
        self.continuationTriedFor = nil
    }

    // MARK: - Glide back

    /// On each new bar of the live track, one glide step toward its original tempo (spec § Tempo).
    private func glide(live: Context, state: (fileTime: Double, rate: Double)) {
        guard self.settings.settings.glideBack, state.rate != 1, let grid = live.track.grid else { return }
        let bar = Int(floor(grid.bar(at: state.fileTime)))
        guard bar != self.lastGlideBar else { return }
        self.lastGlideBar = bar
        let original = grid.localBPM(at: state.fileTime)
        let current = original * state.rate
        let nextBPM = self.next?.track.grid.map { $0.localBPM(at: 0) } ?? self.next?.row?.bpm
        let stepped = TempoPlan.glideStep(
            currentBPM: current, originalBPM: original, nextBPM: nextBPM, speedPer4Bars: self.settings.settings.glideSpeed
        )
        if stepped != current {
            self.deck.setLiveRate(stepped / original)
        }
    }

    // MARK: - Settings

    private func enabledChanged(_ enabled: Bool) {
        if enabled {
            self.playedRowIDs = []
            self.live = nil
            return
        }
        switch self.phase {
        case .prepared, .preparing, .armed:
            if !self.deck.isBlending {
                self.deck.cancelTransition()
            }
            self.phase = .idle
        case .idle:
            break
        }
    }
}

@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § What plays next, § Tempo (glide), § Clock, completion and transport.
@MainActor
final class AutomixCoordinatorTests: XCTestCase {
    private var deck: MockAutomixDeck!
    private var library: MockAutomixLibrary!
    private var playlist: PlaylistManager!
    private var player: MockAudioPlayer!
    private var settings: AutomixSettingsStore!
    private var coordinator: AutomixCoordinator!

    /// A, B, C: 128 BPM from 0 s, 375 s long (content ends at bar 200; Last Phrase mixes out at bar 176 = 330 s).
    private var a: Track!
    private var b: Track!
    private var c: Track!

    override func setUp() async throws {
        try await super.setUp()
        self.deck = MockAutomixDeck()
        self.library = MockAutomixLibrary()
        self.player = MockAudioPlayer()
        self.playlist = PlaylistManager(audioPlayer: self.player, restoreBookmarks: false, restorePlaylist: false, alertPresenter: SilentPlaylistAlertPresenter())
        self.settings = AutomixSettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        var settings = AutomixSettings()
        settings.enabled = true
        settings.mixPoints = .lastPhrase
        settings.continueWithMixesWell = false
        self.settings.settings = settings
        (self.a, self.b, self.c) = (self.track("A"), self.track("B"), self.track("C"))
        let library = self.library!
        self.coordinator = AutomixCoordinator(
            settings: self.settings, playlist: self.playlist, deck: self.deck, library: { library }, clock: .manual
        )
    }

    private func row(_ title: String, bpm: Double = 128, camelot: String = "8A") -> LibraryRow {
        var row = LibraryRow(
            id: UUID(), rootID: UUID(), url: URL(fileURLWithPath: "/Music/DJ/\(title).mp3"),
            title: title, artist: "Artist", album: "", albumArtist: "",
            genre: "Techno", trackNumber: nil, duration: 375, fileSize: 1,
            bpm: bpm, musicalKey: nil, camelotKey: camelot, bitrate: 0, bitrateIsDerived: false,
            codec: "mp3", isAvailable: true, searchKey: title.lowercased()
        )
        row.tempoSpread = 0
        return row
    }

    @discardableResult
    private func track(_ title: String, bpm: Double = 128, inLibrary: Bool = true) -> Track {
        let row = self.row(title, bpm: bpm)
        if inLibrary {
            let grid = MixGrid(segments: [RekordboxBeat(start: 0, bpm: bpm, meter: "4/4", beat: 1)], duration: 375)
            self.library.tracks[row.url] = (row, AutomixTrack(duration: 375, trackClass: .steady, grid: grid, phrases: nil))
        }
        return Track(title: title, artist: "Artist", duration: 375, url: row.url)
    }

    private func start(_ tracks: [Track], at time: Double, current: Int = 0) async {
        self.playlist.addTracks(tracks)
        self.playlist.currentIndex = current
        self.deck.currentTrack = tracks[current]
        await self.at(time)
    }

    private func at(_ time: Double) async {
        self.deck.fileTime = time
        await self.coordinator.tick()
    }

    func testPreparesTenSecondsBeforeMixOutAndArmsAtOne() async {
        await self.start([self.a, self.b], at: 310)
        XCTAssertTrue(self.deck.prepared.isEmpty)
        await self.at(321)
        XCTAssertEqual(self.deck.prepared.map(\.track.id), [self.b.id])
        XCTAssertEqual(self.deck.prepared.first?.plan.outgoingStart ?? 0, 330, accuracy: 1e-9)
        XCTAssertTrue(self.deck.armed.isEmpty)
        await self.at(329.2)
        XCTAssertEqual(self.deck.armed, [self.deck.prepared[0].token])
        await self.at(329.5)
        XCTAssertEqual(self.deck.armed.count, 1)
    }

    func testPlaylistChangeBeforeFreezeReprepares() async {
        await self.start([self.a, self.b, self.c], at: 321)
        self.playlist.moveTrack(from: 2, to: 1)
        await self.at(322)
        XCTAssertEqual(self.deck.cancelCount, 1)
        XCTAssertEqual(self.deck.prepared.map(\.track.id), [self.b.id, self.c.id])
    }

    func testPlaylistChangeAfterFreezeKeepsPlan() async {
        await self.start([self.a, self.b, self.c], at: 321)
        self.playlist.moveTrack(from: 2, to: 1)
        await self.at(326)
        XCTAssertEqual(self.deck.cancelCount, 0)
        await self.at(329.2)
        XCTAssertEqual(self.deck.armed, [self.deck.prepared[0].token])
        XCTAssertEqual(self.deck.prepared.count, 1)
    }

    func testRemovedNextTrackCancelsPreparedTransition() async {
        await self.start([self.a, self.b], at: 321)
        self.playlist.removeTrack(at: 1)
        await self.at(326)
        XCTAssertEqual(self.deck.cancelCount, 1)
        await self.at(329.2)
        XCTAssertTrue(self.deck.armed.isEmpty)
    }

    func testContinuationAppendsAutoPickWhenLastTrackStarts() async {
        self.settings.settings.continueWithMixesWell = true
        let pick = self.row("Pick", bpm: 127)
        self.library.poolRows = [pick, self.row("Far", bpm: 150)]
        await self.start([self.a], at: 1)
        XCTAssertEqual(self.playlist.tracks.map(\.url), [self.a.url, pick.url])
        XCTAssertEqual(self.playlist.autoTrackIDs.count, 1)
        XCTAssertEqual(self.library.poolRequests.first?.0, .currentView)
    }

    func testContinuationOffOrRepeatOnNeverPicks() async {
        self.library.poolRows = [self.row("Pick")]
        await self.start([self.a], at: 1)
        XCTAssertEqual(self.playlist.tracks.count, 1)
        self.settings.settings.continueWithMixesWell = true
        self.playlist.repeatEnabled = true
        await self.at(2)
        XCTAssertEqual(self.playlist.tracks.count, 1)
    }

    func testContinuationExcludesPlayedAndRemovedAuto() async {
        self.settings.settings.continueWithMixesWell = true
        let first = self.row("First", bpm: 128)
        let second = self.row("Second", bpm: 127)
        let third = self.row("Third", bpm: 126)
        self.library.poolRows = [self.library.tracks[self.a.url!]!.row!, first, second, third]
        await self.start([self.a], at: 1)
        XCTAssertEqual(self.playlist.tracks.last?.url, first.url, "the playing track itself is never picked")
        self.playlist.removeTrack(at: 1)
        await self.at(2)
        XCTAssertEqual(self.playlist.tracks.last?.url, second.url, "a removed AUTO pick does not come back")
    }

    func testContinuationUsesEffectiveTempo() async {
        self.settings.settings.continueWithMixesWell = true
        let slow = self.row("Slow", bpm: 125)
        let fast = self.row("Fast", bpm: 133)
        self.library.poolRows = [slow, fast]
        let live = self.track("Live", bpm: 125)
        self.deck.rate = 1.06
        await self.start([live], at: 1)
        XCTAssertEqual(self.coordinator.effectiveTempo ?? 0, 132.5, accuracy: 1e-9)
        XCTAssertEqual(self.playlist.tracks.last?.url, fast.url)
    }

    func testEmptyPoolStopsAfterCurrentTrack() async {
        self.settings.settings.continueWithMixesWell = true
        await self.start([self.a], at: 321)
        XCTAssertEqual(self.playlist.tracks.count, 1)
        XCTAssertTrue(self.deck.prepared.isEmpty)
    }

    func testNonLibraryNextTrackGetsCrossfadePlan() async {
        let outsider = Track(title: "Outsider", artist: "X", duration: 200, url: URL(fileURLWithPath: "/Downloads/outsider.mp3"))
        await self.start([self.a, outsider], at: 362)
        XCTAssertEqual(self.deck.prepared.first?.plan.kind, .crossfade)
        XCTAssertEqual(self.deck.prepared.first?.plan.outgoingStart ?? 0, 369, accuracy: 1e-9)
    }

    func testGlideOnlyOnBarBoundariesAndNotWhilePrepared() async {
        self.settings.settings.glideBack = true
        let slower = self.track("Slower", bpm: 126)
        self.deck.rate = 1.03
        await self.start([self.a, slower], at: 20)
        XCTAssertEqual(self.deck.rates.count, 1)
        XCTAssertEqual(self.deck.rates[0] * 128, 128 * 1.03 - 0.025, accuracy: 1e-9)
        await self.at(20.5)
        XCTAssertEqual(self.deck.rates.count, 1, "same bar")
        await self.at(22)
        XCTAssertEqual(self.deck.rates.count, 2, "next bar")
        await self.at(321)
        await self.at(324)
        XCTAssertEqual(self.deck.rates.count, 2, "frozen once B is prepared")
    }

    func testTrackChangeAdvancesPlaylistWithoutLoad() async {
        await self.start([self.a, self.b], at: 321)
        self.deck.onAutomixTrackChanged?(self.b)
        XCTAssertEqual(self.playlist.currentIndex, 1)
        XCTAssertTrue(self.player.loadTrackCalls.isEmpty)
    }

    func testTurningOffCancelsArmedButNotBlending() async {
        await self.start([self.a, self.b], at: 329.2)
        XCTAssertEqual(self.deck.armed.count, 1)
        self.settings.settings.enabled = false
        XCTAssertEqual(self.deck.cancelCount, 1)

        self.settings.settings.enabled = true
        self.deck.currentTrack = self.b
        self.playlist.addTracks([self.c])
        self.playlist.currentIndex = 1
        await self.at(329.2)
        self.deck.isBlending = true
        self.settings.settings.enabled = false
        XCTAssertEqual(self.deck.cancelCount, 1, "a running blend finishes")
    }

    func testNextDuringBlendCompletesInsteadOfSkipping() async {
        await self.start([self.a, self.b], at: 331)
        self.deck.isBlending = true
        self.playlist.next()
        XCTAssertEqual(self.deck.completeNowCount, 1)
        XCTAssertTrue(self.player.loadTrackCalls.isEmpty)
    }

    func testSeekCancellationReplansFromNewPosition() async {
        await self.start([self.a, self.b], at: 321)
        XCTAssertEqual(self.deck.prepared.count, 1)
        self.deck.onTransitionCancelled?()
        await self.at(200)
        XCTAssertEqual(self.deck.prepared.count, 1)
        await self.at(321)
        XCTAssertEqual(self.deck.prepared.count, 2)
    }

    /// Review finding 2: with an asynchronous prepare inside the arm window, arming must not wait for the next tick.
    func testAsyncPrepareInsideArmWindowArmsAtOnce() async {
        self.deck.completesAsynchronously = true
        await self.start([self.a, self.b], at: 329.5)
        XCTAssertEqual(self.deck.prepared.count, 1)
        for _ in 0 ..< 20 where self.deck.armed.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(self.deck.armed, [self.deck.prepared[0].token])
    }
}

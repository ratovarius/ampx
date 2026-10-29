@testable import AmpX
import AVFoundation
import XCTest

/// DJ mode spec Revision 2 § Transitions, § Clock, completion and transport. Ticks are injected with
/// `testing_tick(outgoingFileTime:)`; the real 10 ms ticker is off in these tests.
@MainActor
final class AudioPlayerTransitionTests: XCTestCase {
    private var player: AudioPlayer!
    private var trackA: Track!
    private var trackB: Track!
    @MainActor private final class Events {
        var changes: [Track] = []
        var cancellations = 0
        var finished = 0
    }

    private let events = Events()
    private var changes: [Track] {
        self.events.changes
    }

    private var cancellations: Int {
        self.events.cancellations
    }

    private var finished: Int {
        self.events.finished
    }

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        self.trackA = Track(title: "A", artist: "T", url: try Self.tone(directory.appendingPathComponent("a.caf"), frequency: 220))
        self.trackB = Track(title: "B", artist: "T", url: try Self.tone(directory.appendingPathComponent("b.caf"), frequency: 330))
        self.player = AudioPlayer(installRemoteCommands: false)
        self.player.testing_manualBlendTicks = true
        let events = self.events
        self.player.onAutomixTrackChanged = { track in events.changes.append(track) }
        self.player.onTransitionCancelled = { events.cancellations += 1 }
        self.player.onTrackFinished = { events.finished += 1 }
        let player = self.player!
        self.addTeardownBlock { @MainActor in player.stop() }
    }

    /// 30 s stereo sine at 44.1 kHz.
    private static func tone(_ url: URL, frequency: Double) throws -> URL {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44100 * 30)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0 ..< 2 {
            let samples = buffer.floatChannelData![channel]
            for index in 0 ..< Int(frames) {
                samples[index] = Float(0.2 * sin(2 * .pi * frequency * Double(index) / 44100))
            }
        }
        try file.write(from: buffer)
        return url
    }

    private func plan(_ kind: MixPlan.Kind = .beatmatched(rate: 1.02, transition: .crossfade)) -> MixPlan {
        MixPlan(kind: kind, outgoingStart: 10, incomingStart: 0, length: 8, blendBars: 4, switchTime: 14)
    }

    private func settle() {
        let queue = expectation(description: "queue")
        self.player.testing_afterAudioQueueFlush { queue.fulfill() }
        wait(for: [queue], timeout: 2)
        let main = expectation(description: "main")
        Task { @MainActor in
            await Task.yield()
            main.fulfill()
        }
        wait(for: [main], timeout: 2)
    }

    private func snapshot() -> [AudioPlayer.DeckSnapshot] {
        let done = expectation(description: "snapshot")
        let box = SendableBox<[AudioPlayer.DeckSnapshot]>([])
        self.player.testing_deckSnapshot { decks in
            box.value = decks
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return box.value
    }

    private func startA() {
        let loaded = expectation(description: "load")
        self.player.loadTrack(self.trackA) { _ in loaded.fulfill() }
        wait(for: [loaded], timeout: 5)
        self.player.play()
        self.settle()
    }

    @discardableResult
    private func prepare(_ plan: MixPlan? = nil, track: Track? = nil) -> (UUID, Bool) {
        let token = UUID()
        let done = expectation(description: "prepare")
        let box = SendableBox(false)
        self.player.prepareTransition(
            PreparedTransition(token: token, track: track ?? self.trackB, plan: plan ?? self.plan(), incomingGrid: nil, outgoingGrid: nil)
        ) { ok in
            box.value = ok
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return (token, box.value)
    }

    private func arm(_ plan: MixPlan? = nil) {
        let (token, ok) = self.prepare(plan)
        XCTAssertTrue(ok)
        self.player.armTransition(token: token)
        self.settle()
    }

    private func tick(_ time: Double) {
        self.player.testing_tick(outgoingFileTime: time)
        self.settle()
    }

    private func live(_ decks: [AudioPlayer.DeckSnapshot]) -> AudioPlayer.DeckSnapshot {
        decks.first(where: \.isLive)!
    }

    private func idle(_ decks: [AudioPlayer.DeckSnapshot]) -> AudioPlayer.DeckSnapshot {
        decks.first { !$0.isLive }!
    }

    func testPrepareLoadsIdleDeckWithoutPlaying() {
        self.startA()
        XCTAssertTrue(self.prepare().1)
        let decks = self.snapshot()
        XCTAssertFalse(self.idle(decks).isPlaying)
        XCTAssertEqual(self.idle(decks).fade, 0)
        XCTAssertTrue(self.live(decks).isPlaying)
        XCTAssertEqual(self.player.currentTrack?.title, "A")
    }

    func testArmedBlendRampsEqualPower() {
        self.startA()
        self.arm()
        XCTAssertEqual(self.idle(self.snapshot()).rate, 1.02, accuracy: 1e-6)
        for quarter in 0 ... 4 {
            let progress = Double(quarter) / 4
            self.tick(10 + 8 * progress)
            let decks = self.snapshot()
            let (outgoing, incoming) = (decks[0], decks[1])
            if quarter < 4 {
                XCTAssertEqual(outgoing.fade, Float(cos(progress * .pi / 2)), accuracy: 0.001)
                XCTAssertEqual(incoming.fade, Float(sin(progress * .pi / 2)), accuracy: 0.001)
            }
        }
    }

    func testTransportSwitchesOnceAtSwitchTime() {
        self.startA()
        self.arm()
        self.tick(13)
        XCTAssertEqual(self.changes.count, 0)
        XCTAssertEqual(self.player.currentTrack?.title, "A")
        self.tick(14)
        self.tick(15)
        XCTAssertEqual(self.changes.map(\.title), ["B"])
        XCTAssertEqual(self.player.currentTrack?.title, "B")
        XCTAssertEqual(self.player.liveDeckIndex, 1)
    }

    func testOutgoingCompletionDoesNotCallOnTrackFinished() {
        self.startA()
        self.arm()
        self.tick(11)
        self.player.testing_simulateTrackCompletion()
        self.settle()
        XCTAssertEqual(self.finished, 0)
    }

    func testBassSwapCutMovesFromIncomingToOutgoing() {
        self.startA()
        self.arm(self.plan(.beatmatched(rate: 1, transition: .bassSwap)))
        self.tick(12)
        var decks = self.snapshot()
        XCTAssertFalse(decks[0].lowCut)
        XCTAssertTrue(decks[1].lowCut)
        self.tick(14.5)
        decks = self.snapshot()
        XCTAssertTrue(decks[0].lowCut)
        XCTAssertFalse(decks[1].lowCut)
    }

    func testSeekMidBlendAbortsAndRestoresLiveDeck() {
        self.startA()
        self.arm()
        self.tick(12)
        self.player.seek(to: 5)
        self.settle()
        let decks = self.snapshot()
        XCTAssertEqual(self.live(decks).fade, 1)
        XCTAssertFalse(self.live(decks).lowCut)
        XCTAssertFalse(self.idle(decks).isPlaying)
        XCTAssertEqual(self.cancellations, 1)
        XCTAssertEqual(self.player.currentTrack?.title, "A")
    }

    func testPauseMidBlendThenSeekAborts() {
        self.startA()
        self.arm()
        self.tick(12)
        self.player.pause()
        self.settle()
        XCTAssertFalse(self.snapshot().contains(where: \.isPlaying), "pause freezes both decks")
        self.player.seek(to: 5)
        self.settle()
        let decks = self.snapshot()
        XCTAssertEqual(self.live(decks).fade, 1)
        XCTAssertFalse(self.idle(decks).isPlaying)
        XCTAssertEqual(self.cancellations, 1)
    }

    func testCompleteTransitionNowGivesIncomingFullGain() {
        self.startA()
        self.arm()
        self.tick(11)
        XCTAssertTrue(self.player.isBlending)
        XCTAssertTrue(self.player.completeTransitionNow())
        self.settle()
        let decks = self.snapshot()
        XCTAssertEqual(self.player.liveDeckIndex, 1)
        XCTAssertEqual(self.live(decks).fade, 1)
        XCTAssertFalse(self.idle(decks).isPlaying)
        XCTAssertEqual(self.player.currentTrack?.title, "B")
        XCTAssertEqual(self.changes.count, 1)
        XCTAssertFalse(self.player.isBlending)
        XCTAssertFalse(self.player.completeTransitionNow(), "nothing left to complete")
    }

    func testPrepareFailureLeavesOutgoingPlaying() {
        self.startA()
        let missing = Track(title: "Gone", artist: "T", url: URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).caf"))
        XCTAssertFalse(self.prepare(track: missing).1)
        let decks = self.snapshot()
        XCTAssertTrue(self.live(decks).isPlaying)
        XCTAssertEqual(self.live(decks).fade, 1)
        XCTAssertEqual(self.player.currentTrack?.title, "A")
    }

    func testReplayGainArrivingMidBlendKeepsFadeEnvelope() {
        self.startA()
        self.player.setVolumeNormalizationEnabled(true)
        self.arm()
        self.tick(12)
        let before = self.snapshot()[1]
        self.player.testing_setReplayGain(ReplayGain(trackGainDB: -6), deck: 1)
        self.settle()
        let after = self.snapshot()[1]
        XCTAssertEqual(after.fade, before.fade)
        XCTAssertEqual(after.playerVolume, pow(10, -6.0 / 20), accuracy: 1e-4)
    }

    func testLoadTrackCancelsArmedTransition() {
        self.startA()
        self.arm()
        let loaded = expectation(description: "load")
        self.player.loadTrack(self.trackA) { _ in loaded.fulfill() }
        wait(for: [loaded], timeout: 5)
        self.settle()
        XCTAssertFalse(self.snapshot().contains(where: \.isPlaying))
        XCTAssertEqual(self.cancellations, 1)
        XCTAssertEqual(self.player.liveDeckIndex, 0)
    }

    /// Review finding 3: a cancel followed at once by a new prepare must leave the slot to the new track, so its
    /// ReplayGain read is applied.
    func testReprepareAfterCancelKeepsIncomingTrackSlot() {
        self.startA()
        XCTAssertTrue(self.prepare().1)
        self.player.cancelTransition()
        let second = Track(title: "B2", artist: "T", url: self.trackB.url)
        XCTAssertTrue(self.prepare(track: second).1)
        self.settle()
        XCTAssertEqual(self.player.testing_deckTrackID(1), second.id)
    }

    /// Review finding 4 (spec § Tempo: Play on a stopped player starts the track at its original tempo).
    func testPlayAfterStopStartsAtOriginalTempo() {
        self.startA()
        self.player.setLiveRate(1.04)
        self.settle()
        XCTAssertEqual(self.live(self.snapshot()).rate, 1.04, accuracy: 1e-6)
        self.player.stop()
        self.settle()
        self.player.play()
        self.settle()
        XCTAssertEqual(self.live(self.snapshot()).rate, 1)
        XCTAssertEqual(self.player.liveRate, 1)
    }
}

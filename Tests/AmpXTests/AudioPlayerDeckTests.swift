@testable import AmpX
import AVFoundation
import XCTest

/// DJ mode spec Revision 2 § Audio graph: AudioPlayer on two decks, single-deck behaviour unchanged.
@MainActor
final class AudioPlayerDeckTests: XCTestCase {
    private var player: AudioPlayer!
    private var fixtureURL: URL!

    override func setUpWithError() throws {
        self.player = AudioPlayer(installRemoteCommands: false)
        self.fixtureURL = try XCTUnwrap(Bundle(for: AudioPlayerDeckTests.self).url(forResource: "short", withExtension: "wav"))
    }

    private func load() {
        let loaded = expectation(description: "load")
        self.player.loadTrack(Track(title: "Short", artist: "Test", url: self.fixtureURL)) { _ in loaded.fulfill() }
        wait(for: [loaded], timeout: 5)
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

    private func flush() {
        let done = expectation(description: "flush")
        self.player.testing_afterAudioQueueFlush { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    func testLoadResetsBothDecksToUnity() {
        self.player.testing_configureDeck(0, rate: 1.04, fade: 0.3, lowCut: true)
        self.player.testing_configureDeck(1, rate: 0.97, fade: 0.0, lowCut: true)
        self.load()
        let decks = self.snapshot()
        XCTAssertEqual(decks.count, 2)
        for deck in decks {
            XCTAssertEqual(deck.rate, 1)
            XCTAssertEqual(deck.fade, 1)
            XCTAssertFalse(deck.lowCut)
        }
    }

    func testSingleDeckPlaybackUsesLiveDeckOnly() {
        self.load()
        self.player.play()
        self.flush()
        let decks = self.snapshot()
        XCTAssertEqual(decks.filter(\.isLive).count, 1)
        XCTAssertTrue(decks.first { $0.isLive }?.isPlaying ?? false)
        XCTAssertFalse(decks.first { !$0.isLive }?.isPlaying ?? true)
        self.player.stop()
    }

    func testReplayGainAppliesToLiveDeckPlayer() {
        self.player.setVolumeNormalizationEnabled(true)
        self.player.testing_setReplayGain(ReplayGain(trackGainDB: -6), deck: 0)
        self.flush()
        let decks = self.snapshot()
        XCTAssertEqual(decks[0].playerVolume, pow(10, -6.0 / 20), accuracy: 1e-4)
        XCTAssertEqual(decks[1].playerVolume, 1, accuracy: 1e-6)
    }

    func testBalanceAppliesToBothDecks() {
        self.player.setBalance(-0.5)
        self.flush()
        XCTAssertEqual(self.snapshot().map(\.pan), [-0.5, -0.5])
    }
}

@testable import AmpX
import AVFoundation
import XCTest

/// Drives the real `AudioPlayer` engine through `PlaylistManager` transport commands,
/// using multi-second generated tracks so playback is still running when state is checked.
@MainActor
final class TransportBehaviorTests: XCTestCase {
    private var player: AudioPlayer!
    private var manager: PlaylistManager!
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        self.tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AmpXTransport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.tempDirectory, withIntermediateDirectories: true)

        self.player = AudioPlayer(installRemoteCommands: false, eqSettingsStore: EQSettingsStore(userDefaults: Self.isolatedDefaults()))
        self.player.setVolume(0)
        self.manager = PlaylistManager(
            audioPlayer: self.player,
            restoreBookmarks: false,
            restorePlaylist: false,
            stateStore: PlaylistStateStore(userDefaults: Self.isolatedDefaults()),
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        self.player.onTrackFinished = { [weak manager] in manager?.advanceAfterTrackFinished() }
    }

    override func tearDownWithError() throws {
        self.player?.stop()
        self.player = nil
        self.manager = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    // MARK: - Pause

    func testPauseWhilePausedResumesPlayback() throws {
        try self.loadTracks(count: 1)
        self.playAndSettle(at: 0)

        self.player.pause()
        self.settle()
        XCTAssertFalse(self.player.isPlaying)

        self.player.pause()
        self.settle()
        XCTAssertTrue(self.player.isPlaying, "Pause while paused should resume")
    }

    func testPauseWhileStoppedStaysStopped() throws {
        try self.loadTracks(count: 1)
        self.playAndSettle(at: 0)

        self.player.stop()
        self.settle()
        self.player.pause()
        self.settle()
        XCTAssertFalse(self.player.isPlaying)
    }

    func testPauseToggleResumesFromSeekPositionAndReArmsAutoAdvance() throws {
        try self.loadTracks(count: 1)
        self.playAndSettle(at: 0)
        self.player.pause()
        self.settle()

        self.player.seek(to: 10)
        self.settle()
        XCTAssertFalse(self.player.isPlaying)

        self.player.pause()
        self.settle()
        XCTAssertTrue(self.player.isPlaying)
        XCTAssertGreaterThanOrEqual(self.player.currentTime, 10)

        let armed = expectation(description: "auto-advance state")
        let shouldAdvance = SendableBox(false)
        self.player.testing_shouldAutoAdvance { value in
            shouldAdvance.value = value
            armed.fulfill()
        }
        wait(for: [armed], timeout: 2.0)
        XCTAssertTrue(shouldAdvance.value)
    }

    // MARK: - Clear

    func testClearPlaylistKeepsCurrentTrackPlaying() throws {
        try self.loadTracks(count: 2)
        self.playAndSettle(at: 0)

        self.manager.clearPlaylist()
        self.settle()

        XCTAssertTrue(self.manager.tracks.isEmpty)
        XCTAssertEqual(self.manager.currentIndex, -1)
        XCTAssertTrue(self.player.isPlaying, "Clearing the playlist should not stop playback")
    }

    // MARK: - Next / Previous

    func testNextWhilePlayingPlaysNextTrack() throws {
        try self.loadTracks(count: 3)
        self.playAndSettle(at: 0)

        self.manager.next()
        self.settle()

        XCTAssertEqual(self.manager.currentIndex, 1)
        XCTAssertEqual(self.player.currentTrack?.title, "Track 1")
        XCTAssertTrue(self.player.isPlaying)
    }

    func testNextOnLastTrackWrapsAndKeepsPlaying() throws {
        try self.loadTracks(count: 3)
        self.playAndSettle(at: 2)

        self.manager.next()
        self.settle()

        XCTAssertEqual(self.manager.currentIndex, 0)
        XCTAssertTrue(self.player.isPlaying)
    }

    func testPreviousWhilePlayingPlaysPreviousTrack() throws {
        try self.loadTracks(count: 3)
        self.playAndSettle(at: 1)

        self.manager.previous()
        self.settle()

        XCTAssertEqual(self.manager.currentIndex, 0)
        XCTAssertTrue(self.player.isPlaying)
    }

    func testPreviousWithNoCurrentTrackStartsAtFirstTrack() throws {
        try self.loadTracks(count: 3)
        self.manager.currentIndex = -1

        self.manager.previous()
        self.settle()
        XCTAssertEqual(self.manager.currentIndex, 0)
        XCTAssertTrue(self.player.isPlaying)
    }

    // MARK: - Shuffle

    func testShuffleNextVisitsEveryTrackOnceThenKeepsPlaying() throws {
        try self.loadTracks(count: 5)
        self.playAndSettle(at: 0)
        self.manager.shuffleEnabled = true

        var visited: [Int] = [self.manager.currentIndex]
        for _ in 0 ..< 4 {
            self.manager.next()
            self.settle()
            XCTAssertTrue(self.player.isPlaying)
            visited.append(self.manager.currentIndex)
        }
        XCTAssertEqual(Set(visited), Set(0 ..< 5), "Shuffle should visit every track: \(visited)")

        // Manual next past the end of the shuffle order starts a new order rather than stopping.
        self.manager.next()
        self.settle()
        XCTAssertTrue(self.player.isPlaying)
    }

    func testShufflePreviousReturnsToPreviouslyPlayedTrack() throws {
        try self.loadTracks(count: 5)
        self.playAndSettle(at: 0)
        self.manager.shuffleEnabled = true

        self.manager.next()
        self.settle()
        let second = self.manager.currentIndex
        self.manager.next()
        self.settle()

        self.manager.previous()
        self.settle()
        XCTAssertEqual(self.manager.currentIndex, second)
        XCTAssertTrue(self.player.isPlaying)
    }

    func testEnablingShuffleMidPlaylistDoesNotReplayCurrentTrack() throws {
        try self.loadTracks(count: 5)
        self.playAndSettle(at: 0)
        self.manager.next()
        self.settle()
        self.manager.next()
        self.settle()
        let current = self.manager.currentIndex

        self.manager.shuffleEnabled = true
        self.manager.next()
        self.settle()

        XCTAssertNotEqual(self.manager.currentIndex, current)
        XCTAssertTrue(self.player.isPlaying)
    }

    // MARK: - Helpers

    private nonisolated static func isolatedDefaults() -> UserDefaults {
        let suite = "AmpXTransportTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func loadTracks(count: Int) throws {
        self.manager.tracks = try (0 ..< count).map { index in
            let url = self.tempDirectory.appendingPathComponent("track-\(index).wav")
            try Self.writeSilentWAV(to: url, seconds: 20)
            return Track(title: "Track \(index)", artist: "Test", url: url)
        }
    }

    private func playAndSettle(at index: Int) {
        self.manager.playTrack(at: index)
        self.settle()
        XCTAssertEqual(self.manager.currentIndex, index)
        XCTAssertTrue(self.player.isPlaying, "Track \(index) should be playing")
    }

    /// Lets load → main-actor completion → play → main-actor publish chains finish.
    private func settle() {
        for _ in 0 ..< 4 {
            self.waitForAudioQueue()
            waitForMainQueue(after: 0.05)
        }
    }

    private func waitForAudioQueue() {
        guard let player else { return }
        let flushed = expectation(description: "audio queue flush")
        player.testing_afterAudioQueueFlush { flushed.fulfill() }
        wait(for: [flushed], timeout: 5.0)
    }

    private static func writeSilentWAV(to url: URL, seconds: Double) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let frames = AVAudioFrameCount(44100 * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }
}

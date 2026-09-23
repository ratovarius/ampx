@testable import AmpX
import AVFoundation
import XCTest

@MainActor
final class AudioPlayerTests: XCTestCase {
    private var player: AudioPlayer!
    private var fixtureURL: URL!

    override func setUpWithError() throws {
        self.player = AudioPlayer(installRemoteCommands: false)
        self.fixtureURL = try XCTUnwrap(
            Bundle(for: AudioPlayerTests.self).url(forResource: "short", withExtension: "wav")
        )
    }

    private func waitForLoad(_ track: Track, timeout: TimeInterval = 5.0) -> Bool {
        let loadExpectation = expectation(description: "loadTrack-\(UUID().uuidString)")
        let outcome = SendableBox(false)
        self.player.loadTrack(track) { loaded in
            outcome.value = loaded
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: timeout)
        return outcome.value
    }

    private func waitForShouldAutoAdvance(timeout: TimeInterval = 2.0) -> Bool {
        let autoAdvanceExpectation = expectation(description: "shouldAutoAdvance-\(UUID().uuidString)")
        let outcome = SendableBox(false)
        self.player.testing_shouldAutoAdvance { result in
            outcome.value = result
            autoAdvanceExpectation.fulfill()
        }
        wait(for: [autoAdvanceExpectation], timeout: timeout)
        return outcome.value
    }

    private func waitBriefly(_ seconds: TimeInterval = 0.3) {
        let expectation = expectation(description: "brief wait")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            expectation.fulfill()
        }
        waitForExpectations(timeout: seconds + 1.0)
    }

    func testLoadTrackSucceedsForValidWAV() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        XCTAssertEqual(self.player.currentTrack?.title, "Short")
        XCTAssertGreaterThan(self.player.duration, 0)
    }

    func testLoadTrackFailsForMissingFile() {
        let track = Track(title: "Missing", artist: "Test", url: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).wav"))
        XCTAssertFalse(self.waitForLoad(track))
        XCTAssertNil(self.player.currentTrack)
        XCTAssertEqual(self.player.duration, 0)
    }

    func testLoadTrackFailureAfterSuccessfulLoadClearsState() {
        let valid = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(valid))
        XCTAssertGreaterThan(self.player.duration, 0)

        let missing = Track(title: "Missing", artist: "Test", url: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).wav"))
        XCTAssertFalse(self.waitForLoad(missing))
        XCTAssertNil(self.player.currentTrack)
        XCTAssertEqual(self.player.duration, 0)
    }

    func testPlayDoesNothingAfterFailedLoad() {
        let track = Track(title: "Missing", artist: "Test", url: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).wav"))
        XCTAssertFalse(self.waitForLoad(track))
        self.player.play()
        self.waitBriefly()
        XCTAssertFalse(self.player.isPlaying)
    }

    func testStaleLoadCompletionIgnored() {
        let first = Track(title: "First", artist: "Test", url: fixtureURL)
        let second = Track(title: "Second", artist: "Test", url: fixtureURL)

        let firstExpectation = expectation(description: "first load completion")
        let firstLoadOutcome = SendableBox<Bool?>(nil)
        self.player.loadTrack(first) { success in
            firstLoadOutcome.value = success
            firstExpectation.fulfill()
        }

        XCTAssertTrue(self.waitForLoad(second))
        wait(for: [firstExpectation], timeout: 5.0)
        XCTAssertEqual(self.player.currentTrack?.title, "Second")
        XCTAssertEqual(firstLoadOutcome.value, false)
    }

    func testSeekWhilePlayingPreservesAutoAdvance() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))

        self.player.testing_markAsPlayingForTests()
        self.waitBriefly(0.2)

        self.player.seek(to: 0.05)
        self.waitBriefly(0.3)

        XCTAssertTrue(self.waitForShouldAutoAdvance())
    }

    func testPlayEnablesAutoAdvanceForLoadedTrack() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.play()
        self.waitBriefly(0.3)
        XCTAssertTrue(self.waitForShouldAutoAdvance())
    }

    func testPlayOrResumeResumesAfterPauseWithoutRestarting() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.testing_setPlaybackUIStateForTests(isPlaying: false, currentTime: 0.15)

        self.player.playOrResume()
        XCTAssertEqual(self.player.testing_lastTransportAction, .resume)
    }

    func testTogglePlayPauseResumesAfterPause() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.testing_setPlaybackUIStateForTests(isPlaying: true, currentTime: 0.15)

        self.player.togglePlayPause()
        XCTAssertEqual(self.player.testing_lastTransportAction, .pause)

        self.player.testing_setPlaybackUIStateForTests(isPlaying: false, currentTime: 0.15)
        self.player.togglePlayPause()
        XCTAssertEqual(self.player.testing_lastTransportAction, .resume)
    }

    func testPlayOrRestartResumesWhenPausedAndStartsWhenStopped() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))

        self.player.testing_setPlaybackUIStateForTests(isPlaying: false, currentTime: 0.15)
        self.player.playOrRestart()
        XCTAssertEqual(self.player.testing_lastTransportAction, .resume)

        self.player.testing_setPlaybackUIStateForTests(isPlaying: false, currentTime: 0)
        self.player.playOrRestart()
        XCTAssertEqual(self.player.testing_lastTransportAction, .play)
    }

    func testPlayOrRestartSeeksToStartInsteadOfPausingWhilePlaying() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.testing_setPlaybackUIStateForTests(isPlaying: true, currentTime: 0.15)

        self.player.playOrRestart()
        XCTAssertNotEqual(self.player.testing_lastTransportAction, .pause)
    }

    func testPlayAfterPauseRestartsFromBeginning() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.testing_setPlaybackUIStateForTests(isPlaying: false, currentTime: 0.15)

        self.player.play()
        XCTAssertEqual(
            self.player.testing_lastTransportAction,
            .play,
            "play() intentionally restarts; UI must use playOrResume/togglePlayPause"
        )
    }

    func testPlayOrResumeStartsFromBeginningOnFreshTrack() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.playOrResume()
        self.waitBriefly(0.1)
        XCTAssertEqual(self.player.testing_lastTransportAction, .play)
    }

    func testRapidLoadsReusePlayerNode() {
        let first = Track(title: "First", artist: "Test", url: fixtureURL)
        let second = Track(title: "Second", artist: "Test", url: fixtureURL)

        XCTAssertTrue(self.waitForLoad(first))

        let identityExpectation = expectation(description: "player node identity")
        let firstIdentity = SendableBox<ObjectIdentifier?>(nil)
        self.player.testing_playerNodeIdentity { identity in
            firstIdentity.value = identity
            identityExpectation.fulfill()
        }
        wait(for: [identityExpectation], timeout: 2.0)
        XCTAssertNotNil(firstIdentity.value)

        XCTAssertTrue(self.waitForLoad(second))

        let secondIdentityExpectation = expectation(description: "player node identity after reload")
        let secondIdentity = SendableBox<ObjectIdentifier?>(nil)
        self.player.testing_playerNodeIdentity { identity in
            secondIdentity.value = identity
            secondIdentityExpectation.fulfill()
        }
        wait(for: [secondIdentityExpectation], timeout: 2.0)

        XCTAssertEqual(firstIdentity.value, secondIdentity.value)
        XCTAssertEqual(self.player.currentTrack?.title, "Second")
    }

    func testEngineReportsRunningAfterSetup() {
        XCTAssertTrue(self.player.engineIsRunning)
    }

    func testResumeRestartsEngineAfterItWasStopped() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.seek(to: 0.1)
        self.waitBriefly(0.2)

        let stopExpectation = expectation(description: "engine stopped")
        self.player.testing_stopEngineForTests {
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 2.0)
        XCTAssertFalse(self.player.engineIsRunning)

        self.player.resume()
        self.waitBriefly(0.3)

        XCTAssertTrue(self.player.engineIsRunning)
        XCTAssertEqual(self.player.testing_lastTransportAction, .resume)
    }

    func testAutoPreampUpdatesDisplayedPreampValue() {
        self.player.setEQPreamp(0.25)
        self.player.setEQAutoEnabled(true)
        self.player.setEQBand(0, gain: 12)

        XCTAssertLessThan(self.player.eqPreampValue, 0, "AUTO compensation should lower displayed preamp")
    }

    func testDisablingAutoRestoresManualPreampValue() {
        self.player.setEQPreamp(0.5)
        self.player.setEQAutoEnabled(true)
        self.player.setEQBand(0, gain: 12)
        XCTAssertNotEqual(self.player.eqPreampValue, 0.5)

        self.player.setEQAutoEnabled(false)
        XCTAssertEqual(self.player.eqPreampValue, 0.5, accuracy: 0.001)
    }

    func testPlaybackTimeSnapshotReturnsTimeWhilePlaying() throws {
        // Needs a file still playing after the wait: a finished track now stops the node
        // and its clock, so the 0.1 s `short.wav` fixture would read back 0.
        let url = try Self.makeSilentWAVFixture(durationSeconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let track = Track(title: "Long enough", artist: "Test", url: url)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.play()
        self.waitBriefly(0.4)

        let snapshotExpectation = expectation(description: "playback time snapshot")
        self.player.testing_playbackTimeSnapshot { time in
            XCTAssertGreaterThan(time ?? 0, 0.05)
            snapshotExpectation.fulfill()
        }
        wait(for: [snapshotExpectation], timeout: 2.0)
    }

    func testPauseUpdatesPlayingState() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.play()
        self.waitBriefly(0.2)
        self.player.pause()
        waitForMainQueue()
        XCTAssertFalse(self.player.isPlaying)
        XCTAssertEqual(self.player.testing_lastTransportAction, .pause)
    }

    func testStopResetsPlaybackState() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.testing_setPlaybackUIStateForTests(isPlaying: true, currentTime: 0.2)
        self.player.stop()
        waitForMainQueue(after: 0.2)
        XCTAssertFalse(self.player.isPlaying)
        XCTAssertEqual(self.player.currentTime, 0)
    }

    func testTrackCompletionResetsToStoppedState() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.testing_markAsPlayingForTests()
        self.player.testing_setPlaybackUIStateForTests(isPlaying: true, currentTime: 0.2)

        self.player.testing_simulateTrackCompletion()
        waitForMainQueue(after: 0.2)

        XCTAssertFalse(self.player.isPlaying)
        XCTAssertEqual(self.player.currentTime, 0, "A finished track should rewind like stop() does")

        self.player.playOrResume()
        self.waitBriefly(0.1)
        XCTAssertEqual(
            self.player.testing_lastTransportAction,
            .play,
            "Play after a finished track must reschedule the file, not resume a node with nothing queued"
        )
    }

    func testPlayAfterNaturalCompletionReplaysFromStartAndFinishesAgain() throws {
        let url = try Self.makeSilentWAVFixture(durationSeconds: 0.4)
        defer { try? FileManager.default.removeItem(at: url) }
        let track = Track(title: "Blip", artist: "Test", url: url)
        XCTAssertTrue(self.waitForLoad(track))

        self.player.play()
        try self.requirePlaybackStarted()
        XCTAssertTrue(self.waitForIsPlaying(false, timeout: 5.0), "Playback should finish on its own")
        XCTAssertEqual(self.player.currentTime, 0)

        // Idle long enough that a node clock left running would exceed the file's duration.
        self.waitBriefly(0.6)

        self.player.playOrResume()
        XCTAssertTrue(self.waitForIsPlaying(true, timeout: 2.0), "Play after completion should start again")
        self.waitBriefly(0.1)
        XCTAssertLessThan(
            self.player.currentTime,
            self.player.duration,
            "Clock must restart from the file, not continue from wall time"
        )
        XCTAssertTrue(
            self.waitForIsPlaying(false, timeout: 5.0),
            "Replayed track should finish again instead of running forever"
        )
    }

    func testPlayAfterSeekWhileStoppedKeepsPlayingAndDoesNotAdvance() throws {
        let url = try Self.makeSilentWAVFixture(durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(at: url) }
        let track = Track(title: "Silence", artist: "Test", url: url)
        XCTAssertTrue(self.waitForLoad(track))
        let finishedCount = SendableBox(0)
        self.player.onTrackFinished = { finishedCount.value += 1 }

        // Schedules a segment without playing it; Play's node stop then fires its completion.
        self.player.seek(to: 0)
        self.player.playOrResume()
        try self.requirePlaybackStarted()
        self.waitBriefly(0.3)

        XCTAssertTrue(self.player.isPlaying, "A stale seek completion must not stop the new playback")
        XCTAssertEqual(finishedCount.value, 0, "A stale seek completion must not advance the playlist")
    }

    /// Waits for playback to start, skipping the test on machines without a usable output
    /// device (the engine cannot start, so `.dataPlayedBack` completions never fire).
    private func requirePlaybackStarted(timeout: TimeInterval = 2.0) throws {
        if self.waitForIsPlaying(true, timeout: timeout) {
            return
        }
        if !self.player.engineIsRunning {
            throw XCTSkip("Audio engine could not start; no output device available")
        }
        XCTFail("Playback should start")
    }

    func testSetVolumeClampsToValidRange() {
        self.player.setVolume(1.5)
        XCTAssertEqual(self.player.volume, 1.0)
        self.player.setVolume(-0.25)
        XCTAssertEqual(self.player.volume, 0)
        self.player.setVolume(0.5)
        XCTAssertEqual(self.player.volume, 0.5)
    }

    func testSetEQBandUpdatesPublishedValue() {
        self.player.setEQBand(0, gain: 6)
        XCTAssertEqual(self.player.eqBandValues[0], 0.5, accuracy: 0.001)
    }

    func testSetEQEnabledUpdatesPublishedState() {
        self.player.setEQEnabled(false)
        XCTAssertFalse(self.player.eqEnabled)
        self.player.setEQEnabled(true)
        XCTAssertTrue(self.player.eqEnabled)
    }

    func testSetEQPreampUpdatesManualValue() {
        self.player.setEQPreamp(0.25)
        XCTAssertEqual(self.player.eqPreampValue, 0.25, accuracy: 0.001)
    }

    func testSeekWhilePausedUpdatesCurrentTime() {
        let track = Track(title: "Short", artist: "Test", url: fixtureURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.seek(to: 0.05)
        let seekExpectation = expectation(description: "seek processed")
        self.player.testing_afterAudioQueueFlush {
            seekExpectation.fulfill()
        }
        wait(for: [seekExpectation], timeout: 2.0)
        waitForMainQueue()
        XCTAssertEqual(self.player.currentTime, 0.05, accuracy: 0.01)
        XCTAssertFalse(self.player.isPlaying)
    }

    /// AVAudioPlayerNode's sampleTime is relative to the scheduled segment start.
    /// After seek, absolute UI time must be offset + sampleTime — otherwise the
    /// ~10 Hz timer snaps the slider/time display back toward zero while audio
    /// correctly continues from the seek point.
    func testSeekWhilePlayingSnapshotIncludesSegmentOffset() throws {
        let longURL = try Self.makeSilentWAVFixture(durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(at: longURL) }

        let track = Track(title: "Long", artist: "Test", url: longURL)
        XCTAssertTrue(self.waitForLoad(track))
        self.player.play()
        self.waitBriefly(0.1)

        self.player.seek(to: 1.0)
        let seekExpectation = expectation(description: "seek processed")
        self.player.testing_afterAudioQueueFlush {
            seekExpectation.fulfill()
        }
        wait(for: [seekExpectation], timeout: 2.0)
        waitForMainQueue()
        self.waitBriefly(0.15)

        let snapshotExpectation = expectation(description: "post-seek snapshot")
        let snapshot = SendableBox<TimeInterval?>(nil)
        self.player.testing_playbackTimeSnapshot { time in
            snapshot.value = time
            snapshotExpectation.fulfill()
        }
        wait(for: [snapshotExpectation], timeout: 2.0)

        guard let time = snapshot.value else {
            XCTFail("Expected a post-seek playback time snapshot")
            return
        }
        XCTAssertGreaterThanOrEqual(
            time,
            0.9,
            "Engine snapshot after seek must report absolute file time, not segment-relative ~0"
        )
        XCTAssertGreaterThanOrEqual(
            self.player.currentTime,
            0.9,
            "Published currentTime must stay near the seek target after timer ticks"
        )
    }

    /// Polls `isPlaying` (published from the audio queue) until it matches `expected`.
    private func waitForIsPlaying(_ expected: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if self.player.isPlaying == expected {
                return true
            }
            self.waitBriefly(0.05)
        }
        return self.player.isPlaying == expected
    }

    private static func makeSilentWAVFixture(durationSeconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("winamp-seek-\(UUID().uuidString).wav")
        let sampleRate = 44100.0
        let frameCount = AVAudioFrameCount(durationSeconds * sampleRate)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        try file.write(from: buffer)
        return url
    }
}

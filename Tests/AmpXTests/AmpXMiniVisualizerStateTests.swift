@testable import AmpX
import XCTest

final class AmpXMiniVisualizerStateTests: XCTestCase {
    func testSilentFrameMatchesRendererDimensionsAndParks() {
        var state = AmpXMiniVisualizerState()
        let frame = state.update(AmpXMiniAudioSnapshot(), at: 10)

        self.assertSilent(frame)
        XCTAssertEqual(frame.spectrum.count, 32)
        XCTAssertEqual(frame.peaks.count, 32)
        XCTAssertEqual(frame.trails.count, 32)
        XCTAssertEqual(frame.history, Array(repeating: 0, count: 4096))
        XCTAssertLessThanOrEqual(frame.waveform.count, 512)
        XCTAssertEqual(frame.elapsed, 0)
    }

    func testMetersMapPCMToMinus72ThroughZeroDBFSIndependently() {
        var state = AmpXMiniVisualizerState()
        var snapshot = self.snapshot()
        snapshot.rms = SIMD2(1, 0.1)
        snapshot.peak = SIMD2(1, 0.5)
        let frame = state.update(snapshot, at: 0)

        XCTAssertEqual(frame.meterLevels.x, 1, accuracy: 0.00001)
        XCTAssertEqual(frame.meterLevels.y, 52.0 / 72, accuracy: 0.00001)
        XCTAssertEqual(frame.meterPeaks.x, 1, accuracy: 0.00001)
        XCTAssertEqual(frame.meterPeaks.y, 0.9163806, accuracy: 0.00001)
    }

    func testMetersClampSilenceFloorAndOverload() {
        var state = AmpXMiniVisualizerState()
        var snapshot = self.snapshot()
        snapshot.rms = SIMD2(0, 0.0001)
        snapshot.peak = SIMD2(2, 0)
        let frame = state.update(snapshot, at: 0)

        XCTAssertEqual(frame.meterLevels, .zero)
        XCTAssertEqual(frame.meterPeaks, SIMD2(1, 0))
    }

    func testStereoMetersRespondToAnAttackWithinOneFrameAndReleaseBetweenBeats() {
        var state = AmpXMiniVisualizerState()
        _ = state.update(self.snapshot(level: 0), at: 0)
        var hit = self.snapshot(sequence: 2, time: 0.01, level: 0)
        hit.rms = SIMD2(0.5, 0)
        hit.peak = SIMD2(0.8, 0)
        _ = state.update(hit, at: 0.01)
        let attack = state.update(hit, at: 0.01 + 1.0 / 60)
        XCTAssertGreaterThan(attack.meterLevels.x, 0.7, "the body must respond to a beat, not just its peak marker")
        XCTAssertEqual(attack.meterLevels.y, 0, "silent right channel must stay still")
        XCTAssertEqual(attack.spectrum.max(), 0, "meter response comes from PCM, not spectrum")

        _ = state.update(hit, at: 0.1)
        let quiet = self.snapshot(sequence: 3, time: 0.1, level: 0)
        _ = state.update(quiet, at: 0.1)
        let released = state.update(quiet, at: 0.2)
        XCTAssertLessThan(released.meterLevels.x, 0.2, "body must fall between beats")
        XCTAssertGreaterThan(released.meterPeaks.x, released.meterLevels.x, "peak hold remains independent")
    }

    func testWaveformReductionPreservesOppositeImpulsesInTemporalOrder() {
        var state = AmpXMiniVisualizerState()
        var snapshot = self.snapshot()
        snapshot.waveformLeft = Array(repeating: 0, count: 2048)
        snapshot.waveformLeft[5] = 1
        snapshot.waveformLeft[6] = -0.8
        snapshot.waveformLeft[2047] = 0.6
        let frame = state.update(snapshot, at: 0)

        XCTAssertEqual(frame.waveform.count, 512)
        XCTAssertEqual(Array(frame.waveform.prefix(2)), [1, -0.8])
        XCTAssertEqual(frame.waveform.last, 0.6)
    }

    func testWaveformKeepsPhaseAndDoesNotCancelAntiphaseStereo() {
        var state = AmpXMiniVisualizerState()
        var snapshot = self.snapshot()
        snapshot.waveformLeft = [0, 0.5, 1, 0.5, 0, -0.5, -1, -0.5]
        snapshot.waveformRight = snapshot.waveformLeft.map { -$0 }
        let frame = state.update(snapshot, at: 0)

        XCTAssertEqual(frame.waveform, snapshot.waveformLeft)
    }

    func testRightOnlyWaveformSurvivesAndNeverExceedsParticleBudget() {
        var state = AmpXMiniVisualizerState()
        var snapshot = self.snapshot()
        snapshot.waveformLeft = Array(repeating: 0, count: 1025)
        snapshot.waveformRight = Array(repeating: 0, count: 1025)
        snapshot.waveformRight[513] = -1
        let frame = state.update(snapshot, at: 0)

        XCTAssertLessThanOrEqual(frame.waveform.count, 512)
        XCTAssertEqual(frame.waveform.min(), -1)
        XCTAssertGreaterThan(frame.particleOpacity, 0)
    }

    func testMalformedSignalsAreSanitizedAndPadded() {
        var state = AmpXMiniVisualizerState()
        var snapshot = self.snapshot()
        snapshot.spectrum = [.nan, .infinity, -.infinity, -1, 2, 0.25]
        snapshot.waveformLeft = [.nan, .infinity, -.infinity, -2, 2, -0.25]
        snapshot.rms = SIMD2(.nan, -1)
        snapshot.peak = SIMD2(.infinity, 2)
        let frame = state.update(snapshot, at: 0)

        XCTAssertEqual(frame.spectrum, [0, 0, 0, 0, 1, 0.25] + Array(repeating: 0, count: 26))
        XCTAssertEqual(frame.waveform, [0, 0, 0, -1, 1, -0.25])
        XCTAssertEqual(frame.meterLevels, .zero)
        XCTAssertEqual(frame.meterPeaks, SIMD2(0, 1))
        self.assertFiniteAndClamped(frame)
    }

    func testExcessSpectrumBandsAreIgnored() {
        var state = AmpXMiniVisualizerState()
        var snapshot = self.snapshot()
        snapshot.spectrum = Array(repeating: 0.5, count: 100)
        let frame = state.update(snapshot, at: 0)

        XCTAssertEqual(frame.spectrum, Array(repeating: 0.5, count: 32))
        XCTAssertEqual(frame.history.count, 4096)
    }

    func testAttackAndDecayDependOnElapsedTimeAcrossRefreshRates() {
        let frames = [30, 60, 120].map { rate in
            var state = AmpXMiniVisualizerState()
            _ = state.update(self.snapshot(level: 0), at: 0)
            _ = state.update(self.snapshot(sequence: 2, level: 1), at: 0)
            var output: [AmpXMiniVisualizerFrame] = []
            for tick in 1 ... rate {
                let time = Double(tick) / Double(rate)
                let loud = time < 0.5
                let sample = self.snapshot(sequence: loud ? 2 : 3, time: loud ? 0 : 0.5, level: loud ? 1 : 0)
                let frame = state.update(sample, at: time)
                if tick == rate / 10 || tick == rate / 2 || tick == rate * 7 / 10 || tick == rate {
                    output.append(frame)
                }
            }
            return output
        }

        for index in frames[0].indices {
            self.assertAnimationEqual(frames[0][index], frames[1][index])
            self.assertAnimationEqual(frames[0][index], frames[2][index])
        }
        XCTAssertGreaterThan(frames[0][0].spectrum[0], 0)
        XCTAssertLessThan(frames[0][0].spectrum[0], 1)
        XCTAssertLessThan(frames[0][2].spectrum[0], frames[0][1].spectrum[0])
        XCTAssertGreaterThan(frames[0][2].peaks[0], frames[0][2].spectrum[0])
        XCTAssertGreaterThan(frames[0][2].trails[0], frames[0][2].spectrum[0])
    }

    func testPauseKeepsHistoryWhileEveryTransientSettlesToExactZero() {
        var state = AmpXMiniVisualizerState()
        var snapshot = self.snapshot(level: 1)
        let playing = state.update(snapshot, at: 0)
        snapshot.isPlaying = false
        let paused = state.update(snapshot, at: 0)
        let tail = state.update(snapshot, at: 0.1)
        let settled = state.update(snapshot, at: 3)

        XCTAssertTrue(paused.isActive)
        XCTAssertTrue(tail.isActive)
        XCTAssertGreaterThan(tail.particleOpacity, 0)
        XCTAssertLessThan(tail.waveform[0], playing.waveform[0])
        self.assertSilent(settled)
        XCTAssertEqual(settled.history, playing.history)
    }

    func testSilentPlaybackStaysActive() {
        var state = AmpXMiniVisualizerState()
        let frame = state.update(self.snapshot(level: 0), at: 100)
        XCTAssertTrue(frame.isActive)
        XCTAssertEqual(frame.particleOpacity, 0)
    }

    func testHistoryDoesNotAdvanceForRepeatedSequenceOrDisplayTimeAlone() {
        var state = AmpXMiniVisualizerState()
        var snapshot = self.snapshot(time: 10, level: 0.5)
        let first = state.update(snapshot, at: 100)
        snapshot.time = 1000
        snapshot.spectrum = Array(repeating: 1, count: 32)
        let repeated = state.update(snapshot, at: 200)

        XCTAssertEqual(repeated.history, first.history)
        XCTAssertEqual(repeated.spectrum, first.spectrum)
        XCTAssertEqual(Array(first.history.suffix(32)), Array(repeating: 0.5, count: 32))
    }

    func testHistoryAdvancesOnAudioTimeAndEvictsAfterFourSeconds() {
        var state = AmpXMiniVisualizerState()
        _ = state.update(self.snapshot(time: 10, level: 1), at: 0)
        let early = state.update(self.snapshot(sequence: 2, time: 10.02, level: 1), at: 10)
        XCTAssertEqual(early.history.filter { $0 > 0 }.count, 32, "no row before 31.25 ms of audio")

        let full = state.update(self.snapshot(sequence: 3, time: 13.96875, level: 1), at: 20)
        XCTAssertEqual(full.history, Array(repeating: 1, count: 4096))
        let replaced = state.update(self.snapshot(sequence: 4, time: 14, level: 0), at: 21)
        XCTAssertEqual(Array(replaced.history.suffix(32)), Array(repeating: 0, count: 32))
        XCTAssertEqual(Array(replaced.history.prefix(32)), Array(repeating: 1, count: 32))
        XCTAssertEqual(replaced.history.count, 4096)
    }

    func testHistoryIsOldestFirstWithIndependentFrequencyColumns() {
        var state = AmpXMiniVisualizerState()
        var first = self.snapshot(time: 0, level: 0)
        first.spectrum[0] = 0.25
        var second = self.snapshot(sequence: 2, time: 1.0 / 32, level: 0)
        second.spectrum[31] = 0.75
        _ = state.update(first, at: 0)
        let frame = state.update(second, at: 0)

        XCTAssertEqual(frame.history[4032], 0.25)
        XCTAssertEqual(frame.history[4063], 0)
        XCTAssertEqual(frame.history[4064], 0)
        XCTAssertEqual(frame.history[4095], 0.75)
        XCTAssertEqual(frame.history.prefix(4032).max(), 0)
    }

    func testHistorySamplingIsStableAt30Through120Hz() {
        let histories = [30, 60, 120].map { rate in
            var state = AmpXMiniVisualizerState()
            var frame = AmpXMiniVisualizerFrame()
            for tick in 0 ... rate * 5 {
                let time = Double(tick) / Double(rate)
                frame = state.update(
                    self.snapshot(sequence: UInt64(tick + 1), time: time, level: Float(time / 5)),
                    at: time + 100
                )
            }
            return frame.history
        }
        XCTAssertEqual(histories[0].count, 4096)
        for index in 0 ..< 4096 {
            XCTAssertEqual(histories[0][index], histories[1][index], accuracy: 0.00001)
            XCTAssertEqual(histories[0][index], histories[2][index], accuracy: 0.00001)
        }
        XCTAssertEqual(histories[0][0], 0.20625, accuracy: 0.00001)
        XCTAssertEqual(histories[0][4095], 1, accuracy: 0.00001)
    }

    func testLateSequenceAndRewoundAudioTimeDoNotReplaceValidData() {
        var state = AmpXMiniVisualizerState()
        let first = state.update(self.snapshot(sequence: 10, time: 2, level: 0.5), at: 0)
        let late = state.update(self.snapshot(sequence: 9, time: 3, level: 1), at: 1)
        let rewound = state.update(self.snapshot(sequence: 11, time: 1, level: 1), at: 2)

        XCTAssertEqual(late.history, first.history)
        XCTAssertEqual(rewound.history, first.history)
        XCTAssertEqual(rewound.spectrum, first.spectrum)
        XCTAssertEqual(rewound.waveform, first.waveform)
    }

    func testPauseDoesNotInsertRowsEvenWhenSnapshotSequenceAdvances() {
        var state = AmpXMiniVisualizerState()
        let first = state.update(self.snapshot(time: 0, level: 0.5), at: 0)
        var paused = self.snapshot(sequence: 2, time: 5, level: 1)
        paused.isPlaying = false
        let frame = state.update(paused, at: 5)
        XCTAssertEqual(frame.history, first.history)
    }

    func testResumePreservesHistoryAndRebasesFutureRowsAcrossPause() {
        for rowCount in [33, 128] {
            for pauseDuration in [0.25, 10.0] {
                var state = AmpXMiniVisualizerState()
                var before = AmpXMiniVisualizerFrame()
                var sample = self.snapshot()
                for row in 0 ..< rowCount {
                    let time = Double(row) / 32
                    sample = self.snapshot(
                        sequence: UInt64(row + 1),
                        time: time,
                        level: 0.25 + Float(row) / Float(rowCount - 1) * 0.25
                    )
                    before = state.update(sample, at: time)
                }
                let pausedTime = sample.time + 1
                sample.isPlaying = false
                sample.time = pausedTime
                let paused = state.update(sample, at: pausedTime)
                XCTAssertEqual(paused.history, before.history)

                // The 33-row, 10-second fixture ends at t=1, pauses at t=2 with the
                // same sequence/generation, and resumes with a new sequence at t=12.
                let resumeTime = pausedTime + pauseDuration
                sample = self.snapshot(sequence: UInt64(rowCount + 1), time: resumeTime, level: 0.75)
                let resumed = state.update(sample, at: resumeTime)
                XCTAssertEqual(resumed.history, before.history, "resume must not fabricate rows for the paused interval")
                XCTAssertEqual(resumed.history[(128 - rowCount) * 32], 0.25, "retain the oldest recorded row")
                XCTAssertEqual(resumed.history[4095], 0.5, "retain the newest pre-pause row")
                XCTAssertEqual(resumed.history.count, 4096)

                sample.sequence += 1
                sample.time = resumeTime + 0.02
                let early = state.update(sample, at: sample.time)
                XCTAssertEqual(early.history, before.history, "restart row timing from the accepted resume snapshot")

                sample.sequence += 1
                sample.time = resumeTime + 1.0 / 32
                sample.spectrum = Array(repeating: 0.875, count: 32)
                let advanced = state.update(sample, at: sample.time)
                let expected = Array(before.history.dropFirst(32)) + Array(repeating: Float(0.875), count: 32)
                XCTAssertEqual(advanced.history, expected, "one row of actual post-resume audio should advance normally")
            }
        }
    }

    func testResumeRebaseWaitsForAnAcceptedNewSnapshot() {
        var state = AmpXMiniVisualizerState()
        _ = state.update(self.snapshot(sequence: 1, time: 0, level: 0.25), at: 0)
        var sample = self.snapshot(sequence: 2, time: 1.0 / 32, level: 0.5)
        let before = state.update(sample, at: sample.time)
        sample.isPlaying = false
        _ = state.update(sample, at: 2)

        sample.isPlaying = true
        let duplicate = state.update(sample, at: 12)
        XCTAssertEqual(duplicate.history, before.history)
        sample.sequence = 3
        sample.time = .nan
        let invalid = state.update(sample, at: 12.01)
        XCTAssertEqual(invalid.history, before.history)
        sample.time = 0
        let stale = state.update(sample, at: 12.02)
        XCTAssertEqual(stale.history, before.history)

        sample.time = 12.03
        sample.spectrum = Array(repeating: 0.75, count: 32)
        let resumed = state.update(sample, at: sample.time)
        XCTAssertEqual(resumed.history, before.history, "rejected snapshots must not consume the pending rebase")

        sample.sequence = 4
        sample.time += 1.0 / 32
        let advanced = state.update(sample, at: sample.time)
        XCTAssertEqual(advanced.history, Array(before.history.dropFirst(32)) + Array(repeating: Float(0.75), count: 32))
    }

    func testGenerationResetClearsHistoryAndAllOldSignal() {
        var state = AmpXMiniVisualizerState()
        _ = state.update(self.snapshot(time: 10, level: 1), at: 100)
        var stopped = AmpXMiniAudioSnapshot()
        stopped.generation = 1
        let frame = state.update(stopped, at: 110)

        self.assertSilent(frame)
        XCTAssertEqual(frame.history, Array(repeating: 0, count: 4096))
        XCTAssertEqual(frame.elapsed, 0)

        var next = self.snapshot(time: 0, level: 0.25)
        next.generation = 1
        let resumed = state.update(next, at: 111)
        XCTAssertEqual(resumed.history.filter { $0 > 0 }.count, 32)
        XCTAssertEqual(resumed.waveform, next.waveformLeft)
    }

    func testExplicitResetMatchesFreshState() {
        var state = AmpXMiniVisualizerState()
        _ = state.update(self.snapshot(sequence: 100, time: 50, level: 1), at: 100)
        state.reset()
        let frame = state.update(self.snapshot(time: 0, level: 0.25), at: 500)
        var fresh = AmpXMiniVisualizerState()
        let expected = fresh.update(self.snapshot(time: 0, level: 0.25), at: 500)

        self.assertAnimationEqual(frame, expected)
        XCTAssertEqual(frame.history, expected.history)
        XCTAssertEqual(frame.elapsed, 0)
    }

    func testInvalidAndBackwardDisplayTimesNeverPoisonOrRewindTheClock() {
        var state = AmpXMiniVisualizerState()
        var snapshot = self.snapshot(level: 1)
        _ = state.update(snapshot, at: 10)
        snapshot.isPlaying = false
        _ = state.update(snapshot, at: 10)
        let before = state.update(snapshot, at: 10.1)
        for time in [Double.nan, .infinity, -.infinity, 9] {
            let frame = state.update(snapshot, at: time)
            self.assertAnimationEqual(frame, before)
            XCTAssertEqual(frame.elapsed, before.elapsed)
            self.assertFiniteAndClamped(frame)
        }
        let resumed = state.update(snapshot, at: 10.2)
        XCTAssertEqual(resumed.elapsed, 0.2, accuracy: 0.00001)
        XCTAssertLessThan(resumed.particleOpacity, before.particleOpacity)
    }

    func testHugeClockAndAudioJumpsRemainBoundedAndFinite() {
        var state = AmpXMiniVisualizerState()
        _ = state.update(self.snapshot(time: 0, level: 1), at: 0)
        var snapshot = self.snapshot(sequence: 2, time: Double.greatestFiniteMagnitude, level: 0)
        let jumped = state.update(snapshot, at: Double.greatestFiniteMagnitude)
        self.assertFiniteAndClamped(jumped)
        XCTAssertEqual(jumped.history.count, 4096)
        snapshot.isPlaying = false
        _ = state.update(snapshot, at: Double.greatestFiniteMagnitude)
        state.reset()
        snapshot.time = .nan
        let invalid = state.update(snapshot, at: .nan)
        self.assertFiniteAndClamped(invalid)
    }

    func testPreviouslyReturnedFramesRemainValueSnapshots() {
        var state = AmpXMiniVisualizerState()
        let first = state.update(self.snapshot(level: 1), at: 0)
        var paused = self.snapshot(sequence: 2, time: 1, level: 0)
        paused.isPlaying = false
        _ = state.update(paused, at: 1)
        _ = state.update(paused, at: 5)
        XCTAssertEqual(first.spectrum, Array(repeating: 1, count: 32))
        XCTAssertEqual(first.waveform, [1, -1])
        XCTAssertEqual(Array(first.history.suffix(32)), Array(repeating: 1, count: 32))
        XCTAssertEqual(first.meterLevels, SIMD2(repeating: 1))
    }
}

private extension AmpXMiniVisualizerStateTests {
    private func snapshot(sequence: UInt64 = 1, time: Double = 0, level: Float = 0) -> AmpXMiniAudioSnapshot {
        var snapshot = AmpXMiniAudioSnapshot()
        snapshot.sequence = sequence
        snapshot.time = time
        snapshot.spectrum = Array(repeating: level, count: 32)
        snapshot.waveformLeft = [level, -level]
        snapshot.rms = SIMD2(repeating: level)
        snapshot.peak = SIMD2(repeating: level)
        snapshot.isPlaying = true
        return snapshot
    }

    private func assertSilent(_ frame: AmpXMiniVisualizerFrame, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(frame.isActive, file: file, line: line)
        XCTAssertTrue((frame.spectrum + frame.peaks + frame.trails + frame.waveform).allSatisfy { $0 == 0 }, file: file, line: line)
        XCTAssertEqual(frame.meterLevels, .zero, file: file, line: line)
        XCTAssertEqual(frame.meterPeaks, .zero, file: file, line: line)
        XCTAssertEqual(frame.particleOpacity, 0, file: file, line: line)
    }

    private func assertFiniteAndClamped(_ frame: AmpXMiniVisualizerFrame, file: StaticString = #filePath, line: UInt = #line) {
        let levels = frame.spectrum + frame.peaks + frame.trails + frame.history
            + [frame.meterLevels.x, frame.meterLevels.y, frame.meterPeaks.x, frame.meterPeaks.y, frame.particleOpacity]
        XCTAssertTrue(levels.allSatisfy { $0.isFinite && (0 ... 1).contains($0) }, file: file, line: line)
        XCTAssertTrue(frame.waveform.allSatisfy { $0.isFinite && (-1 ... 1).contains($0) }, file: file, line: line)
        XCTAssertTrue(frame.elapsed.isFinite && frame.elapsed >= 0, file: file, line: line)
    }

    private func assertAnimationEqual(
        _ actual: AmpXMiniVisualizerFrame,
        _ expected: AmpXMiniVisualizerFrame,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualValues = actual.spectrum + actual.peaks + actual.trails + actual.waveform
            + [actual.meterLevels.x, actual.meterLevels.y, actual.meterPeaks.x, actual.meterPeaks.y, actual.particleOpacity]
        let expectedValues = expected.spectrum + expected.peaks + expected.trails + expected.waveform
            + [expected.meterLevels.x, expected.meterLevels.y, expected.meterPeaks.x, expected.meterPeaks.y, expected.particleOpacity]
        XCTAssertEqual(actualValues.count, expectedValues.count, file: file, line: line)
        for (actualValue, expectedValue) in zip(actualValues, expectedValues) {
            XCTAssertEqual(actualValue, expectedValue, accuracy: 0.002, file: file, line: line)
        }
        XCTAssertEqual(actual.isActive, expected.isActive, file: file, line: line)
    }
}

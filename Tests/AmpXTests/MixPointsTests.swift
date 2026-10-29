@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § Mix points and the edge-case table.
final class MixPointsTests: XCTestCase {
    /// 128 BPM from 0 s: a bar is 1.875 s.
    private let bar = 1.875

    private func grid(_ bpm: Double = 128, duration: Double) -> MixGrid {
        MixGrid(segments: [RekordboxBeat(start: 0, bpm: bpm, meter: "4/4", beat: 1)], duration: duration)!
    }

    private func phrases(endBeat: Int, _ entries: [(Int, RekordboxPhraseKind)]) -> RekordboxPhraseAnalysis {
        RekordboxPhraseAnalysis(mood: 1, endBeat: endBeat, phrases: entries.map { RekordboxPhrase(beat: $0.0, kind: $0.1) })
    }

    private func track(
        _ bpm: Double = 128,
        duration: Double = 375,
        trackClass: TrackClass = .steady,
        phrases: RekordboxPhraseAnalysis? = nil
    ) -> AutomixTrack {
        AutomixTrack(duration: duration, trackClass: trackClass, grid: self.grid(bpm, duration: duration), phrases: phrases)
    }

    private func settings(_ method: MixPointMethod = .lastPhrase, transition: TransitionStyle = .crossfade) -> AutomixSettings {
        var settings = AutomixSettings()
        settings.mixPoints = method
        settings.transition = transition
        return settings
    }

    private func plan(
        _ a: AutomixTrack,
        _ b: AutomixTrack,
        position: Double = 0,
        settings: AutomixSettings? = nil
    ) -> MixPlan? {
        MixPoints.plan(outgoing: a, incoming: b, outgoingRate: 1, outgoingPosition: position, settings: settings ?? self.settings())
    }

    // A: content ends at bar 200 (beat 801, 1-based); outro from bar 184.
    private var outroA: RekordboxPhraseAnalysis {
        self.phrases(endBeat: 801, [(1, .intro), (65, .other), (737, .outro)])
    }

    // MARK: - Content end

    func testContentEndPrefersPhraseEndBeat() {
        let a = self.track(phrases: self.phrases(endBeat: 513, [(1, .intro)]))
        XCTAssertEqual(MixPoints.contentEnd(a), 240, accuracy: 1e-9)
    }

    func testContentEndFallsBackToLastFullBar() {
        XCTAssertEqual(MixPoints.contentEnd(self.track(duration: 376)), 375, accuracy: 1e-9)
    }

    func testContentEndWithoutGridIsDuration() {
        XCTAssertEqual(MixPoints.contentEnd(.unknown(duration: 211)), 211)
    }

    // MARK: - Last Phrase

    func testLastPhrasePicksLast16BarBoundaryThatFits() throws {
        let plan = try XCTUnwrap(self.plan(self.track(), self.track(duration: 300)))
        XCTAssertEqual(plan.kind, .beatmatched(rate: 1, transition: .crossfade))
        XCTAssertEqual(plan.blendBars, 16)
        XCTAssertEqual(plan.outgoingStart, 176 * self.bar, accuracy: 1e-9)
        XCTAssertEqual(plan.length, 16 * self.bar, accuracy: 1e-9)
        XCTAssertEqual(plan.incomingStart, 0, accuracy: 1e-9)
    }

    // MARK: - Intro / Outro

    func testIntroOutroUsesShorterOfIntroAndOutro() throws {
        let b = self.track(duration: 300, phrases: self.phrases(endBeat: 600, [(1, .intro), (65, .intro), (129, .other)]))
        let plan = try XCTUnwrap(self.plan(self.track(phrases: self.outroA), b, settings: self.settings(.introOutro)))
        XCTAssertEqual(plan.blendBars, 16)
        XCTAssertEqual(plan.outgoingStart, 184 * self.bar, accuracy: 1e-9)
        XCTAssertEqual(plan.incomingStart, 16 * self.bar, accuracy: 1e-9, "B's intro ends as A's content ends")
    }

    func testIntroOutro14BarIntroRoundsDownTo12() throws {
        let b = self.track(duration: 300, phrases: self.phrases(endBeat: 600, [(1, .intro), (57, .other)]))
        let plan = try XCTUnwrap(self.plan(self.track(phrases: self.outroA), b, settings: self.settings(.introOutro)))
        XCTAssertEqual(plan.blendBars, 12)
        XCTAssertEqual(plan.outgoingStart, 188 * self.bar, accuracy: 1e-9)
        XCTAssertEqual(plan.incomingStart, 2 * self.bar, accuracy: 1e-9)
    }

    func testIntroOutroCappedByLongestBlend() throws {
        let a = self.track(phrases: self.phrases(endBeat: 801, [(1, .intro), (65, .other), (545, .outro)]))
        let b = self.track(duration: 300, phrases: self.phrases(endBeat: 600, [(1, .intro), (257, .other)]))
        let plan = try XCTUnwrap(self.plan(a, b, settings: self.settings(.introOutro)))
        XCTAssertEqual(plan.blendBars, 32)
    }

    func testIntroOutroFallsBackToLastPhraseWithoutPhrases() throws {
        let plan = try XCTUnwrap(self.plan(self.track(phrases: self.outroA), self.track(duration: 300), settings: self.settings(.introOutro)))
        XCTAssertEqual(plan.blendBars, 16)
        XCTAssertEqual(plan.incomingStart, 0, accuracy: 1e-9)
    }

    func testIntroOutroUnder4BarsFallsBack() throws {
        let b = self.track(duration: 300, phrases: self.phrases(endBeat: 600, [(1, .intro), (9, .other)]))
        let plan = try XCTUnwrap(self.plan(self.track(phrases: self.outroA), b, settings: self.settings(.introOutro)))
        XCTAssertEqual(plan.blendBars, 16, "Last Phrase")
        XCTAssertEqual(plan.incomingStart, 0, accuracy: 1e-9)
    }

    // MARK: - Plain crossfade

    func testSetChangingOrNoGridGivesPlainCrossfade() throws {
        for trackClass in [TrackClass.set, .changing, .noGrid] {
            for (a, b) in [(self.track(trackClass: trackClass), self.track()), (self.track(), self.track(trackClass: trackClass))] {
                let plan = try XCTUnwrap(self.plan(a, b))
                XCTAssertEqual(plan.kind, .crossfade, "\(trackClass)")
                XCTAssertEqual(plan.length, 6, accuracy: 1e-9)
                XCTAssertEqual(plan.outgoingStart, MixPoints.contentEnd(a) - 6, accuracy: 1e-9)
                XCTAssertEqual(plan.incomingStart, 0)
            }
        }
    }

    func testUnknownTrackGivesPlainCrossfade() throws {
        let plan = try XCTUnwrap(self.plan(self.track(), .unknown(duration: 200)))
        XCTAssertEqual(plan.kind, .crossfade)
        let reverse = try XCTUnwrap(self.plan(.unknown(duration: 200), self.track()))
        XCTAssertEqual(reverse.kind, .crossfade)
        XCTAssertEqual(reverse.outgoingStart, 194, accuracy: 1e-9)
    }

    func testTempoOutsideClampGivesCrossfade() throws {
        XCTAssertEqual(try XCTUnwrap(self.plan(self.track(128), self.track(138))).kind, .crossfade)
    }

    func testHalfTempoTrackIsOctaveNormalised() throws {
        let plan = try XCTUnwrap(self.plan(self.track(174), self.track(87, duration: 600)))
        XCTAssertEqual(plan.kind, .beatmatched(rate: 1, transition: .crossfade))
    }

    // MARK: - Short incoming track

    func testShortIncomingShortensBlendToAThird() throws {
        var settings = self.settings()
        settings.lastPhraseBlendBars = 32
        let plan = try XCTUnwrap(self.plan(self.track(), self.track(duration: 30 * self.bar), settings: settings))
        XCTAssertEqual(plan.blendBars, 8, "30 bars / 3 = 10, rounded down to 8")
    }

    func testVeryShortIncomingGivesCrossfade() throws {
        XCTAssertEqual(try XCTUnwrap(self.plan(self.track(), self.track(duration: 20))).kind, .crossfade)
    }

    // MARK: - Position already past the mix-out

    func testPositionPastMixOutGivesCrossfadeAtContentEnd() throws {
        let plan = try XCTUnwrap(self.plan(self.track(), self.track(), position: 355))
        XCTAssertEqual(plan.kind, .crossfade)
        XCTAssertEqual(plan.outgoingStart, 369, accuracy: 1e-9)
        XCTAssertEqual(plan.length, 6, accuracy: 1e-9)
    }

    func testPositionInsideLastSixSecondsCrossfadesOverRemaining() throws {
        let plan = try XCTUnwrap(self.plan(self.track(), self.track(), position: 371))
        XCTAssertEqual(plan.outgoingStart, 371, accuracy: 1e-9)
        XCTAssertEqual(plan.length, 4, accuracy: 1e-9)
    }

    func testUnderOneSecondLeftGivesNil() {
        XCTAssertNil(self.plan(self.track(), self.track(), position: 374.5))
    }

    // MARK: - Bass Swap

    func testBassSwapSwitchIsBarNearestMidpoint() throws {
        let plan = try XCTUnwrap(self.plan(self.track(), self.track(), settings: self.settings(transition: .bassSwap)))
        XCTAssertEqual(plan.kind, .beatmatched(rate: 1, transition: .bassSwap))
        XCTAssertEqual(plan.switchTime, 184 * self.bar, accuracy: 1e-9)
    }
}

@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § rekordbox phrases (reading).
final class RekordboxAnalysisFileTests: XCTestCase {
    private let highMood = RekordboxPhraseAnalysis(mood: 1, endBeat: 836, phrases: [
        RekordboxPhrase(beat: 1, kind: .intro), RekordboxPhrase(beat: 65, kind: .other), RekordboxPhrase(beat: 785, kind: .outro),
    ])

    func testHighMoodUnmasked() {
        let ext = ANLZTestData.ext(mood: 1, endBeat: 836, entries: [(1, 1), (65, 2), (785, 6)], masked: false)
        XCTAssertEqual(RekordboxAnalysisFile.phrases(ext: ext), self.highMood)
    }

    func testMaskedEqualsUnmasked() {
        for mood in 1 ... 3 {
            let entries = [(1, 1), (33, 5), (97, 10)]
            let plain = RekordboxAnalysisFile.phrases(ext: ANLZTestData.ext(mood: mood, endBeat: 400, entries: entries, masked: false))
            let masked = RekordboxAnalysisFile.phrases(ext: ANLZTestData.ext(mood: mood, endBeat: 400, entries: entries, masked: true))
            XCTAssertNotNil(plain, "mood \(mood)")
            XCTAssertEqual(masked, plain, "mood \(mood)")
        }
    }

    func testMidAndLowMoodOutroIsKindTen() throws {
        for mood in [2, 3] {
            let ext = ANLZTestData.ext(mood: mood, endBeat: 300, entries: [(1, 1), (129, 6), (257, 10)], masked: true)
            let analysis = try XCTUnwrap(RekordboxAnalysisFile.phrases(ext: ext))
            XCTAssertEqual(analysis.phrases.map(\.kind), [.intro, .other, .outro], "mood \(mood)")
            XCTAssertEqual(analysis.mood, mood)
            XCTAssertEqual(analysis.endBeat, 300)
        }
    }

    func testRejectsCorruptSections() {
        XCTAssertNil(RekordboxAnalysisFile.phrases(ext: ANLZTestData.ext(mood: 1, endBeat: 10, entries: [(1, 1)], masked: false, count: 5)))
        XCTAssertNil(RekordboxAnalysisFile.phrases(ext: ANLZTestData.ext(mood: 7, endBeat: 10, entries: [(1, 1)], masked: false)))
        XCTAssertNil(RekordboxAnalysisFile.phrases(ext: ANLZTestData.ext(mood: 1, endBeat: 10, entries: [], masked: false)))
        XCTAssertNil(RekordboxAnalysisFile.phrases(ext: ANLZTestData.file([ANLZTestData.section("PCOB", headerLength: 12, body: [0])])))
        XCTAssertNil(RekordboxAnalysisFile.phrases(ext: Data("PMAI".utf8)))
        XCTAssertNil(RekordboxAnalysisFile.phrases(ext: Data()))
    }

    func testTrackPathIsNFC() {
        let nfd = "/Users/x/Music/DJ/Mu\u{301}sica/Re\u{301}mix #1.mp3"
        XCTAssertEqual(
            RekordboxAnalysisFile.trackPath(dat: ANLZTestData.dat(path: nfd)),
            "/Users/x/Music/DJ/M\u{FA}sica/R\u{E9}mix #1.mp3"
        )
        XCTAssertNil(RekordboxAnalysisFile.trackPath(dat: ANLZTestData.ext(mood: 1, endBeat: 1, entries: [(1, 1)], masked: false)))
    }

    func testPackRoundTrip() {
        let packed = RekordboxAnalysisFile.pack(self.highMood)
        XCTAssertEqual(RekordboxAnalysisFile.unpack(packed), self.highMood)
        XCTAssertNil(RekordboxAnalysisFile.unpack(Data([9]) + packed.dropFirst()))
        XCTAssertNil(RekordboxAnalysisFile.unpack(packed.dropLast()))
    }
}

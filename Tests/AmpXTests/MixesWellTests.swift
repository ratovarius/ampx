@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § MIXES WELL and § Continue with MIXES WELL.
final class MixesWellTests: XCTestCase {
    private func row(
        _ title: String,
        bpm: Double?,
        camelot: String?,
        genre: String? = "Techno",
        duration: Double = 400,
        available: Bool = true,
        tempoSpread: Double? = 0
    ) -> LibraryRow {
        var row = LibraryRow(
            id: UUID(), rootID: UUID(), url: URL(fileURLWithPath: "/Music/DJ/\(title).mp3"),
            title: title, artist: "Artist", album: "", albumArtist: "",
            genre: genre, trackNumber: nil, duration: duration, fileSize: 1,
            bpm: bpm, musicalKey: nil, camelotKey: camelot, bitrate: 0, bitrateIsDerived: false,
            codec: "mp3", isAvailable: available, searchKey: title.lowercased()
        )
        row.tempoSpread = tempoSpread
        return row
    }

    func testKeyRelations() {
        XCTAssertEqual(MixesWell.keyRelation("8A", "8A"), .same)
        XCTAssertEqual(MixesWell.keyRelation("8A", "9A"), .plusOne)
        XCTAssertEqual(MixesWell.keyRelation("8A", "7A"), .minusOne)
        XCTAssertEqual(MixesWell.keyRelation("12B", "1B"), .plusOne)
        XCTAssertEqual(MixesWell.keyRelation("1A", "12A"), .minusOne)
        XCTAssertEqual(MixesWell.keyRelation("8A", "8B"), .relative)
        XCTAssertNil(MixesWell.keyRelation("8A", "10A"))
        XCTAssertNil(MixesWell.keyRelation("8A", "9B"))
        XCTAssertNil(MixesWell.keyRelation("8A", "x"))
    }

    func testWindowAndRanking() {
        let reference = self.row("ref", bpm: 128, camelot: "8A")
        let plusOne = self.row("plusOne", bpm: 128, camelot: "9A")
        let same = self.row("same", bpm: 130, camelot: "8A")
        let tooFast = self.row("tooFast", bpm: 136, camelot: "8A")
        let relative = self.row("relative", bpm: 120.4, camelot: "8B")

        let result = MixesWell.matches(reference: reference, tempo: 128, rows: [reference, plusOne, same, tooFast, relative])

        XCTAssertEqual(result.matches.map(\.row.title), ["same", "plusOne", "relative"])
        XCTAssertEqual(result.matches.map(\.tags), [["SAME KEY", "+2%"], ["+1", "±0%"], ["REL", "−6%"]])
        XCTAssertEqual(result.chapter, [])
    }

    func testPlusAndMinusOneTieOnTempo() {
        let reference = self.row("ref", bpm: 128, camelot: "8A")
        let minusOne = self.row("minusOne", bpm: 128.5, camelot: "7A")
        let plusOne = self.row("plusOne", bpm: 131, camelot: "9A")
        let result = MixesWell.matches(reference: reference, tempo: 128, rows: [plusOne, minusOne])
        XCTAssertEqual(result.matches.map(\.row.title), ["minusOne", "plusOne"])
        XCTAssertEqual(result.matches.first?.tags, ["−1", "±0%"])
    }

    func testHalfAndDoubleGoToChapter() {
        let reference = self.row("ref", bpm: 140, camelot: "8A")
        let half = self.row("half", bpm: 70, camelot: "8A")
        let double = self.row("double", bpm: 280, camelot: "8A")

        let result = MixesWell.matches(reference: reference, tempo: 140, rows: [half, double])

        XCTAssertEqual(result.matches, [])
        XCTAssertEqual(result.chapter.map(\.row.title), ["double", "half"])
        XCTAssertEqual(result.chapter.first { $0.row.title == "half" }?.tags, ["SAME KEY", "±0%", "½×"])
        XCTAssertEqual(result.chapter.first { $0.row.title == "half" }?.octave, .half)
        XCTAssertEqual(result.chapter.first { $0.row.title == "double" }?.tags, ["SAME KEY", "±0%", "2×"])
    }

    func testExclusions() {
        let reference = self.row("ref", bpm: 128, camelot: "8A")
        let rows = [
            reference,
            self.row("set", bpm: 128, camelot: "8A", genre: "Sets & Mixes"),
            self.row("long", bpm: 128, camelot: "8A", duration: 3600),
            self.row("offline", bpm: 128, camelot: "8A", available: false),
            self.row("noKey", bpm: 128, camelot: nil),
            self.row("noBPM", bpm: nil, camelot: "8A"),
        ]
        let result = MixesWell.matches(reference: reference, tempo: 128, rows: rows)
        XCTAssertEqual(result.matches, [])
        XCTAssertEqual(result.chapter, [])
    }

    func testChangingTrackListedWithVarTag() {
        let reference = self.row("ref", bpm: 128, camelot: "8A")
        let changing = self.row("changing", bpm: 128, camelot: "8A", tempoSpread: 12)
        let result = MixesWell.matches(reference: reference, tempo: 128, rows: [changing])
        XCTAssertEqual(result.matches.first?.tags, ["SAME KEY", "±0%", "VAR"])
    }

    func testUsesGivenTempoNotReferenceBPM() {
        let reference = self.row("ref", bpm: 122, camelot: "8A")
        let candidate = self.row("candidate", bpm: 130, camelot: "8A") // 6.6% from 122, 1.6% from 128
        XCTAssertEqual(MixesWell.matches(reference: reference, tempo: 128, rows: [candidate]).matches.count, 1)
        XCTAssertEqual(MixesWell.matches(reference: reference, tempo: 122, rows: [candidate]).matches.count, 0)
    }

    func testNextPickSkipsChapterChangingAndExcluded() {
        let reference = self.row("ref", bpm: 128, camelot: "8A")
        let top = self.row("top", bpm: 128, camelot: "8A")
        let changing = self.row("changing", bpm: 128.2, camelot: "8A", tempoSpread: 20)
        let noGrid = self.row("noGrid", bpm: 128.3, camelot: "8A", tempoSpread: nil)
        let second = self.row("second", bpm: 129, camelot: "9A")
        let half = self.row("half", bpm: 64, camelot: "8A")
        let pool = [reference, top, changing, noGrid, second, half]

        XCTAssertEqual(MixesWell.nextPick(reference: reference, tempo: 128, pool: pool, excluded: [])?.title, "top")
        XCTAssertEqual(MixesWell.nextPick(reference: reference, tempo: 128, pool: pool, excluded: [top.id])?.title, "second")
    }

    func testNextPickFallsBackToClosestTempoIgnoringKey() {
        let reference = self.row("ref", bpm: 128, camelot: "8A")
        let near = self.row("near", bpm: 126, camelot: "3B")
        let far = self.row("far", bpm: 140, camelot: "3B")
        let set = self.row("set", bpm: 128, camelot: "3B", genre: "Sets & Mixes")
        XCTAssertEqual(MixesWell.nextPick(reference: reference, tempo: 128, pool: [far, near, set], excluded: [])?.title, "near")
    }

    func testNextPickEmptyPool() {
        let reference = self.row("ref", bpm: 128, camelot: "8A")
        let only = self.row("only", bpm: 128, camelot: "8A")
        XCTAssertNil(MixesWell.nextPick(reference: reference, tempo: 128, pool: [reference, only], excluded: [only.id]))
        XCTAssertNil(MixesWell.nextPick(reference: reference, tempo: 128, pool: [], excluded: []))
    }
}

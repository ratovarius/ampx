@testable import AmpX
import XCTest

/// Matching and write planning (rekordbox sync spec § `RekordboxImportPlanner`). No file system.
final class RekordboxImportPlannerTests: XCTestCase {
    private let dj = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
    private let other = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private func roots(caseSensitive: Bool = true) -> [RekordboxRootPath] {
        [
            RekordboxRootPath(id: self.dj, path: "/Music/DJ", caseSensitive: caseSensitive),
            RekordboxRootPath(id: self.other, path: "/Music/Other", caseSensitive: true),
        ]
    }

    private func row(
        _ n: Int,
        root: UUID? = nil,
        _ relativePath: String,
        size: Int64 = 1000,
        duration: Double = 300,
        bpm: Double? = nil,
        key: String? = nil,
        source: AnalysisSource? = nil,
        rating: Int = 0,
        ratingSource: RatingSource? = nil
    ) -> RekordboxRowSnapshot {
        RekordboxRowSnapshot(
            id: self.id(n), rootID: root ?? self.dj, relativePath: relativePath, fileSize: size, duration: duration,
            bpm: bpm, musicalKey: key, analysisSource: source, rating: rating, ratingSource: ratingSource,
            rekordboxPlayCount: 0, label: nil, remixer: nil, composer: nil, grouping: nil, mix: nil, beatGrid: nil
        )
    }

    private func track(
        _ path: String,
        size: Int64? = 1000,
        duration: Double? = 300,
        bpm: Double? = 124,
        tonality: String? = "Am",
        rating: Int? = 0,
        playCount: Int? = 0,
        label: String? = nil,
        remixer: String? = nil,
        beatGrid: [RekordboxBeat] = []
    ) -> RekordboxTrack {
        RekordboxTrack(
            path: path, size: size, duration: duration, bpm: bpm, tonality: tonality, rating: rating, playCount: playCount,
            label: label, remixer: remixer, composer: nil, grouping: nil, mix: nil, beatGrid: beatGrid
        )
    }

    private func plan(
        _ tracks: [RekordboxTrack],
        rows: [RekordboxRowSnapshot],
        roots: [RekordboxRootPath]? = nil,
        source: UUID? = nil
    ) -> RekordboxImportPlan {
        RekordboxImportPlanner.plan(
            RekordboxCollection(productVersion: "7.2.19", tracks: tracks, droppedWithoutLocation: 0),
            fileName: "collection.xml",
            sourceRootID: source ?? self.dj,
            library: RekordboxLibrarySnapshot(roots: roots ?? self.roots(), rows: rows)
        )
    }

    // MARK: - Matching

    func testMatchesByPath() throws {
        let plan = self.plan([self.track("/Music/DJ/Techno/a.mp3", bpm: 126, tonality: "Fm")], rows: [self.row(1, "Techno/a.mp3")])
        XCTAssertEqual(plan.report.matched, 1)
        XCTAssertEqual(plan.report.fileName, "collection.xml")
        let write = try XCTUnwrap(plan.writes.first)
        XCTAssertEqual(write.rowID, self.id(1))
        XCTAssertEqual(write.rootID, self.dj)
        XCTAssertEqual(write.values.bpm, 126)
        XCTAssertEqual(write.values.musicalKey, "Fm")
        XCTAssertEqual(write.values.analysisSource, .rekordbox)
    }

    func testMatchesThroughSymlinkedRoot() {
        // Both sides arrive resolved: the root's path is its resolved URL, the track's path went through the parser.
        let roots = [RekordboxRootPath(id: self.dj, path: "/Volumes/Data/Music/DJ", caseSensitive: true)]
        let plan = self.plan([self.track("/Volumes/Data/Music/DJ/a.mp3", size: 5)], rows: [self.row(1, "a.mp3")], roots: roots)
        XCTAssertEqual(plan.report.matched, 1)
        XCTAssertEqual(plan.writes.map(\.rowID), [self.id(1)])
    }

    func testMatchesCaseInsensitivelyOnCaseInsensitiveRoot() {
        let plan = self.plan(
            [self.track("/music/dj/TECHNO/A.mp3", size: 5)],
            rows: [self.row(1, "Techno/a.mp3")],
            roots: self.roots(caseSensitive: false)
        )
        XCTAssertEqual(plan.report.matched, 1)
        XCTAssertEqual(plan.writes.map(\.rowID), [self.id(1)])
    }

    func testCaseSensitiveRootDoesNotFoldCase() {
        let plan = self.plan([self.track("/Music/DJ/techno/a.mp3", size: 5)], rows: [self.row(1, "Techno/a.mp3")])
        XCTAssertEqual(plan.report.matched, 0)
        XCTAssertEqual(plan.report.unmatched, ["/Music/DJ/techno/a.mp3"])
    }

    func testFallbackBySizeAndDuration() {
        let rows = [self.row(1, "a.mp3", size: 777, duration: 301.2)]
        let near = self.plan([self.track("/Elsewhere/a.mp3", size: 777, duration: 300.4)], rows: rows)
        XCTAssertEqual(near.writes.map(\.rowID), [self.id(1)])
        let far = self.plan([self.track("/Elsewhere/a.mp3", size: 777, duration: 302.5)], rows: rows)
        XCTAssertTrue(far.writes.isEmpty)
        XCTAssertEqual(far.report.unmatched, ["/Elsewhere/a.mp3"])
    }

    func testFallbackIncludesUnavailableRootRows() {
        // Rows of every root are in the snapshot whatever their availability; the fallback sees them all.
        let plan = self.plan([self.track("/Old/Path/b.mp3", size: 42)], rows: [self.row(2, root: self.other, "b.mp3", size: 42)])
        XCTAssertEqual(plan.writes.map(\.rowID), [self.id(2)])
    }

    func testAmbiguousFallbackNotWritten() {
        let rows = [self.row(1, "a.mp3", size: 42), self.row(2, root: self.other, "b.mp3", size: 42)]
        let plan = self.plan([self.track("/Elsewhere/x.mp3", size: 42)], rows: rows)
        XCTAssertTrue(plan.writes.isEmpty)
        XCTAssertEqual(plan.report.ambiguous.map(\.path), ["/Elsewhere/x.mp3"])
        XCTAssertEqual(Set(plan.report.ambiguous.first?.candidates ?? []), ["/Music/DJ/a.mp3", "/Music/Other/b.mp3"])
    }

    func testDuplicateEntriesForOneFileAreAmbiguous() {
        let plan = self.plan(
            [self.track("/Music/DJ/a.mp3", bpm: 120), self.track("/Music/DJ/a.mp3", bpm: 121)],
            rows: [self.row(1, "a.mp3")]
        )
        XCTAssertTrue(plan.writes.isEmpty)
        XCTAssertEqual(plan.report.matched, 0)
        XCTAssertEqual(plan.report.ambiguous.count, 2)
    }

    func testFallbackCopyBeforePathMatchDoesNotStealRow() {
        let copy = self.track("/Music/MUSICA/a.mp3", size: 1000, duration: 300, bpm: 99)
        let own = self.track("/Music/DJ/a.mp3", size: 1000, duration: 300, bpm: 126)
        let plan = self.plan([copy, own], rows: [self.row(1, "a.mp3")])
        XCTAssertEqual(plan.writes.map(\.values.bpm), [126])
        XCTAssertEqual(plan.report.matched, 1)
        XCTAssertEqual(plan.report.unmatched, ["/Music/MUSICA/a.mp3"])
    }

    func testOutsideRootsIsUnmatched() {
        let plan = self.plan([self.track("/Elsewhere/z.mp3", size: 1)], rows: [self.row(1, "a.mp3", size: 2)])
        XCTAssertEqual(plan.report.unmatched, ["/Elsewhere/z.mp3"])
    }

    func testZeroMatchesIsEmptyPlan() {
        let plan = self.plan([self.track("/Elsewhere/z.mp3", size: 1)], rows: [])
        XCTAssertTrue(plan.writes.isEmpty)
        XCTAssertEqual(plan.report.matched, 0)
        XCTAssertEqual(plan.report.updated, 0)
    }

    // MARK: - Values

    func testRekordboxWinsOverFileTag() throws {
        let rows = [self.row(1, "a.mp3", bpm: 120, key: "Am", source: .fileTag)]
        let write = try XCTUnwrap(self.plan([self.track("/Music/DJ/a.mp3", bpm: 124, tonality: "Gm")], rows: rows).writes.first)
        XCTAssertEqual(write.values.bpm, 124)
        XCTAssertEqual(write.values.musicalKey, "Gm")
        XCTAssertEqual(write.values.analysisSource, .rekordbox)
    }

    func testMissingRekordboxValueKeepsExisting() throws {
        let rows = [self.row(1, "a.mp3", bpm: 120, key: "Am", source: .fileTag)]
        let write = try XCTUnwrap(self.plan([self.track("/Music/DJ/a.mp3", bpm: nil, tonality: "Gm")], rows: rows).writes.first)
        XCTAssertEqual(write.values.bpm, 120)
        XCTAssertEqual(write.values.musicalKey, "Gm")
    }

    func testRatingFromRekordbox() throws {
        let write = try XCTUnwrap(self.plan([self.track("/Music/DJ/a.mp3", rating: 4)], rows: [self.row(1, "a.mp3")]).writes.first)
        XCTAssertEqual(write.values.rating, 4)
        XCTAssertEqual(write.values.ratingSource, .rekordbox)
    }

    func testUserRatingIsConflictNotOverwritten() throws {
        let rows = [self.row(1, "a.mp3", rating: 2, ratingSource: .user)]
        let plan = self.plan([self.track("/Music/DJ/a.mp3", rating: 5)], rows: rows)
        let write = try XCTUnwrap(plan.writes.first)
        XCTAssertEqual(write.values.rating, 2)
        XCTAssertEqual(write.values.ratingSource, .user)
        XCTAssertEqual(plan.report.ratingConflicts, [.init(path: "/Music/DJ/a.mp3", library: 2, rekordbox: 5)])
    }

    func testTextFieldsAndPlayCountMirror() throws {
        let track = self.track("/Music/DJ/a.mp3", playCount: 7, label: "Denature Records", remixer: "Âme")
        let write = try XCTUnwrap(self.plan([track], rows: [self.row(1, "a.mp3")]).writes.first)
        XCTAssertEqual(write.values.rekordboxPlayCount, 7)
        XCTAssertEqual(write.values.label, "Denature Records")
        XCTAssertEqual(write.values.remixer, "Âme")
        XCTAssertNil(write.values.composer)
    }

    func testBeatGridEncodedDeterministically() throws {
        let grid = [RekordboxBeat(start: 0.38, bpm: 117, meter: "4/4", beat: 1)]
        let first = try XCTUnwrap(self.plan([self.track("/Music/DJ/a.mp3", beatGrid: grid)], rows: [self.row(1, "a.mp3")]).writes.first)
        let second = try XCTUnwrap(self.plan([self.track("/Music/DJ/a.mp3", beatGrid: grid)], rows: [self.row(1, "a.mp3")]).writes.first)
        XCTAssertEqual(first.values.beatGrid, second.values.beatGrid)
        XCTAssertEqual(try JSONDecoder().decode([RekordboxBeat].self, from: XCTUnwrap(first.values.beatGrid)), grid)
        let empty = try XCTUnwrap(self.plan([self.track("/Music/DJ/a.mp3")], rows: [self.row(1, "a.mp3")]).writes.first)
        XCTAssertNil(empty.values.beatGrid)
    }

    func testSecondPlanOfSameCollectionHasNoWrites() throws {
        let tracks = [
            self.track(
                "/Music/DJ/a.mp3",
                bpm: 126,
                tonality: "Fm",
                rating: 3,
                playCount: 2,
                label: "L",
                beatGrid: [RekordboxBeat(start: 0.1, bpm: 126, meter: "4/4", beat: 1)]
            ),
        ]
        let row = self.row(1, "a.mp3")
        let first = self.plan(tracks, rows: [row])
        let values = try XCTUnwrap(first.writes.first?.values)
        let applied = RekordboxRowSnapshot(
            id: row.id, rootID: row.rootID, relativePath: row.relativePath, fileSize: row.fileSize, duration: row.duration,
            bpm: values.bpm, musicalKey: values.musicalKey, analysisSource: values.analysisSource,
            rating: values.rating, ratingSource: values.ratingSource, rekordboxPlayCount: values.rekordboxPlayCount,
            label: values.label, remixer: values.remixer, composer: values.composer, grouping: values.grouping, mix: values.mix,
            beatGrid: values.beatGrid
        )
        let second = self.plan(tracks, rows: [applied])
        XCTAssertTrue(second.writes.isEmpty)
        XCTAssertEqual(second.report.matched, 1)
        XCTAssertEqual(second.report.updated, 0)
    }

    func testNoLongerInRekordboxScopedToSourceRoot() {
        let rows = [
            self.row(1, "gone.mp3", source: .rekordbox),
            self.row(2, root: self.other, "elsewhere.mp3", source: .rekordbox),
            self.row(3, "tagged.mp3", source: .fileTag),
        ]
        let plan = self.plan([], rows: rows)
        XCTAssertEqual(plan.report.noLongerInRekordbox, ["/Music/DJ/gone.mp3"])
    }
}

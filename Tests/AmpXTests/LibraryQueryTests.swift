@testable import AmpX
import XCTest

/// Pure query semantics (spec: "Index and query semantics").
final class LibraryQueryTests: XCTestCase {
    private func row(
        _ id: Int,
        title: String = "Song",
        artist: String = "Artist",
        album: String = "",
        genre: String? = nil,
        trackNumber: Int? = nil,
        duration: Double = 100,
        bpm: Double? = nil,
        key: String? = nil,
        bitrate: Int = 0,
        available: Bool = true
    ) -> LibraryRow {
        LibraryRow(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
            rootID: UUID(), url: URL(fileURLWithPath: "/Music/\(id).mp3"),
            title: title, artist: artist, album: album, albumArtist: "",
            genre: genre, trackNumber: trackNumber, duration: duration, fileSize: 1000,
            bpm: bpm, musicalKey: key, bitrate: bitrate, bitrateIsDerived: false, codec: "mp3",
            isAvailable: available,
            searchKey: LibraryRow.makeSearchKey(title: title, artist: artist, album: album, albumArtist: "")
        )
    }

    func testMinimalRowSearchAndAbsentFacets() {
        let row = self.row(1, available: false)
        let result = LibraryQuery(search: "ARTIST song").evaluate(rows: [row], snapshotVersion: 1, generation: 2)
        XCTAssertEqual(result.rows.map(\.id), [row.id])
        XCTAssertEqual(result.facets.genres[.absent], 1)
        XCTAssertEqual(result.facets.albums[.absent], 1)
        XCTAssertEqual(result.generation, 2)
        XCTAssertEqual(result.snapshotVersion, 1)
    }

    func testMultiTermFoldedSearch() {
        let rows = [self.row(1, title: "Crazy in Love", artist: "Beyoncé"), self.row(2, title: "Crazy", artist: "Gnarls Barkley")]
        let result = LibraryQuery(search: "  beyonce   CRAZY ").evaluate(rows: rows, snapshotVersion: 0, generation: 0)
        XCTAssertEqual(result.rows.map(\.id), [rows[0].id])
        XCTAssertEqual(LibraryQuery(search: "").evaluate(rows: rows, snapshotVersion: 0, generation: 0).rows.count, 2)
        XCTAssertTrue(LibraryQuery(search: "crazy techno").evaluate(rows: rows, snapshotVersion: 0, generation: 0).rows.isEmpty)
    }

    func testOrWithinFacetAndAcrossFacets() {
        let rows = [
            self.row(1, artist: "A", genre: "Techno"),
            self.row(2, artist: "B", genre: "House"),
            self.row(3, artist: "A", genre: "Trance"),
            self.row(4, artist: "B", genre: "Techno"),
        ]
        var query = LibraryQuery()
        query.genres = [.text("Techno"), .text("House")]
        query.artists = [.text("A")]
        XCTAssertEqual(query.evaluate(rows: rows, snapshotVersion: 0, generation: 0).rows.map(\.id), [rows[0].id])
    }

    func testFacetCountsExcludeOwnSelection() {
        let rows = [
            self.row(1, artist: "A", genre: "Techno"),
            self.row(2, artist: "B", genre: "House"),
            self.row(3, artist: "A", genre: "House"),
        ]
        var query = LibraryQuery()
        query.genres = [.text("Techno")]
        let facets = query.evaluate(rows: rows, snapshotVersion: 0, generation: 0).facets
        // Genre counts ignore the genre selection; artist counts respect it.
        XCTAssertEqual(facets.genres, [.text("Techno"): 1, .text("House"): 2])
        XCTAssertEqual(facets.artists, [.text("A"): 1])
    }

    func testAbsentDistinctFromLiteralNoGenreText() {
        let rows = [self.row(1, genre: nil), self.row(2, genre: "(No Genre)"), self.row(3, genre: "")]
        var query = LibraryQuery()
        query.genres = [.absent]
        let result = query.evaluate(rows: rows, snapshotVersion: 0, generation: 0)
        XCTAssertEqual(result.rows.map(\.id), [rows[0].id, rows[2].id])
        XCTAssertEqual(result.facets.genres, [.absent: 2, .text("(No Genre)"): 1])
    }

    func testCountsIncludeUnavailableRows() {
        let rows = [self.row(1, genre: "Techno", available: false), self.row(2, genre: "Techno")]
        XCTAssertEqual(LibraryQuery().evaluate(rows: rows, snapshotVersion: 0, generation: 0).facets.genres[.text("Techno")], 2)
    }

    func testSortIsTotalOrderWithTieBreakers() {
        let rows = [
            self.row(5, title: "B", artist: "Same", album: "X", trackNumber: 2),
            self.row(4, title: "A", artist: "Same", album: "X", trackNumber: nil),
            self.row(3, title: "Z", artist: "Same", album: "X", trackNumber: 1),
            self.row(2, title: "Same", artist: "Same", album: "W"),
            self.row(1, title: "Same", artist: "Same", album: "W"),
        ]
        let ids = LibraryQuery().evaluate(rows: rows.shuffled(), snapshotVersion: 0, generation: 0).rows.map(\.id)
        XCTAssertEqual(ids, [rows[4].id, rows[3].id, rows[2].id, rows[0].id, rows[1].id])
        for _ in 0 ..< 5 {
            XCTAssertEqual(LibraryQuery().evaluate(rows: rows.shuffled(), snapshotVersion: 0, generation: 0).rows.map(\.id), ids)
        }
    }

    func testPrimaryColumnDirection() {
        let rows = [self.row(1, duration: 300), self.row(2, duration: 100), self.row(3, duration: 200)]
        var query = LibraryQuery(sort: .duration)
        XCTAssertEqual(query.evaluate(rows: rows, snapshotVersion: 0, generation: 0).rows.map(\.duration), [100, 200, 300])
        query.ascending = false
        XCTAssertEqual(query.evaluate(rows: rows, snapshotVersion: 0, generation: 0).rows.map(\.duration), [300, 200, 100])
    }

    func testNilSortValuesLastBothDirections() {
        let rows = [self.row(1, bpm: nil), self.row(2, bpm: 128), self.row(3, bpm: 124)]
        var query = LibraryQuery(sort: .bpm)
        XCTAssertEqual(query.evaluate(rows: rows, snapshotVersion: 0, generation: 0).rows.map(\.bpm), [124, 128, nil])
        query.ascending = false
        XCTAssertEqual(query.evaluate(rows: rows, snapshotVersion: 0, generation: 0).rows.map(\.bpm), [128, 124, nil])
    }

    func testQueryCodableRoundTrip() throws {
        var query = LibraryQuery(search: "acid", sort: .musicalKey, ascending: false)
        query.genres = [.text("Techno"), .absent]
        query.albums = [.absent]
        let decoded = try JSONDecoder().decode(LibraryQuery.self, from: JSONEncoder().encode(query))
        XCTAssertEqual(decoded, query)
    }
}

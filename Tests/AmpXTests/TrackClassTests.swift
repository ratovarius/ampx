@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § Track classes.
final class TrackClassTests: XCTestCase {
    func testClassBoundaries() {
        XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 400, tempoSpread: 0), .steady)
        XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 400, tempoSpread: 0.5), .steady)
        XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 400, tempoSpread: 0.51), .drifting)
        XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 400, tempoSpread: 8), .drifting)
        XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 400, tempoSpread: 8.01), .changing)
        XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 400, tempoSpread: nil), .noGrid)
    }

    func testSetRule() {
        XCTAssertEqual(TrackClass.classify(genre: "sets & mixes", duration: 225, tempoSpread: 0), .set)
        XCTAssertEqual(TrackClass.classify(genre: "Sets & Mixes", duration: 225, tempoSpread: nil), .set)
        XCTAssertEqual(TrackClass.classify(genre: nil, duration: 1800.5, tempoSpread: 0), .set)
        XCTAssertEqual(TrackClass.classify(genre: nil, duration: 1800, tempoSpread: 0), .steady)
        XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 1710, tempoSpread: 0), .steady) // the 28½-min track
    }

    func testRowExposesClass() {
        var row = LibraryRow(
            id: UUID(), rootID: UUID(), url: URL(fileURLWithPath: "/Music/DJ/a.mp3"),
            title: "Song", artist: "Artist", album: "", albumArtist: "",
            genre: "Techno", trackNumber: nil, duration: 400, fileSize: 1,
            bpm: 128, musicalKey: "Am", bitrate: 0, bitrateIsDerived: false,
            codec: "mp3", isAvailable: true, searchKey: "song artist"
        )
        XCTAssertEqual(row.trackClass, .noGrid)
        XCTAssertFalse(row.hasPhrases)
        row.tempoSpread = 12
        XCTAssertEqual(row.trackClass, .changing)
        XCTAssertFalse(row.isSet)
    }
}

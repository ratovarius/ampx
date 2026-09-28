@testable import AmpX
import XCTest

final class RekordboxCollectionParserTests: XCTestCase {
    static func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: RekordboxCollectionParserTests.self).url(
            forResource: "rekordbox-collection",
            withExtension: "xml"
        ))
        return try Data(contentsOf: url)
    }

    private func parsedFixture() throws -> RekordboxCollection {
        try RekordboxCollectionParser.parse(Self.fixtureData())
    }

    private func track(named fragment: String, in collection: RekordboxCollection) throws -> RekordboxTrack {
        try XCTUnwrap(collection.tracks.first { $0.path.contains(fragment) }, fragment)
    }

    func testParsesFixture() throws {
        let collection = try self.parsedFixture()
        XCTAssertEqual(collection.productVersion, "7.2.19")
        XCTAssertEqual(collection.tracks.count, 19)
        XCTAssertEqual(collection.droppedWithoutLocation, 1)
    }

    func testHashInPathIsLiteral() throws {
        let track = try self.track(named: "#DESCONOCIDO", in: self.parsedFixture())
        XCTAssertTrue(track.path.hasSuffix("/EBM & Industrial/#DESCONOCIDO - demoniac puppets.mp3"), track.path)
    }

    func testPathsAreNFC() throws {
        let collection = try self.parsedFixture()
        for track in collection.tracks {
            XCTAssertEqual(track.path, track.path.precomposedStringWithCanonicalMapping)
        }
        // The fixture's Isbjörn entry is percent-encoded in NFD.
        XCTAssertNoThrow(try self.track(named: "Sven Väth - Akzidenz Grotesk - Isbjörn", in: collection))
    }

    func testVariableTempoGrid() throws {
        let track = try self.track(named: "Colored City", in: self.parsedFixture())
        XCTAssertGreaterThan(track.beatGrid.count, 1)
        XCTAssertEqual(track.beatGrid.first, RekordboxBeat(start: 0.150, bpm: 127.99, meter: "4/4", beat: 2))
    }

    func testRatingScaled() throws {
        let collection = try self.parsedFixture()
        XCTAssertEqual(try self.track(named: "Listen To The Hiss", in: collection).rating, 5)
        XCTAssertEqual(try self.track(named: "#DESCONOCIDO", in: collection).rating, 0)
    }

    func testMissingAttributesAreNil() throws {
        let collection = try self.parsedFixture()
        let edited = try XCTUnwrap(collection.tracks.first { $0.bpm == nil })
        XCTAssertNil(edited.tonality)
        XCTAssertNotNil(edited.size)
        let outside = try self.track(named: "Kasambila", in: collection)
        XCTAssertEqual(outside.label, "Denature Records")
        XCTAssertNil(try self.track(named: "#DESCONOCIDO", in: collection).label)
    }

    func testCommonAttributes() throws {
        let track = try self.track(named: "Kasambila", in: self.parsedFixture())
        XCTAssertEqual(track.path, "/AmpXFixture/Music/MUSICA/PEN/GHIMMEL/BEDOUIN/Stavroz/Kasambila/03 Kasambila (Original Mix).aiff")
        XCTAssertEqual(track.size, 93_249_016)
        XCTAssertEqual(track.duration, 527)
        XCTAssertEqual(track.bpm, 117)
        XCTAssertEqual(track.tonality, "E")
        XCTAssertEqual(track.playCount, 1)
    }

    func testPlaylistsIgnored() throws {
        let collection = try self.parsedFixture()
        XCTAssertTrue(collection.tracks.allSatisfy { !$0.path.isEmpty })
        XCTAssertEqual(collection.tracks.count, 19)
    }

    func testTruncatedFileThrows() throws {
        let data = try Self.fixtureData()
        XCTAssertThrowsError(try RekordboxCollectionParser.parse(data.prefix(data.count / 2))) { error in
            guard case .malformed = error as? RekordboxParseError else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testNotACollection() {
        XCTAssertThrowsError(try RekordboxCollectionParser.parse(Data("<foo/>".utf8))) { error in
            XCTAssertEqual(error as? RekordboxParseError, .notACollection)
        }
    }

    func testSniffAcceptsExport() throws {
        let data = try Self.fixtureData()
        XCTAssertTrue(RekordboxCollectionParser.isCollectionExport(prefix: data.prefix(RekordboxCollectionParser.sniffLength)))
    }

    func testSniffRejectsOthers() {
        let itunes = #"<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist><plist version="1.0"><dict>"#
        let other = #"<?xml version="1.0"?><DJ_PLAYLISTS Version="1.0.0"><PRODUCT Name="Other" Version="1"/>"#
        XCTAssertFalse(RekordboxCollectionParser.isCollectionExport(prefix: Data(itunes.utf8)))
        XCTAssertFalse(RekordboxCollectionParser.isCollectionExport(prefix: Data()))
        XCTAssertFalse(RekordboxCollectionParser.isCollectionExport(prefix: Data([0xFF, 0x00, 0x12, 0x9C])))
        XCTAssertFalse(RekordboxCollectionParser.isCollectionExport(prefix: Data(other.utf8)))
    }

    func testLocationDecoding() {
        XCTAssertEqual(
            RekordboxCollectionParser.path(fromLocation: "file://localhost/A%20B/%23x%20%5b1%5d.mp3"),
            "/A B/#x [1].mp3"
        )
        XCTAssertNil(RekordboxCollectionParser.path(fromLocation: ""))
    }
}

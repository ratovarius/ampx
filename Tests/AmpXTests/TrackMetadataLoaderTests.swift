@testable import AmpX
import XCTest

/// Widened `TrackMetadataLoader.Metadata` (spec: "Metadata extraction"), driven by the L1 gate matrix:
/// every field is exposed in every container, so each tagged fixture must yield every value.
final class TrackMetadataLoaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackMetadataLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.directory)
    }

    func testTaggedFixturesYieldEveryField() async throws {
        let codecs = [
            "tagged-v23.mp3": "mp3", "tagged-v24.mp3": "mp3", "tagged.flac": "flac",
            "tagged.wav": "wav", "tagged.aiff": "aiff", "tagged.m4a": "m4a",
        ]
        for (name, codec) in codecs {
            let metadata = try await TrackMetadataLoader.load(from: self.fixture(name))
            // FLAC's Vorbis TITLE/ARTIST are not in common metadata; precedence step 1 reads them (Revision 7).
            XCTAssertEqual(metadata.title, "Library Song", name)
            XCTAssertEqual(metadata.artist, "Library Artist", name)
            XCTAssertEqual(metadata.album, "Library Album", name)
            XCTAssertEqual(metadata.albumArtist, "Album Artist", name)
            XCTAssertEqual(metadata.genre, "Techno", name)
            XCTAssertEqual(metadata.year, 2024, name)
            XCTAssertEqual(metadata.trackNumber, 3, name)
            XCTAssertEqual(metadata.bpm, 130, name)
            XCTAssertEqual(metadata.musicalKey, "Am", name)
            XCTAssertEqual(metadata.comment, "Library fixture", name)
            XCTAssertEqual(metadata.sampleRate, 44100, name)
            XCTAssertEqual(metadata.channels, 2, name)
            XCTAssertEqual(metadata.codec, codec, name)
            XCTAssertGreaterThan(metadata.bitrate, 0, name)
            XCTAssertFalse(metadata.readFailed, name)
        }
    }

    func testReportedBitrateIsNotDerived() async throws {
        let metadata = try await TrackMetadataLoader.load(from: self.fixture("tagged.m4a"))
        XCTAssertFalse(metadata.bitrateIsDerived)
    }

    func testDerivedBitrateWhenNoEstimate() async throws {
        // The gate recorded estimatedDataRate == 0 for the 2 s MP3 fixture.
        let metadata = try await TrackMetadataLoader.load(from: self.fixture("tagged-v23.mp3"))
        XCTAssertTrue(metadata.bitrateIsDerived)
        let expected = Double(metadata.fileSize) * 8 / metadata.duration
        XCTAssertEqual(Double(metadata.bitrate), expected.rounded())
    }

    func testUntaggedArtistSongUsesParser() async throws {
        let url = try self.fixture("untagged/Library Artist - Library Song.mp3")
        let metadata = await TrackMetadataLoader.load(from: url)
        XCTAssertEqual(metadata.artist, "Library Artist")
        XCTAssertEqual(metadata.title, "Library Song")
        XCTAssertEqual(metadata.album, "")
        XCTAssertNil(metadata.genre)
    }

    func testUntaggedStemMatchesParser() async throws {
        let url = try self.fixture("untagged/Library Song.mp3")
        let metadata = await TrackMetadataLoader.load(from: url)
        let fallback = TrackMetadataParser.parse(from: url)
        XCTAssertEqual(metadata.title, fallback.title)
        XCTAssertEqual(metadata.artist, fallback.artist)
    }

    func testTitleOnlyKeepsUnknownArtist() async throws {
        let metadata = try await TrackMetadataLoader.load(from: self.fixture("title-only.mp3"))
        XCTAssertEqual(metadata.title, "Library Song")
        XCTAssertEqual(metadata.artist, "Unknown Artist")
    }

    func testArtistOnlyKeepsFilenameTitle() async throws {
        let metadata = try await TrackMetadataLoader.load(from: self.fixture("artist-only.mp3"))
        XCTAssertEqual(metadata.title, "artist-only")
        XCTAssertEqual(metadata.artist, "Library Artist")
    }

    func testTrackLoadAgreesWithLoader() async throws {
        for name in ["tagged-v23.mp3", "tagged.flac", "tagged.m4a", "untagged/Library Song.mp3", "title-only.mp3"] {
            let url = try self.fixture(name)
            let metadata = await TrackMetadataLoader.load(from: url)
            let track = await Track.load(from: url)
            XCTAssertEqual(track.title, metadata.title, name)
            XCTAssertEqual(track.artist, metadata.artist, name)
            XCTAssertEqual(track.duration, metadata.duration, name)
            XCTAssertEqual(track.fileSize, metadata.fileSize, name)
        }
    }

    /// The playlist path (`Track.load`) reads only what a playlist row shows: the full extraction made
    /// restoring a playlist and dropping many files several times slower (CI missed its waits).
    func testBasicLoadAgreesWithFullLoadOnPlaylistFields() async throws {
        for name in ["tagged-v23.mp3", "tagged.flac", "tagged.m4a", "tagged.aiff", "untagged/Library Song.mp3", "title-only.mp3"] {
            let url = try self.fixture(name)
            let full = await TrackMetadataLoader.load(from: url)
            let basic = await TrackMetadataLoader.loadBasic(from: url)
            XCTAssertEqual(basic.title, full.title, name)
            XCTAssertEqual(basic.artist, full.artist, name)
            XCTAssertEqual(basic.duration, full.duration, name)
            XCTAssertEqual(basic.fileSize, full.fileSize, name)
            XCTAssertEqual(basic.album, "", "basic load skips library-only fields: \(name)")
            XCTAssertEqual(basic.sampleRate, 0, name)
        }
    }

    func testCodecFromExtension() async throws {
        let url = try self.copy("tagged.aiff", as: "Copy.aif")
        let metadata = await TrackMetadataLoader.load(from: url)
        XCTAssertEqual(metadata.codec, "aiff")
    }

    func testUppercaseExtensionCodec() async throws {
        let url = try self.copy("tagged-v23.mp3", as: "X.MP3")
        let metadata = await TrackMetadataLoader.load(from: url)
        XCTAssertEqual(metadata.codec, "mp3")
        XCTAssertEqual(metadata.genre, "Techno")
    }

    func testMissingFileSetsReadFailed() async {
        let metadata = await TrackMetadataLoader.load(from: self.directory.appendingPathComponent("missing.mp3"))
        XCTAssertTrue(metadata.readFailed)
        XCTAssertEqual(metadata.duration, 0)
        XCTAssertEqual(metadata.bitrate, 0)
    }

    func testZeroByteFileSetsReadFailed() async throws {
        let url = self.directory.appendingPathComponent("empty.mp3")
        try Data().write(to: url)
        let metadata = await TrackMetadataLoader.load(from: url)
        XCTAssertTrue(metadata.readFailed)
        XCTAssertEqual(metadata.duration, 0)
    }

    func testTrackNumberParsing() {
        XCTAssertEqual(TrackMetadataLoader.leadingInteger("3/12"), 3)
        XCTAssertEqual(TrackMetadataLoader.leadingInteger(" 07 "), 7)
        XCTAssertNil(TrackMetadataLoader.leadingInteger("A1"))
        XCTAssertNil(TrackMetadataLoader.leadingInteger(""))
    }

    func testYearParsing() {
        XCTAssertEqual(TrackMetadataLoader.year(from: "2024"), 2024)
        XCTAssertEqual(TrackMetadataLoader.year(from: "2016-05-01T00:00:00Z"), 2016)
        XCTAssertNil(TrackMetadataLoader.year(from: "unknown"))
        XCTAssertNil(TrackMetadataLoader.year(from: "0"))
    }

    func testBPMParsing() {
        XCTAssertEqual(TrackMetadataLoader.bpm(from: "130"), 130)
        XCTAssertEqual(TrackMetadataLoader.bpm(from: "127.5"), 127.5)
        XCTAssertNil(TrackMetadataLoader.bpm(from: "0"))
        XCTAssertNil(TrackMetadataLoader.bpm(from: "-5"))
        XCTAssertNil(TrackMetadataLoader.bpm(from: "fast"))
    }

    func testKeyNormalizationKeepsTaggedNotation() {
        XCTAssertEqual(TrackMetadataLoader.normalizedKey("  am "), "Am")
        XCTAssertEqual(TrackMetadataLoader.normalizedKey("f#m"), "F#m")
        XCTAssertEqual(TrackMetadataLoader.normalizedKey("C  major"), "C major")
        XCTAssertEqual(TrackMetadataLoader.normalizedKey("8A"), "8A")
        XCTAssertNil(TrackMetadataLoader.normalizedKey("   "))
    }

    // MARK: - Helpers

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).resourceURL).appendingPathComponent("Library/\(name)")
    }

    private func copy(_ name: String, as newName: String) throws -> URL {
        let destination = self.directory.appendingPathComponent(newName)
        try FileManager.default.copyItem(at: self.fixture(name), to: destination)
        return destination
    }
}

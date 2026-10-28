@testable import AmpX
import AVFoundation
import XCTest

/// Reading and writing DJ mode's standard tag fields through TagLib (DJ mode spec Revision 2 § Tag writing).
final class TagFileIOTests: XCTestCase {
    private static let containers = ["tagged-v23.mp3", "tagged-v24.mp3", "tagged.wav", "tagged.aiff", "tagged.flac", "tagged.m4a"]
    private let values: [TagField: String] = [
        .bpm: "128", .key: "F#m", .label: "Drumcode", .remixer: "Adam Beyer", .composer: "A. Beyer", .grouping: "Peak",
    ]

    private func copy(_ name: String) throws -> URL {
        let fixtures = try XCTUnwrap(Bundle(for: Self.self).resourceURL).appendingPathComponent("Library")
        let destination = try LibraryTestSupport.temporaryDirectory(self).appendingPathComponent(name)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: destination)
        return destination
    }

    func testReadsExistingFields() throws {
        for name in Self.containers {
            let fields = try TagFileIO.read(self.copy(name))
            XCTAssertEqual(fields[.bpm], "130", name)
            XCTAssertEqual(fields[.key], "Am", name)
            XCTAssertNil(fields[.label], name)
        }
    }

    func testWritesAllSixFieldsInEveryContainer() throws {
        for name in Self.containers {
            let url = try self.copy(name)
            try TagFileIO.write(self.values, to: url)
            XCTAssertEqual(try TagFileIO.read(url), self.values, name)
        }
    }

    func testWritesOnlyGivenFields() throws {
        for name in Self.containers {
            let url = try self.copy(name)
            try TagFileIO.write([.label: "Kompakt"], to: url)
            XCTAssertEqual(try TagFileIO.read(url), [.bpm: "130", .key: "Am", .label: "Kompakt"], name)
        }
    }

    func testWriteKeepsOtherTagsAndArtwork() async throws {
        for name in ["artwork-v24.mp3", "artwork.m4a"] {
            let url = try self.copy(name)
            let artworkBefore = try await self.artwork(url)
            XCTAssertNotNil(artworkBefore, name)

            try TagFileIO.write(self.values, to: url)

            let metadata = await TrackMetadataLoader.load(from: url)
            XCTAssertEqual(metadata.title, "Library Song", name)
            XCTAssertEqual(metadata.artist, "Library Artist", name)
            XCTAssertEqual(metadata.album, "Library Album", name)
            XCTAssertEqual(metadata.genre, "Techno", name)
            XCTAssertEqual(metadata.duration, 2, accuracy: 0.1, name)
            let artworkAfter = try await self.artwork(url)
            XCTAssertEqual(artworkAfter, artworkBefore, name)
        }
    }

    func testKeepsID3Version() throws {
        let v23 = try self.copy("tagged-v23.mp3")
        try TagFileIO.write(self.values, to: v23)
        XCTAssertEqual(try Data(contentsOf: v23)[3], 3)
        let v24 = try self.copy("tagged-v24.mp3")
        try TagFileIO.write(self.values, to: v24)
        XCTAssertEqual(try Data(contentsOf: v24)[3], 4)
    }

    func testUnsupportedExtensionThrows() throws {
        let url = try LibraryTestSupport.temporaryDirectory(self).appendingPathComponent("a.ogg")
        try Data([0, 1, 2]).write(to: url)
        XCTAssertThrowsError(try TagFileIO.read(url))
        XCTAssertThrowsError(try TagFileIO.write(self.values, to: url))
    }

    private func artwork(_ url: URL) async throws -> Data? {
        let asset = AVURLAsset(url: url)
        let items = try await asset.load(.commonMetadata)
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first else {
            return nil
        }
        return try await item.load(.dataValue)
    }
}

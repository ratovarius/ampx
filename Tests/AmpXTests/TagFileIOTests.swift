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

    func testID3v22BecomesV23() throws {
        let url = try self.copy("tagged-v22.mp3")
        XCTAssertEqual(try Data(contentsOf: url)[3], 2)
        try TagFileIO.write(self.values, to: url)
        XCTAssertEqual(try Data(contentsOf: url)[3], 3, "TagLib cannot write v2.2; v2.3 is the closer, more compatible version")
        XCTAssertEqual(try TagFileIO.read(url), self.values)
    }

    func testOtherKeysListEverythingButTheWrittenFields() throws {
        let url = try self.copy("rvad-v23.mp3")
        let keys = try TagFileIO.otherKeys(url)
        XCTAssertTrue(keys.contains("RVAD"), "\(keys)")
        XCTAssertTrue(keys.contains("APIC"), "\(keys)")
        XCTAssertFalse(keys.contains("TBPM"))
        XCTAssertFalse(keys.contains("TKEY"))
        XCTAssertTrue(try TagFileIO.otherKeys(self.copy("artwork.m4a")).contains("covr"))
        XCTAssertTrue(try TagFileIO.otherKeys(self.copy("tagged.flac")).contains("TITLE"))

        // TagLib drops RVAD when it rewrites a v2.3 tag: the writer must notice.
        try TagFileIO.write(self.values, to: url)
        XCTAssertFalse(try TagFileIO.otherKeys(url).contains("RVAD"))
    }

    func testReadsAndKeepsCompressedFrames() throws {
        // A zlib-less TagLib would miss this BPM and bypass the half/double guard.
        let url = try self.id3v23(frames: self.frame("TBPM", text: "130", compressed: true))
        XCTAssertEqual(try TagFileIO.read(url), [.bpm: "130"])
        try TagFileIO.write([.key: "F#m"], to: url)
        XCTAssertEqual(try TagFileIO.read(url), [.bpm: "130", .key: "F#m"])
    }

    func testRefusesV23ExtendedHeader() throws {
        // TagLib reads the v2.3 size (6, excluding itself) as v2.4's and would skip, then drop, every frame.
        let extendedHeader = Data([0, 0, 0, 6, 0, 0, 0, 0, 0, 0])
        let url = try self.id3v23(flags: 0x40, frames: extendedHeader + self.frame("TBPM", text: "130"))
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(try TagFileIO.write(self.values, to: url)) {
            XCTAssertEqual(($0 as NSError).code, AmpXTagFileError.unsafeTag.rawValue)
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testRefusesEncryptedFrames() throws {
        // TagLib would save the encrypted bytes as a plain frame.
        let encrypted = self.frame("TIT2", payload: Data([0x80, 0xDE, 0xAD, 0xBE, 0xEF]), flags: 0x40)
        let url = try self.id3v23(frames: self.frame("TBPM", text: "130") + encrypted)
        XCTAssertThrowsError(try TagFileIO.write(self.values, to: url)) {
            XCTAssertEqual(($0 as NSError).code, AmpXTagFileError.unsafeTag.rawValue)
        }
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

    /// `tagged-v23.mp3`'s audio under a hand-built ID3v2.3 tag with header `flags` and `frames`.
    private func id3v23(flags: UInt8 = 0, frames: Data) throws -> URL {
        let url = try self.copy("tagged-v23.mp3")
        let original = try Data(contentsOf: url)
        let oldSize = original[6 ..< 10].reduce(0) { $0 << 7 | Int($1) }
        let audio = original[(10 + oldSize)...]
        let size = frames.count
        let header = Data("ID3".utf8) + [3, 0, flags] + [3, 2, 1, 0].map { UInt8(size >> ($0 * 7) & 0x7F) }
        try (header + frames + audio).write(to: url)
        return url
    }

    /// A v2.3 text frame (Latin-1), zlib-compressed when asked.
    private func frame(_ id: String, text: String, compressed: Bool = false) -> Data {
        let payload = Data([0]) + Data(text.utf8)
        guard compressed else { return self.frame(id, payload: payload, flags: 0) }
        return self.frame(id, payload: Self.bigEndian(payload.count) + Self.zlibStored(payload), flags: 0x80)
    }

    private func frame(_ id: String, payload: Data, flags: UInt8) -> Data {
        Data(id.utf8) + Self.bigEndian(payload.count) + [0, flags] + payload
    }

    private static func bigEndian(_ value: Int) -> Data {
        Data([3, 2, 1, 0].map { UInt8(value >> ($0 * 8) & 0xFF) })
    }

    /// A zlib stream holding `data` in one stored (uncompressed) deflate block.
    private static func zlibStored(_ data: Data) -> Data {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let length = UInt16(data.count)
        let lengths = [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)]
        return Data([0x78, 0x01, 0x01] + lengths) + data + self.bigEndian(Int(b << 16 | a))
    }
}

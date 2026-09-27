@testable import AmpX
import SwiftData
import XCTest

final class LibrarySchemaMigrationTests: XCTestCase {
    private let rootID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let trackID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!

    func testV1OnDiskRoundTrip() throws {
        let storeURL = try LibraryTestSupport.temporaryDirectory(self).appendingPathComponent("Library.store")
        do {
            let context = try ModelContext(LibraryContainerFactory.make(url: storeURL))
            context.insert(self.makeRoot())
            context.insert(self.makeTrack())
            try context.save()
        }

        let context = try ModelContext(LibraryContainerFactory.make(url: storeURL))
        let root = try XCTUnwrap(try context.fetch(FetchDescriptor<LibraryRoot>()).first)
        XCTAssertEqual(root.id, self.rootID)
        XCTAssertEqual(root.bookmark, Data([1, 2, 3]))
        XCTAssertEqual(root.displayPath, "/Music/DJ")
        XCTAssertFalse(root.isAvailable)
        XCTAssertEqual(root.unreadableFolderCount, 2)
        XCTAssertEqual(root.addedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(root.lastCompletedScanAt, Date(timeIntervalSince1970: 200))

        let track = try XCTUnwrap(try context.fetch(FetchDescriptor<LibraryTrack>()).first)
        self.assertTrackFields(
            id: track.id, rootID: track.rootID, relativePath: track.relativePath,
            schemaVersion: track.schemaVersion, title: track.title, artist: track.artist, album: track.album,
            albumArtist: track.albumArtist, genre: track.genre, year: track.year, trackNumber: track.trackNumber,
            duration: track.duration, fileSize: track.fileSize, contentModifiedAt: track.contentModifiedAt,
            contentFingerprint: track.contentFingerprint, bitrate: track.bitrate, bitrateIsDerived: track.bitrateIsDerived,
            sampleRate: track.sampleRate, channels: track.channels, codec: track.codec, bpm: track.bpm,
            musicalKey: track.musicalKey, comment: track.comment, dateAdded: track.dateAdded,
            lastPlayedAt: track.lastPlayedAt, playCount: track.playCount, rating: track.rating, isMissing: track.isMissing
        )
        XCTAssertEqual(track.schemaVersion, 1)
    }

    func testNewTrackDefaults() {
        let track = LibraryTrack(
            id: UUID(), rootID: UUID(), relativePath: "a.mp3", title: "T", artist: "A",
            fileSize: 1, contentModifiedAt: Date(timeIntervalSince1970: 0), dateAdded: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(track.schemaVersion, 1)
        XCTAssertEqual(track.album, "")
        XCTAssertEqual(track.albumArtist, "")
        XCTAssertNil(track.genre)
        XCTAssertEqual(track.duration, 0)
        XCTAssertNil(track.contentFingerprint)
        XCTAssertEqual(track.bitrate, 0)
        XCTAssertEqual(track.playCount, 0)
        XCTAssertEqual(track.rating, 0)
        XCTAssertNil(track.lastPlayedAt)
        XCTAssertFalse(track.isMissing)
    }

    func testMakeTrackCarriesFileSizeAndURL() {
        let row = LibraryRow(
            id: UUID(), rootID: UUID(), url: URL(fileURLWithPath: "/Music/DJ/a.mp3"),
            title: "Song", artist: "Artist", album: "", albumArtist: "",
            genre: nil, trackNumber: nil, duration: 120, fileSize: 4096,
            bpm: nil, musicalKey: nil, bitrate: 0, bitrateIsDerived: false,
            codec: "mp3", isAvailable: true, searchKey: "song artist"
        )
        let first = row.makeTrack()
        let second = row.makeTrack()
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.fileSize, 4096)
        XCTAssertEqual(first.url, row.url)
        XCTAssertEqual(first.title, "Song")
        XCTAssertEqual(first.artist, "Artist")
        XCTAssertEqual(first.duration, 120)
    }

    func testLightweightMigrationToTestV2() throws {
        let storeURL = try LibraryTestSupport.temporaryDirectory(self).appendingPathComponent("Library.store")
        do {
            let context = try ModelContext(LibraryContainerFactory.make(url: storeURL))
            context.insert(self.makeRoot())
            context.insert(self.makeTrack())
            try context.save()
        }

        for _ in 0 ..< 2 { // second open proves idempotence
            let context = try ModelContext(LibraryTestSchemaV2.makeContainer(url: storeURL))
            let tracks = try context.fetch(FetchDescriptor<LibraryTestSchemaV2.LibraryTrack>())
            XCTAssertEqual(tracks.count, 1)
            let track = try XCTUnwrap(tracks.first)
            XCTAssertEqual(track.schemaVersion, 2)
            XCTAssertNil(track.camelotKey)
            self.assertTrackFields(
                id: track.id, rootID: track.rootID, relativePath: track.relativePath,
                schemaVersion: 1, title: track.title, artist: track.artist, album: track.album,
                albumArtist: track.albumArtist, genre: track.genre, year: track.year, trackNumber: track.trackNumber,
                duration: track.duration, fileSize: track.fileSize, contentModifiedAt: track.contentModifiedAt,
                contentFingerprint: track.contentFingerprint, bitrate: track.bitrate, bitrateIsDerived: track.bitrateIsDerived,
                sampleRate: track.sampleRate, channels: track.channels, codec: track.codec, bpm: track.bpm,
                musicalKey: track.musicalKey, comment: track.comment, dateAdded: track.dateAdded,
                lastPlayedAt: track.lastPlayedAt, playCount: track.playCount, rating: track.rating, isMissing: track.isMissing
            )
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<LibraryTestSchemaV2.LibraryRoot>()), 1)
        }
    }

    func testNewerStoreRefusesToOpenAndKeepsRows() throws {
        let storeURL = try LibraryTestSupport.temporaryDirectory(self).appendingPathComponent("Library.store")
        do {
            let context = try ModelContext(LibraryContainerFactory.make(url: storeURL))
            context.insert(self.makeTrack())
            try context.save()
        }
        _ = try LibraryTestSchemaV2.makeContainer(url: storeURL)

        XCTAssertThrowsError(try LibraryContainerFactory.make(url: storeURL)) { error in
            XCTAssertEqual(error as? LibraryContainerError, .newerSchema(found: "2.0.0"))
        }
        let context = try ModelContext(LibraryTestSchemaV2.makeContainer(url: storeURL))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LibraryTestSchemaV2.LibraryTrack>()), 1)
    }

    // MARK: - Helpers

    private func makeRoot() -> LibraryRoot {
        let root = LibraryRoot(
            id: self.rootID,
            bookmark: Data([1, 2, 3]),
            displayPath: "/Music/DJ",
            addedAt: Date(timeIntervalSince1970: 100)
        )
        root.isAvailable = false
        root.unreadableFolderCount = 2
        root.lastCompletedScanAt = Date(timeIntervalSince1970: 200)
        return root
    }

    private func makeTrack() -> LibraryTrack {
        let track = LibraryTrack(
            id: self.trackID, rootID: self.rootID, relativePath: "Techno/a.mp3", title: "Song", artist: "Artist",
            fileSize: 12345, contentModifiedAt: Date(timeIntervalSince1970: 300), dateAdded: Date(timeIntervalSince1970: 400)
        )
        track.album = "Album"
        track.albumArtist = "Album Artist"
        track.genre = "Techno"
        track.year = 2024
        track.trackNumber = 3
        track.duration = 200.5
        track.contentFingerprint = Data([9, 9])
        track.bitrate = 320_000
        track.bitrateIsDerived = true
        track.sampleRate = 44100
        track.channels = 2
        track.codec = "mp3"
        track.bpm = 130
        track.musicalKey = "Am"
        track.comment = "Comment"
        track.lastPlayedAt = Date(timeIntervalSince1970: 500)
        track.playCount = 7
        track.rating = 4
        track.isMissing = true
        return track
    }

    private func assertTrackFields(
        id: UUID, rootID: UUID, relativePath: String, schemaVersion: Int, title: String, artist: String,
        album: String, albumArtist: String, genre: String?, year: Int?, trackNumber: Int?, duration: Double,
        fileSize: Int64, contentModifiedAt: Date, contentFingerprint: Data?, bitrate: Int, bitrateIsDerived: Bool,
        sampleRate: Int, channels: Int, codec: String, bpm: Double?, musicalKey: String?, comment: String?,
        dateAdded: Date, lastPlayedAt: Date?, playCount: Int, rating: Int, isMissing: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(id, self.trackID, file: file, line: line)
        XCTAssertEqual(rootID, self.rootID, file: file, line: line)
        XCTAssertEqual(relativePath, "Techno/a.mp3", file: file, line: line)
        XCTAssertEqual(schemaVersion, 1, file: file, line: line)
        XCTAssertEqual(title, "Song", file: file, line: line)
        XCTAssertEqual(artist, "Artist", file: file, line: line)
        XCTAssertEqual(album, "Album", file: file, line: line)
        XCTAssertEqual(albumArtist, "Album Artist", file: file, line: line)
        XCTAssertEqual(genre, "Techno", file: file, line: line)
        XCTAssertEqual(year, 2024, file: file, line: line)
        XCTAssertEqual(trackNumber, 3, file: file, line: line)
        XCTAssertEqual(duration, 200.5, file: file, line: line)
        XCTAssertEqual(fileSize, 12345, file: file, line: line)
        XCTAssertEqual(contentModifiedAt, Date(timeIntervalSince1970: 300), file: file, line: line)
        XCTAssertEqual(contentFingerprint, Data([9, 9]), file: file, line: line)
        XCTAssertEqual(bitrate, 320_000, file: file, line: line)
        XCTAssertTrue(bitrateIsDerived, file: file, line: line)
        XCTAssertEqual(sampleRate, 44100, file: file, line: line)
        XCTAssertEqual(channels, 2, file: file, line: line)
        XCTAssertEqual(codec, "mp3", file: file, line: line)
        XCTAssertEqual(bpm, 130, file: file, line: line)
        XCTAssertEqual(musicalKey, "Am", file: file, line: line)
        XCTAssertEqual(comment, "Comment", file: file, line: line)
        XCTAssertEqual(dateAdded, Date(timeIntervalSince1970: 400), file: file, line: line)
        XCTAssertEqual(lastPlayedAt, Date(timeIntervalSince1970: 500), file: file, line: line)
        XCTAssertEqual(playCount, 7, file: file, line: line)
        XCTAssertEqual(rating, 4, file: file, line: line)
        XCTAssertTrue(isMissing, file: file, line: line)
    }
}

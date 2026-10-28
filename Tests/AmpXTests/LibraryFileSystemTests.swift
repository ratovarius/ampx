@testable import AmpX
import XCTest

/// `FoundationLibraryFileSystem` on real temporary trees (spec: "Scanning", step 2).
final class LibraryFileSystemTests: XCTestCase {
    private let fileSystem = FoundationLibraryFileSystem()
    private var root: URL!
    private var lockedURLs: [URL] = []

    override func setUpWithError() throws {
        self.root = try LibraryTestSupport.temporaryDirectory(self)
    }

    override func tearDownWithError() throws {
        for url in self.lockedURLs {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    func testWalkReadsNoContents() async throws {
        // Unreadable contents but listable folders: a stat-only walk still sees every file.
        let files = try ["a.mp3", "crate/b.flac", "crate/c.wav"].map { try self.write($0) }
        for file in files {
            try self.lock(file, permissions: 0o000)
        }
        let walk = try await self.walk()
        XCTAssertEqual(walk.coverage, .complete)
        XCTAssertEqual(walk.entries.map(\.relativePath).sorted(), ["a.mp3", "crate/b.flac", "crate/c.wav"])
    }

    func testUnreadableFolderMakesWalkPartial() async throws {
        try self.write("open/a.mp3")
        try self.write("locked/b.mp3")
        try self.lock(self.root.appendingPathComponent("locked"), permissions: 0o000)
        let walk = try await self.walk()
        XCTAssertEqual(walk.coverage, .partial(uncoveredFolders: ["locked"]))
        XCTAssertEqual(walk.entries.map(\.relativePath), ["open/a.mp3"])
    }

    func testMissingRootThrows() async {
        let missing = self.root.appendingPathComponent("gone", isDirectory: true)
        do {
            _ = try await self.fileSystem.walk(root: missing, volume: LibraryVolume(caseSensitive: false, typeName: "apfs"))
            XCTFail("a missing root must not produce an empty complete walk")
        } catch {}
        let reachable = await self.fileSystem.isReachable(missing)
        XCTAssertFalse(reachable)
    }

    func testEmptyRootIsCompleteAndEmpty() async throws {
        let walk = try await self.walk()
        XCTAssertEqual(walk.coverage, .complete)
        XCTAssertTrue(walk.entries.isEmpty)
    }

    func testExcludesDotfilesPackagesReservedFoldersAndOtherTypes() async throws {
        for path in [
            "keep.mp3",
            ".hidden.mp3",
            ".DS_Store",
            "_extracted/x.mp3",
            "_library/y.mp3",
            "Bundle.app/Contents/z.mp3",
            "notes.txt",
            "crate/_extracted_not/ok.mp3",
        ] {
            try self.write(path)
        }
        let walk = try await self.walk()
        XCTAssertEqual(walk.entries.map(\.relativePath).sorted(), ["crate/_extracted_not/ok.mp3", "keep.mp3"])
    }

    func testWalkAcceptsUppercaseExtensions() async throws {
        try self.write("Loud.MP3")
        try self.write("Deep.AIF")
        let walk = try await self.walk()
        XCTAssertEqual(walk.entries.map(\.relativePath).sorted(), ["Deep.AIF", "Loud.MP3"])
    }

    func testRelativePathRoundTripsPunctuation() async throws {
        let path = "Hard Groove (128k)/Drum & Bass #1 [Mix].mp3"
        try self.write(path)
        let walk = try await self.walk()
        XCTAssertEqual(walk.entries.map(\.relativePath), [path])
        let url = self.root.appendingPathComponent(walk.entries[0].relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSymlinkedRootProducesStableRelativePaths() async throws {
        let real = self.root.appendingPathComponent("real", isDirectory: true)
        try self.write("real/crate/a.mp3")
        let link = self.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let volume = try await self.fileSystem.volume(at: real)
        let viaReal = try await self.fileSystem.walk(root: real, volume: volume)
        let viaLink = try await self.fileSystem.walk(root: link, volume: volume)
        XCTAssertEqual(viaLink.entries.map(\.relativePath), ["crate/a.mp3"])
        XCTAssertEqual(viaLink.entries, viaReal.entries)
    }

    func testVolumeReportsAPFS() async throws {
        let volume = try await self.fileSystem.volume(at: self.root)
        XCTAssertEqual(volume.typeName, "apfs")
        XCTAssertTrue(volume.renameTrackingEnabled)
    }

    func testStatMatchesWalk() async throws {
        let url = try self.write("a.mp3", bytes: 4321)
        let walk = try await self.walk()
        let stat = try await self.fileSystem.stat(at: url)
        XCTAssertEqual(stat.fileSize, 4321)
        XCTAssertEqual(walk.entries.first?.stat, stat)
    }

    func testFingerprintUsesLibraryFingerprint() async throws {
        let url = try self.write("a.mp3", bytes: 200_000)
        let fingerprint = try await self.fileSystem.fingerprint(at: url)
        XCTAssertEqual(fingerprint, try LibraryFingerprint.read(from: url))
    }

    func testCancellationAbortsWalk() async throws {
        for index in 0 ..< 600 {
            try self.write("crate/\(index).mp3")
        }
        let volume = try await self.fileSystem.volume(at: self.root)
        let fileSystem = self.fileSystem
        let root = try XCTUnwrap(self.root)
        let task = Task { try await fileSystem.walk(root: root, volume: volume) }
        task.cancel()
        let walk = try await task.value
        XCTAssertEqual(walk.coverage, .aborted)
    }

    // MARK: - Helpers

    private func walk() async throws -> LibraryWalk {
        let volume = try await self.fileSystem.volume(at: self.root)
        return try await self.fileSystem.walk(root: self.root, volume: volume)
    }

    @discardableResult
    private func write(_ relativePath: String, bytes: Int = 16) throws -> URL {
        let url = self.root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    private func lock(_ url: URL, permissions: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        self.lockedURLs.append(url)
    }

    // MARK: - rekordbox discovery

    func testTopLevelFilesListsOnlyTopLevelXml() async throws {
        let manager = FileManager.default
        try manager.createDirectory(at: self.root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try manager.createDirectory(at: self.root.appendingPathComponent("folder.xml"), withIntermediateDirectories: true)
        for name in ["a.xml", "B.XML", "sub/c.xml", "d.txt"] {
            try Data("x".utf8).write(to: self.root.appendingPathComponent(name))
        }

        let files = try await self.fileSystem.topLevelFiles(in: self.root, pathExtension: "xml")

        XCTAssertEqual(files.map(\.name).sorted(), ["B.XML", "a.xml"])
        let a = try XCTUnwrap(files.first { $0.name == "a.xml" })
        XCTAssertEqual(a.stamp.size, 1)
        XCTAssertEqual(a.url.lastPathComponent, "a.xml")
    }

    func testReadPrefixReadsAtMostLength() async throws {
        let url = self.root.appendingPathComponent("big.xml")
        try Data(repeating: 65, count: 10000).write(to: url)
        let prefix = try await self.fileSystem.readPrefix(of: url, length: 4096)
        XCTAssertEqual(prefix.count, 4096)
        let all = try await self.fileSystem.readAll(of: url)
        XCTAssertEqual(all.count, 10000)
    }

    func testReadAllSurvivesTruncationAfterRead() async throws {
        let url = self.root.appendingPathComponent("collection.xml")
        try Data(repeating: 65, count: 8 << 20).write(to: url)
        let data = try await self.fileSystem.readAll(of: url)
        // rekordbox may rewrite the export in place; a mapped read would fault on the truncated pages.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.close()
        XCTAssertEqual(data.reduce(0) { $0 &+ Int($1) }, 65 * (8 << 20))
    }
}

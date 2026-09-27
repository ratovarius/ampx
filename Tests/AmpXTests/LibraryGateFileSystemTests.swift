@testable import AmpX
import AVFoundation
import XCTest

/// L1 gate (spec: "Where each measurement runs"): APFS rename evidence and case sensitivity inside the sandbox,
/// the synthetic 11,000-file walk, and — opt-in with `TEST_RUNNER_AMPX_LIBRARY_GATE=1` — the real
/// `~/Music/DJ` walk and first-scan cost. Results are kept as `LIBRARY-GATE-*` attachments.
final class LibraryGateFileSystemTests: XCTestCase {
    private static let prefetchKeys: [URLResourceKey] = [
        .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .volumeIdentifierKey,
    ]
    private static let audioExtensions: Set<String> = ["aif", "aiff", "flac", "m4a", "mp3", "wav"]
    private static let skippedFolders: Set<String> = ["_extracted", "_library"]

    private var directory: URL!

    override func setUpWithError() throws {
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryGate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.directory)
    }

    func testAPFSRenameEvidenceInContainer() throws {
        let fileManager = FileManager.default
        let original = self.directory.appendingPathComponent("gate-a.mp3")
        let renamed = self.directory.appendingPathComponent("gate-b.mp3")
        let subfolder = self.directory.appendingPathComponent("gate-sub", isDirectory: true)
        let moved = subfolder.appendingPathComponent("gate-b.mp3")
        try Data(repeating: 7, count: 65536).write(to: original)
        try fileManager.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600.123_456)], ofItemAtPath: original.path
        )

        let volume = try self.directory.resourceValues(forKeys: [.volumeTypeNameKey, .volumeSupportsCaseSensitiveNamesKey])
        let before = try self.walk(self.directory)["gate-a.mp3"]
        try fileManager.moveItem(at: original, to: renamed)
        let afterRename = try self.walk(self.directory)["gate-b.mp3"]
        try fileManager.moveItem(at: renamed, to: moved)
        let afterMove = try self.walk(self.directory)["gate-sub/gate-b.mp3"]

        XCTAssertEqual(volume.volumeTypeName, "apfs")
        XCTAssertNotNil(volume.volumeSupportsCaseSensitiveNames, "case sensitivity must be readable in the sandbox")
        XCTAssertNotNil(before)
        XCTAssertEqual(afterRename, before)
        XCTAssertEqual(afterMove, before)
        self.emitGate("rename", [
            "volumeType": volume.volumeTypeName ?? "unknown",
            "caseSensitive": volume.volumeSupportsCaseSensitiveNames.map { "\($0)" } ?? "unreadable",
            "renamePreserved": "\(afterRename == before)",
            "movePreserved": "\(afterMove == before)",
            "modified": before.map { "\($0.modified.timeIntervalSinceReferenceDate)" } ?? "missing",
        ])
    }

    func testSyntheticNoChangeWalk11k() throws {
        let payload = Data(repeating: 1, count: 1024)
        for folder in 0 ..< 110 {
            let folderURL = self.directory.appendingPathComponent("crate-\(folder)", isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            for file in 0 ..< 100 {
                try payload.write(to: folderURL.appendingPathComponent("track-\(file).mp3"))
            }
        }

        let start = ContinuousClock.now
        let entries = try self.walk(self.directory)
        let elapsed = (ContinuousClock.now - start) / .seconds(1)

        XCTAssertEqual(entries.count, 11000)
        XCTAssertLessThan(elapsed, 5, "no-change walk of 11,000 files exceeds the 5 s budget")
        self.emitGate("walk11k", ["files": "\(entries.count)", "seconds": String(format: "%.3f", elapsed)])
    }

    func testRealCollectionCost() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AMPX_LIBRARY_GATE"] == "1",
            "Set TEST_RUNNER_AMPX_LIBRARY_GATE=1 to measure ~/Music/DJ"
        )
        let home = try String(cString: XCTUnwrap(getpwuid(getuid())).pointee.pw_dir)
        let root = URL(fileURLWithPath: home).appendingPathComponent("Music/DJ", isDirectory: true)

        let walkStart = ContinuousClock.now
        let entries: [String: Observed]
        do {
            entries = try self.walk(root)
        } catch {
            return XCTFail("Music entitlement does not cover ~/Music/DJ: \(error)")
        }
        let walkSeconds = (ContinuousClock.now - walkStart) / .seconds(1)
        XCTAssertEqual(entries.count, 2232)
        XCTAssertLessThan(walkSeconds, 2, "no-change walk of ~/Music/DJ exceeds the 2 s budget")

        var genres: [String: Int] = [:]
        var folders: [String: Int] = [:]
        var readFailures = 0
        let scanStart = ContinuousClock.now
        for relativePath in entries.keys.sorted() {
            let url = root.appendingPathComponent(relativePath)
            folders[String(relativePath.split(separator: "/").first ?? ""), default: 0] += 1
            let genre = await Self.fullMetadataLoad(url)
            genres[genre ?? "(no genre)", default: 0] += 1
            if (try? LibraryFingerprint.read(from: url)) == nil {
                readFailures += 1
            }
        }
        let scanSeconds = (ContinuousClock.now - scanStart) / .seconds(1)
        XCTAssertLessThan(scanSeconds, 60, "first scan (metadata + fingerprints) exceeds the 60 s budget")

        self.emitGate("cost", CostReport(
            files: entries.count,
            walkSeconds: walkSeconds,
            firstScanSeconds: scanSeconds,
            fingerprintFailures: readFailures,
            genres: genres,
            folders: folders
        ))
    }

    // MARK: - Helpers

    private struct Observed: Equatable {
        let size: Int
        let modified: Date
    }

    private struct CostReport: Encodable {
        let files: Int
        let walkSeconds: Double
        let firstScanSeconds: Double
        let fingerprintFailures: Int
        let genres: [String: Int]
        let folders: [String: Int]
    }

    /// Mirrors the library walk: prefetched keys only, no content reads, dotfiles/packages/reserved folders skipped.
    private func walk(_ root: URL) throws -> [String: Observed] {
        let resolved = root.resolvingSymlinksInPath()
        var failure: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: resolved,
            includingPropertiesForKeys: Self.prefetchKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in
                failure = error
                return false
            }
        ) else { throw CocoaError(.fileReadUnknown) }

        var entries: [String: Observed] = [:]
        let prefix = resolved.path.hasSuffix("/") ? resolved.path : resolved.path + "/"
        for case let url as URL in enumerator {
            if Self.skippedFolders.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let values = try url.resourceValues(forKeys: Set(Self.prefetchKeys))
            guard values.isRegularFile == true,
                  Self.audioExtensions.contains(url.pathExtension.lowercased()),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate
            else { continue }
            entries[String(url.resolvingSymlinksInPath().path.dropFirst(prefix.count))] = Observed(size: size, modified: modified)
        }
        if let failure {
            throw failure
        }
        return entries
    }

    /// What the widened Task 4 loader will read: today's loader plus every metadata format and the audio format.
    private static func fullMetadataLoad(_ url: URL) async -> String? {
        _ = await TrackMetadataLoader.load(from: url)
        let asset = AVURLAsset(url: url)
        var items = await (try? asset.load(.commonMetadata)) ?? []
        for format in await (try? asset.load(.availableMetadataFormats)) ?? [] {
            await items += (try? asset.loadMetadata(for: format)) ?? []
        }
        if let track = try? await asset.loadTracks(withMediaType: .audio).first {
            _ = try? await track.load(.formatDescriptions, .estimatedDataRate)
        }
        let genreIdentifiers: Set = ["id3/TCON", "vorb/GENRE", "itsk/%A9gen"]
        for item in items where genreIdentifiers.contains(item.identifier?.rawValue ?? "") {
            if let genre = try? await item.load(.stringValue), !genre.isEmpty {
                return genre
            }
        }
        return nil
    }
}

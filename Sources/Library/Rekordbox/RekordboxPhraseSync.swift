import Foundation
import os

private let phraseLogger = Logger(subsystem: "com.ampx.macos", category: "RekordboxPhrases")

/// rekordbox's analysis tree (`share/PIONEER/USBANLZ/*/*`), one folder per analysed track.
protocol RekordboxAnalysisSource: Sendable {
    /// Every folder holding an `ANLZ0000.DAT`.
    func trackFolders() async throws -> [URL]
    func read(_ url: URL) async throws -> Data
    func stamp(_ url: URL) async throws -> RekordboxFileStamp
    /// Ends the run's access (the live source holds the folder's security scope while open).
    func close()
}

struct RekordboxPhraseWrite: Sendable, Equatable {
    let rowID: UUID
    /// Packed `RekordboxPhraseAnalysis`; nil when the file had none or did not decode.
    let phrases: Data?
    /// JSON `RekordboxFileStamp` of the `.EXT` file.
    let stamp: Data
}

/// The granted rekordbox folder on disk, opened for one run.
final class RekordboxAnalysisDirectory: RekordboxAnalysisSource, @unchecked Sendable {
    private let analysis: URL
    private let folder: URL
    private let accessing: Bool

    init(folder: URL) {
        self.folder = folder
        self.analysis = RekordboxAnalysisAccess.analysisFolder(in: folder)
        self.accessing = folder.startAccessingSecurityScopedResource()
    }

    func trackFolders() async throws -> [URL] {
        let manager = FileManager.default
        var folders: [URL] = []
        for outer in try manager.contentsOfDirectory(at: self.analysis, includingPropertiesForKeys: nil) {
            guard let inner = try? manager.contentsOfDirectory(at: outer, includingPropertiesForKeys: nil) else { continue }
            folders += inner.filter { manager.fileExists(atPath: $0.appendingPathComponent("ANLZ0000.DAT").path) }
        }
        return folders.sorted { $0.path < $1.path }
    }

    func read(_ url: URL) async throws -> Data {
        try Data(contentsOf: url)
    }

    func stamp(_ url: URL) async throws -> RekordboxFileStamp {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return RekordboxFileStamp(size: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate ?? .distantPast)
    }

    func close() {
        if self.accessing {
            self.folder.stopAccessingSecurityScopedResource()
        }
    }
}

/// Links rekordbox analysis folders to library rows. rekordbox stores only the file name, so a folder matches the row
/// with that name whose beatgrid starts on the same beat (within 20 ms and 0.05 BPM). A row without a grid matches
/// only when its name is unique. More than one candidate is ambiguous and never guessed.
struct RekordboxAnalysisMatcher: Sendable {
    private struct Candidate: Sendable {
        let rowID: UUID
        let firstBeat: RekordboxBeat?
    }

    private let byName: [String: [Candidate]]

    init(_ snapshot: RekordboxLibrarySnapshot) {
        var byName: [String: [Candidate]] = [:]
        for row in snapshot.rows {
            let name = (row.relativePath as NSString).lastPathComponent.precomposedStringWithCanonicalMapping
            let first = row.beatGrid.flatMap(RekordboxBeatGrid.unpack)?.first
            byName[name, default: []].append(Candidate(rowID: row.id, firstBeat: first))
        }
        self.byName = byName
    }

    func rowID(fileName: String, firstBeat: RekordboxBeat?) -> UUID? {
        let candidates = self.byName[fileName.precomposedStringWithCanonicalMapping] ?? []
        if let firstBeat {
            let confirmed = candidates.filter { candidate in
                candidate.firstBeat.map { abs($0.start - firstBeat.start) <= 0.02 && abs($0.bpm - firstBeat.bpm) <= 0.05 } ?? false
            }
            if !confirmed.isEmpty {
                return confirmed.count == 1 ? confirmed[0].rowID : nil
            }
        }
        guard candidates.count == 1, candidates[0].firstBeat == nil else { return nil }
        return candidates[0].rowID
    }
}

/// Imports rekordbox's phrase analysis into the library (DJ mode spec Revision 2 § rekordbox phrases). Runs as an
/// exclusive job in the scanner's FIFO, after each rekordbox import, at launch and when access is granted. Only
/// `.EXT` files whose stamp changed are read. Failures reach the console log only.
actor RekordboxPhraseSync {
    private let store: LibraryStore
    private let scanner: LibraryScanner
    private let fileSystem: any LibraryFileSystem
    private let source: @Sendable () -> (any RekordboxAnalysisSource)?

    private var requested = false
    private var stopped = false
    private var jobTask: Task<Void, Never>?
    /// Per row, the stamp whose decode failure was already logged.
    private var loggedFailures: [UUID: Data] = [:]

    init(
        store: LibraryStore,
        scanner: LibraryScanner,
        fileSystem: any LibraryFileSystem,
        source: @escaping @Sendable () -> (any RekordboxAnalysisSource)?
    ) {
        self.store = store
        self.scanner = scanner
        self.fileSystem = fileSystem
        self.source = source
    }

    /// Queues a run; requests while one is queued or running collapse into one follow-up.
    func requestRun() {
        guard !self.stopped else { return }
        self.requested = true
        self.enqueueJobIfIdle()
    }

    func halt() {
        self.stopped = true
        self.requested = false
    }

    /// Test and teardown hook: returns once no run is queued or running.
    func waitUntilIdle() async {
        while let job = self.jobTask {
            await job.value
        }
    }

    private func enqueueJobIfIdle() {
        guard self.jobTask == nil, self.requested, !self.stopped else { return }
        self.requested = false
        let scanner = self.scanner
        self.jobTask = Task { [self] in
            await scanner.performExclusive { await self.run() }
            await self.jobFinished()
        }
    }

    private func jobFinished() {
        self.jobTask = nil
        self.enqueueJobIfIdle()
    }

    private func run() async {
        guard !self.stopped, let source = self.source() else { return }
        defer { source.close() }
        do {
            var caseSensitivity: [UUID: Bool] = [:]
            for root in try await self.store.roots() where root.isAvailable {
                caseSensitivity[root.id] = try? await self.fileSystem.volume(at: root.url).caseSensitive
            }
            let matcher = try await RekordboxAnalysisMatcher(self.store.rekordboxSnapshot(caseSensitivity: caseSensitivity))
            let stored = try await self.store.phraseStamps()
            // Claim rows first: a row two folders claim is ambiguous and skipped.
            var claims: [UUID: [URL]] = [:]
            for folder in try await source.trackFolders() {
                guard !self.stopped, !Task.isCancelled else { return }
                guard let dat = try? await source.read(folder.appendingPathComponent("ANLZ0000.DAT")),
                      let name = RekordboxAnalysisFile.fileName(dat: dat),
                      let rowID = matcher.rowID(fileName: name, firstBeat: RekordboxAnalysisFile.firstBeat(dat: dat))
                else { continue }
                claims[rowID, default: []].append(folder)
            }
            var writes: [RekordboxPhraseWrite] = []
            for (rowID, folders) in claims.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
                guard !self.stopped, !Task.isCancelled else { return }
                guard folders.count == 1 else {
                    phraseLogger.info("\(folders.count) analysis folders claim one row; skipped")
                    continue
                }
                if let write = await self.check(folders[0], rowID: rowID, source: source, stored: stored) {
                    writes.append(write)
                }
            }
            try await self.store.applyRekordboxPhrases(writes)
            phraseLogger.info("Phrase import: \(claims.count) rows matched, \(writes.count) updated")
        } catch {
            phraseLogger.error("Phrase import failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The write for a row's folder, or nil when its EXT is unchanged or unreadable.
    private func check(
        _ folder: URL,
        rowID: UUID,
        source: any RekordboxAnalysisSource,
        stored: [UUID: Data]
    ) async -> RekordboxPhraseWrite? {
        let ext = folder.appendingPathComponent("ANLZ0000.EXT")
        guard let stamp = try? await source.stamp(ext) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let stampData = try? encoder.encode(stamp), stored[rowID] != stampData else { return nil }
        let analysis = await (try? source.read(ext)).flatMap(RekordboxAnalysisFile.phrases(ext:))
        if analysis == nil, self.loggedFailures[rowID] != stampData {
            self.loggedFailures[rowID] = stampData
            phraseLogger.info("No phrases in \(ext.path, privacy: .public)")
        }
        return RekordboxPhraseWrite(rowID: rowID, phrases: analysis.map(RekordboxAnalysisFile.pack), stamp: stampData)
    }
}

import Foundation
import os

private let scanLogger = Logger(subsystem: "com.ampx.macos", category: "LibraryScanner")

typealias LibraryMetadataLoading = @Sendable (URL) async -> TrackMetadataLoader.Metadata

struct LibraryScanOutcome: Sendable, Equatable {
    let coverage: LibraryCoverage
    /// A file changed while it was being read; the run left it stale and wants one more scan.
    let needsFollowUp: Bool
}

enum LibraryScanError: Error, Equatable {
    /// A read failed and the root was no longer reachable: the run aborted without saving a degraded row.
    case rootUnreachable
}

/// Full-root scans (spec: "Scanning"). Every save carries the run's token, so a revoked run is stopped by the
/// store, not by cooperative cancellation. Scheduling lives in `LibraryScanner+Scheduling.swift`.
actor LibraryScanner {
    let store: LibraryStore
    let fileSystem: any LibraryFileSystem
    private let loadMetadata: LibraryMetadataLoading
    private let batchSize: Int
    private var progressSubscribers: [UUID: AsyncStream<ScanProgress>.Continuation] = [:]

    // Scheduling state (see LibraryScanner+Scheduling.swift).
    var queue: [UUID] = []
    var queued: Set<UUID> = []
    var runningRoot: UUID?
    var runningTask: Task<Void, Never>?
    var rescanRequested: Set<UUID> = []
    var drainTask: Task<Void, Never>?
    var concurrentRuns = 0
    var maxConcurrentRuns = 0

    init(
        store: LibraryStore,
        fileSystem: any LibraryFileSystem,
        loadMetadata: @escaping LibraryMetadataLoading = { await TrackMetadataLoader.load(from: $0) },
        batchSize: Int = LibraryStore.batchLimit
    ) {
        self.store = store
        self.fileSystem = fileSystem
        self.loadMetadata = loadMetadata
        self.batchSize = min(batchSize, LibraryStore.batchLimit)
    }

    func progress() -> AsyncStream<ScanProgress> {
        let (stream, continuation) = AsyncStream.makeStream(of: ScanProgress.self)
        let id = UUID()
        self.progressSubscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeProgressSubscriber(id) }
        }
        return stream
    }

    private func removeProgressSubscriber(_ id: UUID) {
        self.progressSubscribers[id] = nil
    }

    // MARK: - One run

    /// Steps 0–7 for one root.
    func scanOnce(rootID: UUID) async throws -> LibraryScanOutcome {
        // 0. Access.
        let token = try await self.store.beginScan(rootID: rootID)
        let root = try await self.store.resolveRoot(token: token)
        let volume: LibraryVolume
        do {
            volume = try await self.fileSystem.volume(at: root.url)
        } catch {
            try await self.store.markUnavailable(token: token)
            throw error
        }

        // 1. Integrity repair.
        var keys = try await self.store.rowKeys(rootID: rootID)
        let merges = LibraryReconciler.integrityMerges(rows: keys, caseSensitive: volume.caseSensitive)
        if !merges.isEmpty {
            try await self.store.applyIntegrityMerges(merges, token: token)
            keys = try await self.store.rowKeys(rootID: rootID)
        }

        // 2. Walk (stat only).
        self.publish(ScanProgress(rootID: rootID, phase: .walking, done: 0, total: 0))
        let walk: LibraryWalk
        do {
            walk = try await self.fileSystem.walk(root: root.url, volume: volume)
        } catch {
            if await !self.fileSystem.isReachable(root.url) {
                try await self.store.markUnavailable(token: token)
            }
            throw error
        }
        guard walk.coverage != .aborted, !Task.isCancelled else {
            return LibraryScanOutcome(coverage: .aborted, needsFollowUp: false)
        }

        // 3–4. Match and reconcile; read fingerprints for candidates only.
        self.publish(ScanProgress(rootID: rootID, phase: .reconciling, done: 0, total: walk.entries.count))
        var fingerprints: [String: Data] = [:]
        for path in LibraryReconciler.candidatePaths(rows: keys, walk: walk) {
            fingerprints[path] = try? await self.fileSystem.fingerprint(at: root.url.appendingPathComponent(path))
        }
        let plan = LibraryReconciler.reconcile(rows: keys, walk: walk, fingerprints: fingerprints)

        // 5. Commit structure, before any insert.
        let unreadable: Int = if case let .partial(folders) = walk.coverage {
            folders.count
        } else {
            0
        }
        try await self.store.applyStructure(plan, token: token, unreadableFolderCount: unreadable)

        // 6. Parse stale and new files in batches.
        let needsFollowUp = try await self.parse(
            self.parseItems(plan: plan, keys: keys, walk: walk), root: root, token: token
        )

        // 7. Finish (complete walks only).
        if walk.coverage == .complete {
            try await self.store.finishScan(token: token)
        }
        return LibraryScanOutcome(coverage: walk.coverage, needsFollowUp: needsFollowUp)
    }

    // MARK: - Parse

    private struct ParseItem {
        let id: UUID
        let isInsert: Bool
        let entry: LibraryEntry
    }

    private func parseItems(plan: LibraryReconciliation, keys: [LibraryRowKey], walk: LibraryWalk) -> [ParseItem] {
        let caseSensitive = walk.volume.caseSensitive
        let entries = Dictionary(
            walk.entries.map { (LibraryReconciler.pathKey($0.relativePath, caseSensitive: caseSensitive), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let stale = keys.filter { plan.staleIDs.contains($0.id) }.compactMap { row in
            entries[LibraryReconciler.pathKey(row.relativePath, caseSensitive: caseSensitive)]
                .map { ParseItem(id: row.id, isInsert: false, entry: $0) }
        }
        let inserts = plan.newEntries.map { ParseItem(id: UUID(), isInsert: true, entry: $0) }
        return (stale + inserts).sorted { $0.entry.relativePath < $1.entry.relativePath }
    }

    /// Returns whether a file changed mid-read and was left stale.
    private func parse(_ items: [ParseItem], root: LibraryRootSnapshot, token: LibraryScanToken) async throws -> Bool {
        var needsFollowUp = false
        var loggedFailures: Set<String> = []
        var done = 0
        self.publish(ScanProgress(rootID: root.id, phase: .parsing, done: 0, total: items.count))

        for batchStart in stride(from: 0, to: items.count, by: self.batchSize) {
            var writes: [LibraryParseWrite] = []
            for item in items[batchStart ..< min(batchStart + self.batchSize, items.count)] {
                let url = root.url.appendingPathComponent(item.entry.relativePath)
                let metadata = await self.loadMetadata(url)
                let fingerprint = try? await self.fileSystem.fingerprint(at: url)
                let after = try? await self.fileSystem.stat(at: url)

                if metadata.readFailed || fingerprint == nil || after == nil {
                    guard await self.fileSystem.isReachable(root.url) else {
                        try await self.store.markUnavailable(token: token)
                        throw LibraryScanError.rootUnreachable
                    }
                    if metadata.readFailed, loggedFailures.insert(item.entry.relativePath).inserted {
                        scanLogger.error("Could not read metadata: \(item.entry.relativePath, privacy: .public)")
                    }
                }
                // Never certify data read from a file that changed (or vanished) during the read.
                guard let after, after == item.entry.stat else {
                    needsFollowUp = true
                    continue
                }
                writes.append(LibraryParseWrite(
                    id: item.id, isInsert: item.isInsert, relativePath: item.entry.relativePath,
                    stat: item.entry.stat, metadata: metadata, fingerprint: fingerprint
                ))
            }
            // An interrupted run saves nothing from the batch in progress.
            try Task.checkCancellation()
            try await self.store.applyParsed(writes, token: token)
            done = min(batchStart + self.batchSize, items.count)
            self.publish(ScanProgress(rootID: root.id, phase: .parsing, done: done, total: items.count))
        }
        return needsFollowUp
    }

    func publish(_ progress: ScanProgress) {
        for continuation in self.progressSubscribers.values {
            continuation.yield(progress)
        }
    }
}

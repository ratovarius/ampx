import Foundation
import os

private let syncLogger = Logger(subsystem: "com.ampx.macos", category: "RekordboxSync")

enum RekordboxSyncStatus: Equatable, Sendable {
    /// No present source: nothing rekordbox-related is shown.
    case hidden
    /// Latest `lastImportAt` across present sources.
    case idle(lastSync: Date?)
    case syncing
}

struct RekordboxSyncState: Equatable, Sendable {
    let status: RekordboxSyncStatus
    let sources: [RekordboxSourceSnapshot]
}

/// Finds a rekordbox export at the top level of each root after its scans, and imports it when it changed
/// (rekordbox sync spec § `RekordboxSync`). Checks run as exclusive jobs in the scanner's FIFO, so they never
/// overlap a scan. Failures reach only the console log, never the UI.
actor RekordboxSync {
    private let store: LibraryStore
    private let scanner: LibraryScanner
    private let fileSystem: any LibraryFileSystem

    private var pending: Set<UUID> = []
    private var forced: Set<UUID> = []
    private var jobTask: Task<Void, Never>?
    private var listeners: [Task<Void, Never>] = []
    private var stopped = false
    private var syncing = false
    /// Tokens of the running job, taken before discovery so a stop, removal or relocation at any point revokes them.
    private var jobTokens: [UUID: RekordboxSyncToken] = [:]
    /// Roots whose next finished scan re-checks every present export: their rows are new to the library.
    private var refreshOnScan: Set<UUID> = []
    /// Per root, the stamp whose parse failed last, to log a repeat at `.error`.
    private var failedStamps: [UUID: RekordboxFileStamp] = [:]
    private var lastState = RekordboxSyncState(status: .hidden, sources: [])
    private var subscribers: [UUID: AsyncStream<RekordboxSyncState>.Continuation] = [:]

    init(store: LibraryStore, scanner: LibraryScanner, fileSystem: any LibraryFileSystem) {
        self.store = store
        self.scanner = scanner
        self.fileSystem = fileSystem
    }

    /// Subscribes before returning, so the `finished` events of scans requested afterwards are seen.
    func start() async {
        let progress = await self.scanner.progress()
        let changes = await self.store.changes()
        self.listeners = [
            Task { [weak self] in
                for await event in progress where event.phase == .finished {
                    await self?.scanFinished(rootID: event.rootID)
                }
            },
            Task { [weak self] in
                for await change in changes {
                    switch change {
                    case .rekordboxSourcesChanged, .rootRemoved:
                        await self?.publishIfIdle()
                    case .rootsChanged, .rowsChanged:
                        break
                    }
                }
            },
        ]
        await self.publishState()
    }

    /// Stops listening, revokes the check in progress, and waits for the current job to end.
    func stop() async {
        await self.halt()
        await self.jobTask?.value
    }

    /// `stop()` without the wait: the engine halts the sync, stops the scanner (dropping a queued check),
    /// then waits with `waitUntilIdle()`, so a check queued behind a long scan never delays shutdown.
    func halt() async {
        self.stopped = true
        self.listeners.forEach { $0.cancel() }
        self.listeners.removeAll()
        self.pending.removeAll()
        for rootID in self.jobTokens.keys {
            await self.store.revokeRekordboxSync(rootID: rootID)
        }
    }

    func requestCheck(rootID: UUID, force: Bool = false) {
        guard !self.stopped else { return }
        self.pending.insert(rootID)
        if force {
            self.forced.insert(rootID)
        }
        self.enqueueJobIfIdle()
    }

    /// A root was added or relocated. After its next scan, every present export is checked again even if unchanged,
    /// so rows that only now joined the library receive its values.
    func rootAdded(_ rootID: UUID) {
        self.refreshOnScan.insert(rootID)
    }

    private func scanFinished(rootID: UUID) async {
        guard self.refreshOnScan.remove(rootID) != nil else {
            self.requestCheck(rootID: rootID)
            return
        }
        self.requestCheck(rootID: rootID, force: true)
        for source in await (try? self.store.rekordboxSources()) ?? [] where source.isPresent {
            self.requestCheck(rootID: source.rootID, force: true)
        }
    }

    func state() -> RekordboxSyncState {
        self.lastState
    }

    func states() -> AsyncStream<RekordboxSyncState> {
        let (stream, continuation) = AsyncStream.makeStream(of: RekordboxSyncState.self)
        let id = UUID()
        self.subscribers[id] = continuation
        continuation.yield(self.lastState)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    /// Test and teardown hook: returns once no check is queued or running.
    func waitUntilIdle() async {
        while let job = self.jobTask {
            await job.value
        }
    }

    // MARK: - Jobs

    private func enqueueJobIfIdle() {
        guard self.jobTask == nil, !self.pending.isEmpty, !self.stopped else { return }
        let scanner = self.scanner
        self.jobTask = Task { [self] in
            await scanner.performExclusive { await self.runJob() }
            await self.jobFinished()
        }
    }

    private func jobFinished() {
        self.jobTask = nil
        self.enqueueJobIfIdle()
    }

    private func runJob() async {
        let requested = self.pending
        let forced = self.forced
        self.pending.removeAll()
        self.forced.removeAll()
        guard !self.stopped, let roots = try? await self.store.roots() else { return }
        defer { self.jobTokens.removeAll() }
        for root in roots where requested.contains(root.id) && root.isAvailable {
            self.jobTokens[root.id] = try? await self.store.beginRekordboxSync(rootID: root.id)
        }
        guard !self.stopped else { return }

        var due: [(root: LibraryRootSnapshot, file: LibraryTopLevelFile)] = []
        for root in roots where self.jobTokens[root.id] != nil {
            if let file = await self.discover(in: root.url) {
                due.append((root, file))
            } else {
                try? await self.store.markRekordboxSourceAbsent(rootID: root.id)
            }
        }
        let sources = await Dictionary(
            ((try? self.store.rekordboxSources()) ?? []).map { ($0.rootID, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for (root, file) in due.sorted(by: { $0.file.stamp.modifiedAt < $1.file.stamp.modifiedAt }) {
            guard !self.stopped, !Task.isCancelled else { return }
            let source = sources[root.id]
            let unchanged = source?.isPresent == true && source?.fileName == file.name && source?.stamp == file.stamp
            if unchanged, !forced.contains(root.id) {
                continue
            }
            guard let token = self.jobTokens[root.id] else { continue }
            await self.importExport(file, root: root, roots: roots, token: token)
        }
        await self.publishState()
    }

    /// The newest top-level `.xml` that sniffs as a rekordbox export; read errors skip a file.
    private func discover(in root: URL) async -> LibraryTopLevelFile? {
        let files: [LibraryTopLevelFile]
        do {
            files = try await self.fileSystem.topLevelFiles(in: root, pathExtension: "xml")
        } catch {
            syncLogger.info("Cannot list \(root.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        var exports: [LibraryTopLevelFile] = []
        for file in files {
            do {
                let prefix = try await self.fileSystem.readPrefix(of: file.url, length: RekordboxCollectionParser.sniffLength)
                if RekordboxCollectionParser.isCollectionExport(prefix: prefix) {
                    exports.append(file)
                }
            } catch {
                syncLogger.info("Cannot read \(file.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return exports.max {
            $0.stamp.modifiedAt != $1.stamp.modifiedAt ? $0.stamp.modifiedAt < $1.stamp.modifiedAt : $0.name > $1.name
        }
    }

    private func importExport(
        _ file: LibraryTopLevelFile,
        root: LibraryRootSnapshot,
        roots: [LibraryRootSnapshot],
        token: RekordboxSyncToken
    ) async {
        defer { self.syncing = false }
        do {
            let data: Data
            do {
                data = try await self.fileSystem.readAll(of: file.url)
            } catch {
                syncLogger.info("Cannot read \(file.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return
            }
            var caseSensitivity: [UUID: Bool] = [:]
            for candidate in roots where candidate.isAvailable {
                caseSensitivity[candidate.id] = try? await self.fileSystem.volume(at: candidate.url).caseSensitive
            }
            // Parse (about 1.5 s for a 40 MB export) and plan off this actor, while the store builds the snapshot.
            async let snapshot = self.store.rekordboxSnapshot(caseSensitivity: caseSensitivity)
            let collection = try await Task.detached(priority: .utility) { try RekordboxCollectionParser.parse(data) }.value
            let library = try await snapshot
            guard !self.stopped, !Task.isCancelled else { return }
            // Only a parsed export shows as syncing: failures never reach the UI.
            self.syncing = true
            await self.publishState()
            let name = file.name, rootID = root.id
            let plan = await Task.detached(priority: .utility) {
                RekordboxImportPlanner.plan(collection, fileName: name, sourceRootID: rootID, library: library)
            }.value
            try await self.store.applyRekordbox(plan, fileName: file.name, stamp: file.stamp, token: token)
            self.failedStamps[root.id] = nil
            syncLogger.info("Imported \(file.name, privacy: .public): \(plan.report.matched) matched, \(plan.report.updated) updated")
        } catch let error as RekordboxParseError {
            let repeated = self.failedStamps[root.id] == file.stamp
            self.failedStamps[root.id] = file.stamp
            if repeated {
                syncLogger.error("\(file.url.path, privacy: .public) failed to parse again: \(String(describing: error), privacy: .public)")
            } else {
                syncLogger
                    .info(
                        "\(file.url.path, privacy: .public) did not parse (may still be writing): \(String(describing: error), privacy: .public)"
                    )
            }
        } catch LibraryStoreError.revokedToken, LibraryStoreError.unknownRoot {
            syncLogger.debug("Check of \(root.id, privacy: .public) revoked")
        } catch {
            syncLogger.error("Import of \(file.url.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - State

    private func publishIfIdle() async {
        guard !self.syncing else { return }
        await self.publishState()
    }

    private func publishState() async {
        let sources = await (try? self.store.rekordboxSources()) ?? self.lastState.sources
        let present = sources.filter(\.isPresent)
        let status: RekordboxSyncStatus = if self.syncing {
            .syncing
        } else if present.isEmpty {
            .hidden
        } else {
            .idle(lastSync: present.compactMap(\.lastImportAt).max())
        }
        let state = RekordboxSyncState(status: status, sources: sources.sorted { $0.rootID.uuidString < $1.rootID.uuidString })
        guard state != self.lastState else { return }
        self.lastState = state
        for continuation in self.subscribers.values {
            continuation.yield(state)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        self.subscribers[id] = nil
    }
}

import Foundation
import os
import SwiftData

/// Throttle timing, injectable so tests control the clock and the trailing delay.
struct LibraryIndexTiming: Sendable {
    var throttle: Duration = .seconds(1)
    var now: @Sendable () -> ContinuousClock.Instant = { .now }
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    static let live = LibraryIndexTiming()
}

/// In-memory row snapshot with its own reader contexts (spec: "Index and query semantics", "Change publication").
/// Queries never go through the writer and never wait for scan commits.
actor LibraryIndex {
    private let container: ModelContainer
    private let timing: LibraryIndexTiming
    private let listener = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    private var rowsByRoot: [UUID: [LibraryRow]] = [:]
    private var allRows: [LibraryRow]?
    private var isBuilt = false
    private var version: UInt64 = 0
    private var versionSubscribers: [UUID: AsyncStream<UInt64>.Continuation] = [:]

    private var lastRefetch: [UUID: ContinuousClock.Instant] = [:]
    private var trailingGeneration: [UUID: Int] = [:]
    private var pendingTrailing: Set<UUID> = []
    private var trailingTasks: [Task<Void, Never>] = []
    /// Test hook: per-root refetches after the first build.
    private(set) var refetchCount = 0

    /// Subscribes to `changes` immediately, before any snapshot exists.
    init(container: ModelContainer, changes: AsyncStream<LibraryChange>, timing: LibraryIndexTiming = .live) {
        self.container = container
        self.timing = timing
        let task = Task { [weak self] in
            for await change in changes {
                await self?.apply(change)
            }
        }
        self.listener.withLock { $0 = task }
    }

    // MARK: - Reads

    func query(_ request: LibraryQuery, generation: UInt64) throws -> LibraryResult {
        let rows = try self.snapshot()
        return request.evaluate(rows: rows, snapshotVersion: self.version, generation: generation)
    }

    /// Latest rows for `ids`, in snapshot order; ids no longer present are dropped.
    func rows(ids: Set<UUID>) throws -> [LibraryRow] {
        try self.snapshot().filter { ids.contains($0.id) }
    }

    func versions() -> AsyncStream<UInt64> {
        let (stream, continuation) = AsyncStream.makeStream(of: UInt64.self)
        let id = UUID()
        self.versionSubscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeVersionSubscriber(id) }
        }
        return stream
    }

    func stop() {
        self.listener.withLock { $0?.cancel() }
        self.trailingTasks.forEach { $0.cancel() }
        self.trailingTasks.removeAll()
        self.versionSubscribers.values.forEach { $0.finish() }
        self.versionSubscribers.removeAll()
    }

    /// Test hook: waits for scheduled trailing refetches (including superseded ones) to finish.
    func waitForPendingRefetches() async {
        let tasks = self.trailingTasks
        self.trailingTasks.removeAll()
        for task in tasks {
            await task.value
        }
    }

    // MARK: - Change application

    private func apply(_ change: LibraryChange) {
        // No snapshot yet: the lazy first build reads current state, so nothing can be lost.
        guard self.isBuilt else { return }
        switch change {
        case let .rootRemoved(rootID):
            self.cancelTrailing(rootID)
            self.rowsByRoot[rootID] = nil
            self.bumpVersion()
        case let .rootsChanged(rootID):
            // Root location/availability gates enqueue: rebuild now, superseding any pending row refetch.
            self.cancelTrailing(rootID)
            self.refetch(rootID)
        case let .rowsChanged(rootID):
            self.throttledRefetch(rootID)
        }
    }

    /// At most one re-fetch per root per `throttle`, plus one trailing re-fetch after the last change.
    private func throttledRefetch(_ rootID: UUID) {
        let now = self.timing.now()
        guard let last = self.lastRefetch[rootID], now - last < self.timing.throttle else {
            self.refetch(rootID)
            return
        }
        guard self.pendingTrailing.insert(rootID).inserted else { return }
        let generation = self.trailingGeneration[rootID, default: 0]
        let delay = self.timing.throttle - (now - last)
        let sleep = self.timing.sleep
        self.trailingTasks.append(Task { [weak self] in
            try? await sleep(delay)
            await self?.fireTrailing(rootID, generation: generation)
        })
    }

    private func fireTrailing(_ rootID: UUID, generation: Int) {
        guard self.trailingGeneration[rootID, default: 0] == generation, self.pendingTrailing.remove(rootID) != nil else { return }
        self.refetch(rootID)
    }

    private func cancelTrailing(_ rootID: UUID) {
        self.trailingGeneration[rootID, default: 0] += 1
        self.pendingTrailing.remove(rootID)
    }

    private func refetch(_ rootID: UUID) {
        self.lastRefetch[rootID] = self.timing.now()
        self.refetchCount += 1
        do {
            let context = ModelContext(self.container) // fresh context: sees every committed save
            if let root = try context.fetch(FetchDescriptor<LibraryRoot>(predicate: #Predicate { $0.id == rootID })).first {
                let tracks = try context.fetch(FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.rootID == rootID }))
                self.rowsByRoot[rootID] = tracks.map { Self.row($0, root: root) }
            } else {
                self.rowsByRoot[rootID] = nil
            }
        } catch {
            Logger(subsystem: "com.ampx.macos", category: "LibraryIndex")
                .error("Refetch failed: \(error.localizedDescription, privacy: .public)")
        }
        self.bumpVersion()
    }

    private func bumpVersion() {
        self.allRows = nil
        self.version += 1
        for continuation in self.versionSubscribers.values {
            continuation.yield(self.version)
        }
    }

    private func removeVersionSubscriber(_ id: UUID) {
        self.versionSubscribers[id] = nil
    }

    // MARK: - Snapshot

    private func snapshot() throws -> [LibraryRow] {
        if !self.isBuilt {
            let context = ModelContext(self.container)
            let roots = try context.fetch(FetchDescriptor<LibraryRoot>())
            let tracks = try context.fetch(FetchDescriptor<LibraryTrack>())
            let rootsByID = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0) })
            self.rowsByRoot = Dictionary(grouping: tracks.compactMap { track in
                rootsByID[track.rootID].map { Self.row(track, root: $0) }
            }, by: \.rootID)
            self.isBuilt = true
        }
        if let rows = self.allRows {
            return rows
        }
        let rows = self.rowsByRoot.values.flatMap { $0 }
        self.allRows = rows
        return rows
    }

    private static func row(_ track: LibraryTrack, root: LibraryRoot) -> LibraryRow {
        LibraryRow(
            id: track.id,
            rootID: track.rootID,
            url: URL(fileURLWithPath: root.displayPath, isDirectory: true).appendingPathComponent(track.relativePath),
            title: track.title,
            artist: track.artist,
            album: track.album,
            albumArtist: track.albumArtist,
            genre: track.genre,
            trackNumber: track.trackNumber,
            duration: track.duration,
            fileSize: track.fileSize,
            bpm: track.bpm,
            musicalKey: track.musicalKey,
            bitrate: track.bitrate,
            bitrateIsDerived: track.bitrateIsDerived,
            codec: track.codec,
            isAvailable: !track.isMissing && root.isAvailable,
            searchKey: LibraryRow.makeSearchKey(
                title: track.title, artist: track.artist, album: track.album, albumArtist: track.albumArtist
            )
        )
    }
}

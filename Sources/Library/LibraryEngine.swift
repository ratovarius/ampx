import Foundation

struct LibraryEngineConfiguration: Sendable {
    /// nil keeps the store in memory (tests).
    var storeURL: URL? = LibraryContainerFactory.defaultURL
    var startupFlag: any LibraryStartupFlag
    /// The one store `PlaylistManager` uses (spec: "Playlist continuity across relaunch").
    var bookmarkStore: SecurityScopedBookmarkStore
    var fileSystem: any LibraryFileSystem = FoundationLibraryFileSystem()
    var loadMetadata: LibraryMetadataLoading = { await TrackMetadataLoader.load(from: $0) }
    var storeDependencies: @Sendable (any LibraryStartupFlag) -> LibraryStoreDependencies = {
        LibraryStoreDependencies(startupFlag: $0)
    }

    var watcherLatency: TimeInterval = 2
    var indexTiming: LibraryIndexTiming = .live
}

/// Composes store, scanner, index and watcher, and coordinates root operations (spec: "Architecture").
/// Dormant until a caller invokes `openIfConfigured` or `open`; no app code does so in L1.
actor LibraryEngine {
    private final class WeakEngine: @unchecked Sendable {
        weak var engine: LibraryEngine?
    }

    nonisolated let index: LibraryIndex
    nonisolated let bookmarkStore: SecurityScopedBookmarkStore
    nonisolated let store: LibraryStore
    nonisolated let scanner: LibraryScanner
    nonisolated let watcher: LibraryWatcher
    /// Imports rekordbox exports found at roots' top level after their scans (rekordbox sync spec).
    nonisolated let rekordbox: RekordboxSync
    private var watchedURLs: [UUID: URL] = [:]
    private var listener: Task<Void, Never>?
    private var pendingRewatches: [Task<Void, Never>] = []

    private init(
        store: LibraryStore,
        index: LibraryIndex,
        scanner: LibraryScanner,
        watcher: LibraryWatcher,
        rekordbox: RekordboxSync,
        bookmarkStore: SecurityScopedBookmarkStore
    ) {
        self.rekordbox = rekordbox
        self.store = store
        self.index = index
        self.scanner = scanner
        self.watcher = watcher
        self.bookmarkStore = bookmarkStore
    }

    /// Flag false → nil without opening a container. Flag true → open; no roots → clear the flag, stop, nil;
    /// otherwise start access, watch, and queue one catch-up scan per available root.
    static func openIfConfigured(_ configuration: LibraryEngineConfiguration) async throws -> LibraryEngine? {
        guard configuration.startupFlag.hasRoots else { return nil }
        let engine = try await self.open(configuration)
        if try await engine.store.clearStartupFlagIfEmpty() {
            await engine.stop()
            return nil
        }
        return engine
    }

    /// Opens unconditionally — for L2's first "Add Library Folder…".
    static func open(_ configuration: LibraryEngineConfiguration) async throws -> LibraryEngine {
        let container = try LibraryContainerFactory.make(url: configuration.storeURL)
        let store = LibraryStore(modelContainer: container, dependencies: configuration.storeDependencies(configuration.startupFlag))
        let index = await LibraryIndex(container: container, changes: store.changes(), timing: configuration.indexTiming)
        let scanner = LibraryScanner(store: store, fileSystem: configuration.fileSystem, loadMetadata: configuration.loadMetadata)
        let reference = WeakEngine()
        let watcher = LibraryWatcher(latency: configuration.watcherLatency) { event in
            // Never call back into the watcher synchronously from its queue.
            Task { await reference.engine?.handle(event) }
        }
        let engine = LibraryEngine(
            store: store,
            index: index,
            scanner: scanner,
            watcher: watcher,
            rekordbox: RekordboxSync(store: store, scanner: scanner, fileSystem: configuration.fileSystem),
            bookmarkStore: configuration.bookmarkStore
        )
        reference.engine = engine
        try await engine.start(changes: store.changes())
        return engine
    }

    private func start(changes: AsyncStream<LibraryChange>) async throws {
        self.listener = Task { [weak self] in
            for await change in changes {
                await self?.follow(change)
            }
        }
        await self.watcher.startVolumeObservation()
        // Before the launch scans, so their `finished` events trigger the rekordbox checks.
        await self.rekordbox.start()
        for root in try await self.store.startAccessForAvailableRoots() {
            self.watch(root)
            await self.scanner.requestScan(rootID: root.id)
        }
    }

    // MARK: - Roots

    func roots() async throws -> [LibraryRootSnapshot] {
        try await self.store.roots()
    }

    func progress() async -> AsyncStream<ScanProgress> {
        await self.scanner.progress()
    }

    func addRoot(url: URL) async throws -> UUID {
        let id = try await self.store.addRoot(url: url)
        try await self.syncWatch(id)
        await self.scanner.requestScan(rootID: id)
        return id
    }

    func relocateRoot(id: UUID, to url: URL) async throws {
        await self.scanner.cancelScans(rootID: id)
        try await self.store.relocateRoot(id: id, to: url)
        try await self.syncWatch(id)
        await self.scanner.requestScan(rootID: id)
    }

    func removeRoot(id: UUID) async throws {
        await self.scanner.cancelScans(rootID: id)
        try await self.store.removeRoot(id: id)
        self.unwatch(id)
    }

    // MARK: - Events

    func handle(_ event: LibraryWatchEvent) async {
        switch event {
        case let .changed(rootID):
            await self.scanner.requestScan(rootID: rootID)
        case let .rootChanged(rootID):
            // The watched path is stale; step 0 of the next run re-resolves the bookmark.
            self.unwatch(rootID)
            await self.scanner.cancelScans(rootID: rootID)
            await self.scanner.requestScan(rootID: rootID)
            // Re-watch from the scan's outcome, not from whichever change events it happens to publish: a root
            // back at the same path with an unchanged status publishes none.
            let scanner = self.scanner
            self.pendingRewatches.append(Task {
                await scanner.waitUntilIdle()
                try? await self.syncWatch(rootID)
            })
        case .mounted:
            for root in await (try? self.store.roots()) ?? [] where !root.isAvailable {
                await self.scanner.requestScan(rootID: root.id)
            }
        case let .unmounted(volume):
            let volumePath = volume.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            for root in await (try? self.store.roots()) ?? []
                where root.url.standardizedFileURL.resolvingSymlinksInPath().pathComponents.starts(with: volumePath)
            {
                await self.scanner.cancelScans(rootID: root.id)
                try? await self.store.markUnavailable(id: root.id)
                self.unwatch(root.id)
            }
        }
    }

    /// Test and teardown hook: returns once no scan is queued or running.
    func waitUntilIdle() async {
        await self.scanner.waitUntilIdle()
        await self.rekordbox.waitUntilIdle()
        while !self.pendingRewatches.isEmpty {
            let tasks = self.pendingRewatches
            self.pendingRewatches.removeAll()
            for task in tasks {
                await task.value
            }
        }
    }

    func stop() async {
        self.listener?.cancel()
        self.listener = nil
        self.pendingRewatches.forEach { $0.cancel() }
        self.pendingRewatches.removeAll()
        await self.rekordbox.halt()
        await self.scanner.stop()
        await self.rekordbox.waitUntilIdle()
        await self.watcher.stop()
        self.watchedURLs.removeAll()
        await self.index.stop()
        await self.store.stopAllAccess()
    }

    // MARK: - Watching

    /// Keeps the watcher on each available root's current location (scans can change availability).
    private func follow(_ change: LibraryChange) async {
        switch change {
        case let .rootsChanged(rootID):
            try? await self.syncWatch(rootID)
        case let .rootRemoved(rootID):
            self.unwatch(rootID)
        case .rowsChanged, .rekordboxSourcesChanged:
            break
        }
    }

    private func syncWatch(_ rootID: UUID) async throws {
        guard let root = try await self.store.roots().first(where: { $0.id == rootID }), root.isAvailable else {
            self.unwatch(rootID)
            return
        }
        self.watch(root)
    }

    private func watch(_ root: LibraryRootSnapshot) {
        guard self.watchedURLs[root.id] != root.url else { return }
        self.watcher.bind(rootID: root.id, url: root.url)
        self.watchedURLs[root.id] = root.url
    }

    private func unwatch(_ rootID: UUID) {
        guard self.watchedURLs.removeValue(forKey: rootID) != nil else { return }
        self.watcher.unbind(rootID: rootID)
    }
}

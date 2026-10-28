import AppKit
import Combine
import Foundation

/// What the browser model needs from the engine; tests substitute controlled closures.
struct LibraryBrowserServices: Sendable {
    var query: @Sendable (LibraryQuery, UInt64) async throws -> LibraryResult
    /// Latest snapshot rows for ids, used to re-check availability at action time.
    var rows: @Sendable (Set<UUID>) async throws -> [LibraryRow]
    var versions: @Sendable () async -> AsyncStream<UInt64>
    var progress: @Sendable () async -> AsyncStream<ScanProgress>
    var roots: @Sendable () async throws -> [LibraryRootSnapshot]

    static func live(_ engine: LibraryEngine) -> LibraryBrowserServices {
        LibraryBrowserServices(
            query: { try await engine.index.query($0, generation: $1) },
            rows: { try await engine.index.rows(ids: $0) },
            versions: { await engine.index.versions() },
            progress: { await engine.progress() },
            roots: { try await engine.roots() }
        )
    }
}

/// The state the L2 Library module draws (spec: "Observation", "Actions"). Root management stays on
/// `LibraryEngine`; L2 calls it with URLs from its own panels. Dropping a browser never stops the engine.
@MainActor
final class LibraryBrowserModel: ObservableObject {
    @Published private(set) var query = LibraryQuery()
    @Published private(set) var rows: [LibraryRow] = []
    @Published private(set) var facets = LibraryFacetCounts(genres: [:], artists: [:], albums: [:])
    @Published var selection: Set<UUID> = []
    @Published var focusedID: UUID?
    @Published private(set) var progress: ScanProgress?
    @Published private(set) var roots: [LibraryRootSnapshot] = []
    /// Unavailable rows in the whole library (the footer's n MISSING), whatever the query filters.
    @Published private(set) var unavailableTotal = 0

    private let services: LibraryBrowserServices
    private let playlist: PlaylistManager
    private let bookmarkStore: SecurityScopedBookmarkStore
    private let beep: @MainActor () -> Void
    private var generation: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var subscriptions: [Task<Void, Never>] = []

    init(
        services: LibraryBrowserServices,
        playlist: PlaylistManager,
        bookmarkStore: SecurityScopedBookmarkStore,
        beep: @escaping @MainActor () -> Void = { NSSound.beep() }
    ) {
        self.services = services
        self.playlist = playlist
        self.bookmarkStore = bookmarkStore
        self.beep = beep

        let versions = services.versions
        let progress = services.progress
        self.subscriptions = [
            Task { [weak self] in
                for await _ in await versions() {
                    // A cancelled stream still hands over an element buffered before `stop()`.
                    guard let self, !Task.isCancelled else { return }
                    self.refresh()
                    await self.refreshRoots()
                }
            },
            Task { [weak self] in
                for await event in await progress() where !Task.isCancelled {
                    self?.progress = event
                }
            },
        ]
    }

    func setQuery(_ query: LibraryQuery) {
        self.query = query
        self.refresh()
    }

    /// Re-runs the current query. Each request carries a new generation; a result is published only if it is
    /// still the latest, because cancellation alone cannot stop a request that already completed.
    func refresh() {
        self.generation &+= 1
        let generation = self.generation
        let query = self.query
        let run = self.services.query
        self.refreshTask?.cancel()
        self.refreshTask = Task { [weak self] in
            guard let result = try? await run(query, generation) else { return }
            guard let self, !Task.isCancelled, result.generation == self.generation else { return }
            self.apply(result)
        }
    }

    /// Replace (Enter) or append (⌘-Enter) the selection's available rows, in displayed order. A clicked row
    /// outside the selection acts alone. Availability is re-checked against the latest snapshot.
    func enqueue(append: Bool, clickedID: UUID?) async {
        let ids: Set<UUID> = if let clickedID, !self.selection.contains(clickedID) {
            [clickedID]
        } else {
            self.selection
        }
        let displayed = self.rows.map(\.id).filter { ids.contains($0) }
        let latest = await (try? self.services.rows(Set(displayed))) ?? []
        let latestByID = Dictionary(latest.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let available = displayed.compactMap { latestByID[$0] }.filter(\.isAvailable)
        guard !available.isEmpty else {
            self.beep()
            return
        }

        // Playlist continuity: the shared bookmark store keeps restored tracks under these roots playable.
        let roots = await (try? self.services.roots()) ?? self.roots
        for rootID in Set(available.map(\.rootID)) {
            if let url = roots.first(where: { $0.id == rootID })?.url {
                self.bookmarkStore.saveBookmark(for: url)
            }
        }

        let tracks = available.map { $0.makeTrack() }
        if append {
            self.playlist.addTracks(tracks)
        } else {
            self.playlist.clearPlaylist()
            self.playlist.addTracks(tracks)
            self.playlist.playTrack(at: 0)
        }
    }

    func stop() {
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.subscriptions.forEach { $0.cancel() }
        self.subscriptions.removeAll()
    }

    /// Test hook: waits for the latest refresh to finish or be dropped.
    func waitForRefresh() async {
        await self.refreshTask?.value
    }

    private func apply(_ result: LibraryResult) {
        self.rows = result.rows
        self.facets = result.facets
        self.unavailableTotal = result.unavailableTotal
        let present = Set(result.rows.map(\.id))
        self.selection.formIntersection(present)
        if let focused = self.focusedID, !present.contains(focused) {
            self.focusedID = nil
        }
    }

    /// Loads the root list now, e.g. when a browser opens before any library change has been published.
    func reloadRoots() async {
        await self.refreshRoots()
    }

    private func refreshRoots() async {
        if let roots = try? await self.services.roots() {
            self.roots = roots
        }
    }
}

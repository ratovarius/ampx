import Foundation

/// What Automix reads from the library: a track's grid, phrases and class, and the continuation pool.
protocol AutomixLibrary: Sendable {
    /// `.unknown` when the file is not in the library or its row is unavailable.
    func track(url: URL, duration: Double) async -> (row: LibraryRow?, track: AutomixTrack)
    /// Available rows only. A nil filter (never set) means the whole library.
    func pool(_ pickFrom: PickPool, filter: LibraryQuery?) async -> [LibraryRow]
    /// Saves the bookmark of the row's library root, so the Playlist can restore a track picked from it.
    func registerRoot(of row: LibraryRow) async
}

/// `AutomixLibrary` over the library engine's index and store.
struct LibraryEngineAutomixLibrary: AutomixLibrary {
    let index: LibraryIndex
    let store: LibraryStore
    let bookmarkStore: SecurityScopedBookmarkStore?

    init(index: LibraryIndex, store: LibraryStore, bookmarkStore: SecurityScopedBookmarkStore? = nil) {
        self.index = index
        self.store = store
        self.bookmarkStore = bookmarkStore
    }

    init(engine: LibraryEngine) {
        self.init(index: engine.index, store: engine.store, bookmarkStore: engine.bookmarkStore)
    }

    func track(url: URL, duration: Double) async -> (row: LibraryRow?, track: AutomixTrack) {
        let length = duration > 0 ? duration : 0
        guard let row = try? await self.index.row(url: url), row.isAvailable else {
            return (nil, .unknown(duration: length))
        }
        let total = length > 0 ? length : row.duration
        let data = try? await self.store.mixData(rowID: row.id)
        let grid = data?.beatGrid.flatMap(RekordboxBeatGrid.unpack).flatMap { MixGrid(segments: $0, duration: total) }
        let phrases = data?.phrases.flatMap(RekordboxAnalysisFile.unpack)
        return (row, AutomixTrack(duration: total, trackClass: row.trackClass, grid: grid, phrases: phrases))
    }

    func pool(_ pickFrom: PickPool, filter: LibraryQuery?) async -> [LibraryRow] {
        var rows: [LibraryRow]?
        if pickFrom == .currentView, var filter {
            // Missing rows are never in the pool, so the MISSING view adds nothing (spec § Continuation).
            filter.onlyUnavailable = false
            rows = try? await self.index.rows(matching: filter)
        } else {
            rows = try? await self.index.everyRow()
        }
        return (rows ?? []).filter(\.isAvailable)
    }

    func registerRoot(of row: LibraryRow) async {
        guard let bookmarkStore = self.bookmarkStore,
              let url = await (try? self.store.roots())?.first(where: { $0.id == row.rootID })?.url
        else { return }
        bookmarkStore.saveBookmark(for: url)
    }
}

import Foundation

/// What Automix reads from the library: a track's grid, phrases and class, and the continuation pool.
protocol AutomixLibrary: Sendable {
    /// `.unknown` when the file is not in the library or its row is unavailable.
    func track(url: URL, duration: Double) async -> (row: LibraryRow?, track: AutomixTrack)
    /// Available rows only. A nil filter (never set) means the whole library.
    func pool(_ pickFrom: PickPool, filter: LibraryQuery?) async -> [LibraryRow]
}

/// `AutomixLibrary` over the library engine's index and store.
struct LibraryEngineAutomixLibrary: AutomixLibrary {
    let index: LibraryIndex
    let store: LibraryStore

    init(index: LibraryIndex, store: LibraryStore) {
        self.index = index
        self.store = store
    }

    init(engine: LibraryEngine) {
        self.init(index: engine.index, store: engine.store)
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
        let rows: [LibraryRow]? = if pickFrom == .currentView, let filter {
            try? await self.index.rows(matching: filter)
        } else {
            try? await self.index.everyRow()
        }
        return (rows ?? []).filter(\.isAvailable)
    }
}

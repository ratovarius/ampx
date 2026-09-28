import Foundation

/// What the toolbar, facet lists, MISSING button and column headers have chosen (Library Module spec
/// § Query mapping). `search` holds committed text only, never IME marked text.
struct LibraryFilterState: Codable, Equatable, Sendable {
    var search = ""
    var genres: Set<LibraryFacetValue> = []
    var artists: Set<LibraryFacetValue> = []
    var bpmMin: Double?
    var bpmMax: Double?
    var showMissing = false
    private(set) var sort: LibrarySortColumn = .artist
    private(set) var ascending = true

    var query: LibraryQuery {
        var query = LibraryQuery(
            search: self.search,
            genres: self.genres,
            artists: self.artists,
            sort: self.sort,
            ascending: self.ascending
        )
        query.bpmRange = self.bpmRange
        query.onlyUnavailable = self.showMissing
        return query
    }

    /// A blank box is unbounded; min > max swaps.
    private var bpmRange: ClosedRange<Double>? {
        switch (self.bpmMin, self.bpmMax) {
        case (nil, nil): nil
        case let (low?, nil): low ... .greatestFiniteMagnitude
        case let (nil, high?): 0 ... high
        case let (low?, high?): min(low, high) ... max(low, high)
        }
    }

    /// CLEAR: search, BPM range, facets and the MISSING view; the sort stays.
    mutating func clear() {
        self = LibraryFilterState(sort: self.sort, ascending: self.ascending)
    }

    /// A header click: a new column sorts ascending, the same column reverses.
    mutating func sortBy(_ column: LibrarySortColumn) {
        if self.sort == column {
            self.ascending.toggle()
        } else {
            self.sort = column
            self.ascending = true
        }
    }

    mutating func restoreSort(_ column: LibrarySortColumn, ascending: Bool) {
        self.sort = column
        self.ascending = ascending
    }

    /// Hiding the sorted column falls back to ARTIST ascending.
    mutating func columnsChanged(_ columns: LibraryColumnSet) {
        guard let column = LibraryColumn.column(for: self.sort), !columns.visible.contains(column) else { return }
        self.sort = .artist
        self.ascending = true
    }

    /// Click selects a single value (clicking the selected one again clears the facet); ⌘-click toggles.
    mutating func facetClick(
        _ value: LibraryFacetValue,
        facet: WritableKeyPath<LibraryFilterState, Set<LibraryFacetValue>>,
        command: Bool
    ) {
        if command {
            if self[keyPath: facet].contains(value) {
                self[keyPath: facet].remove(value)
            } else {
                self[keyPath: facet].insert(value)
            }
        } else {
            self[keyPath: facet] = self[keyPath: facet] == [value] ? [] : [value]
        }
    }

    private init(sort: LibrarySortColumn, ascending: Bool) {
        self.sort = sort
        self.ascending = ascending
    }

    init() {}
}

/// The Library window's persisted choices (UserDefaults `AmpXLibraryModuleV1`); frame and size live in the
/// module layout store.
struct LibraryModulePreferences: Codable, Equatable, Sendable {
    static let storageKey = "AmpXLibraryModuleV1"

    var columns = LibraryColumnSet.default
    var sort: LibrarySortColumn = .artist
    var ascending = true
    var mixesFollowsSelection = false

    static func load(_ defaults: UserDefaults) -> LibraryModulePreferences {
        guard let data = defaults.data(forKey: self.storageKey),
              let preferences = try? JSONDecoder().decode(LibraryModulePreferences.self, from: data)
        else { return LibraryModulePreferences() }
        return preferences
    }

    func save(_ defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

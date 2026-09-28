import Foundation

enum LibraryFacetValue: Hashable, Codable, Sendable {
    case text(String)
    /// Nil genre / empty album; presented as "(No Genre)" / "(No Album)" by the UI only.
    case absent
}

enum LibrarySortColumn: String, Codable, Sendable {
    case artist, title, genre, duration, bpm, musicalKey, bitrate
}

struct LibraryFacetCounts: Sendable, Equatable {
    let genres: [LibraryFacetValue: Int]
    let artists: [LibraryFacetValue: Int]
    let albums: [LibraryFacetValue: Int]
}

struct LibraryResult: Sendable {
    let rows: [LibraryRow]
    let facets: LibraryFacetCounts
    let snapshotVersion: UInt64
    let generation: UInt64
    /// Unavailable rows in the whole snapshot, whatever the query filters (the browser's MISSING button).
    var unavailableTotal = 0
    /// Sum of `rows` durations, in seconds.
    var totalDuration: Double = 0
}

/// A browser request (spec: "Index and query semantics"). `Codable` so DJ-mode smart playlists can persist it.
struct LibraryQuery: Codable, Sendable, Equatable {
    var search = ""
    var genres: Set<LibraryFacetValue> = []
    var artists: Set<LibraryFacetValue> = []
    var albums: Set<LibraryFacetValue> = []
    var sort: LibrarySortColumn = .artist
    var ascending = true
    /// Inclusive BPM range (Library module spec). Rows without a BPM are excluded while it is set.
    var bpmRange: ClosedRange<Double>?
    /// The MISSING view: only rows that are not available.
    var onlyUnavailable = false

    static let foldOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    func evaluate(rows: [LibraryRow], snapshotVersion: UInt64, generation: UInt64) -> LibraryResult {
        self.evaluate(sortedRows: self.sorted(rows), snapshotVersion: snapshotVersion, generation: generation)
    }

    /// Rows in this query's display order. Filtering preserves order, so an index can sort once per snapshot.
    func sorted(_ rows: [LibraryRow]) -> [LibraryRow] {
        rows.sorted(by: self.precedes)
    }

    /// `rows` must already be in `sorted(_:)` order for this query's column and direction.
    func evaluate(sortedRows rows: [LibraryRow], snapshotVersion: UInt64, generation: UInt64) -> LibraryResult {
        let terms = self.search.folding(options: Self.foldOptions, locale: nil)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        // BPM range and the MISSING view act like facets: they filter rows and every facet's counts.
        let searched = rows.filter { row in
            if self.onlyUnavailable, row.isAvailable {
                return false
            }
            if let range = self.bpmRange {
                guard let bpm = row.bpm, range.contains(bpm) else { return false }
            }
            return terms.isEmpty || terms.allSatisfy { row.searchKey.contains($0) }
        }

        // Each facet counts rows matching the search and every *other* facet's selection.
        let facets = LibraryFacetCounts(
            genres: Self.counts(searched.filter { self.matches($0, skipping: \.genres) }, Self.genreKey),
            artists: Self.counts(searched.filter { self.matches($0, skipping: \.artists) }, Self.artistKey),
            albums: Self.counts(searched.filter { self.matches($0, skipping: \.albums) }, Self.albumKey)
        )
        let matched = searched.filter { self.matches($0, skipping: nil) }
        return LibraryResult(
            rows: matched,
            facets: facets,
            snapshotVersion: snapshotVersion,
            generation: generation,
            unavailableTotal: rows.reduce(0) { $0 + ($1.isAvailable ? 0 : 1) },
            totalDuration: matched.reduce(0) { $0 + $1.duration }
        )
    }

    // MARK: - Facets

    static func genreKey(_ row: LibraryRow) -> LibraryFacetValue {
        guard let genre = row.genre, !genre.isEmpty else { return .absent }
        return .text(genre)
    }

    static func artistKey(_ row: LibraryRow) -> LibraryFacetValue {
        row.artist.isEmpty ? .absent : .text(row.artist)
    }

    static func albumKey(_ row: LibraryRow) -> LibraryFacetValue {
        row.album.isEmpty ? .absent : .text(row.album)
    }

    /// OR within a facet, AND across facets; an empty selection does not filter.
    private func matches(_ row: LibraryRow, skipping skipped: KeyPath<LibraryQuery, Set<LibraryFacetValue>>?) -> Bool {
        let facets: [(KeyPath<LibraryQuery, Set<LibraryFacetValue>>, (LibraryRow) -> LibraryFacetValue)] = [
            (\.genres, Self.genreKey), (\.artists, Self.artistKey), (\.albums, Self.albumKey),
        ]
        return facets.allSatisfy { path, key in
            path == skipped || self[keyPath: path].isEmpty || self[keyPath: path].contains(key(row))
        }
    }

    private static func counts(_ rows: [LibraryRow], _ key: (LibraryRow) -> LibraryFacetValue) -> [LibraryFacetValue: Int] {
        rows.reduce(into: [:]) { $0[key($1), default: 0] += 1 }
    }

    // MARK: - Sort

    /// The chosen column (nil last in both directions), then artist, album, trackNumber (nil last), title, id.
    private func precedes(_ lhs: LibraryRow, _ rhs: LibraryRow) -> Bool {
        let primary: ComparisonResult = switch self.sort {
        case .artist: Self.compare(lhs.artist, rhs.artist)
        case .title: Self.compare(lhs.title, rhs.title)
        case .genre: Self.compareOptional(Self.sortableGenre(lhs), Self.sortableGenre(rhs), ascending: self.ascending)
        case .duration: Self.compare(lhs.duration, rhs.duration)
        case .bitrate: Self.compare(lhs.bitrate, rhs.bitrate)
        case .bpm: Self.compareOptional(lhs.bpm, rhs.bpm, ascending: self.ascending)
        case .musicalKey: Self.compareOptional(lhs.musicalKey, rhs.musicalKey, ascending: self.ascending)
        }
        if primary != .orderedSame {
            let isOptional = self.sort == .bpm || self.sort == .musicalKey || self.sort == .genre
            // Optional columns already folded the direction in, so nil stays last.
            return isOptional || self.ascending ? primary == .orderedAscending : primary == .orderedDescending
        }
        for result in [
            Self.compare(lhs.artist, rhs.artist),
            Self.compare(lhs.album, rhs.album),
            Self.compareOptional(lhs.trackNumber, rhs.trackNumber, ascending: true),
            Self.compare(lhs.title, rhs.title),
        ] where result != .orderedSame {
            return result == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// An empty genre tag sorts with the untagged rows, last.
    private static func sortableGenre(_ row: LibraryRow) -> String? {
        guard let genre = row.genre, !genre.isEmpty else { return nil }
        return genre
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive, .numeric])
    }

    private static func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame
    }

    /// Nil sorts last regardless of direction; present values follow `ascending`.
    private static func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?, ascending: Bool) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (lhs?, rhs?):
            let result = if let l = lhs as? String, let r = rhs as? String {
                self.compare(l, r)
            } else {
                self.compare(lhs, rhs)
            }
            guard !ascending else { return result }
            return result == .orderedAscending ? .orderedDescending : result == .orderedDescending ? .orderedAscending : .orderedSame
        }
    }
}

extension LibraryQuery {
    /// Every field is optional on decode, so queries saved by earlier versions keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        self.search = try container.decodeIfPresent(String.self, forKey: .search) ?? self.search
        self.genres = try container.decodeIfPresent(Set<LibraryFacetValue>.self, forKey: .genres) ?? self.genres
        self.artists = try container.decodeIfPresent(Set<LibraryFacetValue>.self, forKey: .artists) ?? self.artists
        self.albums = try container.decodeIfPresent(Set<LibraryFacetValue>.self, forKey: .albums) ?? self.albums
        self.sort = try container.decodeIfPresent(LibrarySortColumn.self, forKey: .sort) ?? self.sort
        self.ascending = try container.decodeIfPresent(Bool.self, forKey: .ascending) ?? self.ascending
        self.bpmRange = try container.decodeIfPresent(ClosedRange<Double>.self, forKey: .bpmRange)
        self.onlyUnavailable = try container.decodeIfPresent(Bool.self, forKey: .onlyUnavailable) ?? self.onlyUnavailable
    }
}

extension LibraryRow {
    /// Space-joined title, artist, album and album artist, folded once per snapshot.
    static func makeSearchKey(title: String, artist: String, album: String, albumArtist: String) -> String {
        [title, artist, album, albumArtist].joined(separator: " ").folding(options: LibraryQuery.foldOptions, locale: nil)
    }
}

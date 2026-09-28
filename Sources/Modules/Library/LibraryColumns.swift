import CoreGraphics

/// Track-table columns (Library Module spec § Layout). Display order is `allCases` order.
enum LibraryColumn: String, CaseIterable, Codable, Sendable {
    case number, artist, title, genre, time, bpm, key, camelot, kbps, format
    case label, remixer, composer, grouping, mix

    /// rekordbox text columns, hidden by default.
    static let textColumns: Set<LibraryColumn> = [.label, .remixer, .composer, .grouping, .mix]

    var title: String {
        switch self {
        case .number: "#"
        case .artist: "ARTIST"
        case .title: "TITLE"
        case .genre: "GENRE"
        case .time: "TIME"
        case .bpm: "BPM"
        case .key: "KEY"
        case .camelot: "CAMELOT"
        case .kbps: "KBPS"
        case .format: "FORMAT"
        case .label: "LABEL"
        case .remixer: "REMIXER"
        case .composer: "COMPOSER"
        case .grouping: "GROUPING"
        case .mix: "MIX"
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .number: 36
        case .artist: 90
        case .title: 120
        case .genre: 80
        case .time: 46
        case .bpm: 42
        case .key: 38
        case .camelot: 58
        case .kbps: 48
        case .format: 58
        case .label, .remixer, .composer, .grouping, .mix: 70
        }
    }

    /// Share of the width left over after minimums; only text columns grow.
    var weight: CGFloat {
        switch self {
        case .artist: 3
        case .title: 4
        case .genre: 2
        case .label, .remixer, .composer, .grouping, .mix: 1
        default: 0
        }
    }

    var isRightAligned: Bool {
        switch self {
        case .number, .time, .bpm, .kbps: true
        default: false
        }
    }

    var sortColumn: LibrarySortColumn? {
        switch self {
        case .number, .format: nil
        case .artist: .artist
        case .title: .title
        case .genre: .genre
        case .time: .duration
        case .bpm: .bpm
        case .key: .musicalKey
        case .camelot: .camelotKey
        case .label: .label
        case .remixer: .remixer
        case .composer: .composer
        case .grouping: .grouping
        case .mix: .mix
        case .kbps: .bitrate
        }
    }

    var isHideable: Bool {
        self != .title
    }

    static func column(for sort: LibrarySortColumn) -> LibraryColumn? {
        self.allCases.first { $0.sortColumn == sort }
    }
}

struct LibraryColumnSet: Codable, Equatable, Sendable {
    private(set) var visible: [LibraryColumn]

    static let `default` = LibraryColumnSet(
        visible: LibraryColumn.allCases.filter { $0 != .number && !LibraryColumn.textColumns.contains($0) }
    )

    /// Shows or hides `column`, keeping display order; TITLE is always visible.
    mutating func toggle(_ column: LibraryColumn) {
        guard column.isHideable else { return }
        var set = Set(self.visible)
        if set.contains(column) {
            set.remove(column)
        } else {
            set.insert(column)
        }
        self.visible = LibraryColumn.allCases.filter(set.contains)
    }

    /// Column x-extents (height 0) filling `width`: minimums first, spare width by weight. Below the sum of
    /// minimums every column shrinks in proportion and its text truncates.
    func frames(width: CGFloat) -> [(LibraryColumn, CGRect)] {
        let columns = self.visible
        let minimums = columns.reduce(0) { $0 + $1.minimumWidth }
        let widths: [CGFloat]
        if width <= minimums {
            let factor = minimums > 0 ? width / minimums : 0
            widths = columns.map { $0.minimumWidth * factor }
        } else {
            let totalWeight = columns.reduce(0) { $0 + $1.weight }
            let spare = width - minimums
            widths = columns.map { column in
                column.minimumWidth + (totalWeight > 0 ? spare * column.weight / totalWeight : 0)
            }
        }
        var x: CGFloat = 0
        return zip(columns, widths).map { column, columnWidth in
            defer { x += columnWidth }
            return (column, CGRect(x: x, y: 0, width: columnWidth, height: 0))
        }
    }
}

extension LibraryColumnSet {
    private enum CodingKeys: String, CodingKey {
        case visible, version
    }

    /// Version 2 added CAMELOT. A set saved before it (no `version`) gains CAMELOT in display order, once.
    private static let currentVersion = 2

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var visible = try container.decode([LibraryColumn].self, forKey: .visible)
        if try container.decodeIfPresent(Int.self, forKey: .version) == nil, !visible.contains(.camelot) {
            let set = Set(visible + [.camelot])
            visible = LibraryColumn.allCases.filter(set.contains)
        }
        self.init(visible: visible)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.visible, forKey: .visible)
        try container.encode(Self.currentVersion, forKey: .version)
    }
}

import CoreGraphics

/// Track-table columns (Library Module spec § Layout). Display order is `allCases` order.
enum LibraryColumn: String, CaseIterable, Codable, Sendable {
    case number, artist, title, genre, time, bpm, key, kbps, format

    var title: String {
        switch self {
        case .number: "#"
        case .artist: "ARTIST"
        case .title: "TITLE"
        case .genre: "GENRE"
        case .time: "TIME"
        case .bpm: "BPM"
        case .key: "KEY"
        case .kbps: "KBPS"
        case .format: "FORMAT"
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
        case .kbps: 48
        case .format: 58
        }
    }

    /// Share of the width left over after minimums; only text columns grow.
    var weight: CGFloat {
        switch self {
        case .artist: 3
        case .title: 4
        case .genre: 2
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

    static let `default` = LibraryColumnSet(visible: LibraryColumn.allCases.filter { $0 != .number })

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

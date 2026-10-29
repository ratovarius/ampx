import Foundation

/// Maps an absolute rekordbox path to a library row through its root plus `relativePath`, NFC-normalised and
/// case-folded on case-insensitive volumes (rekordbox sync spec § Matching, pass 1). Used by the XML import.
struct RekordboxPathMatcher: Sendable {
    private let roots: [RekordboxRootPath]
    private let byPath: [UUID: [String: UUID]]

    init(_ snapshot: RekordboxLibrarySnapshot) {
        let caseSensitivity = Dictionary(snapshot.roots.map { ($0.id, $0.caseSensitive) }, uniquingKeysWith: { first, _ in first })
        var byPath: [UUID: [String: UUID]] = [:]
        for row in snapshot.rows {
            byPath[row.rootID, default: [:]][Self.key(row.relativePath, caseSensitive: caseSensitivity[row.rootID] ?? true)] = row.id
        }
        self.roots = snapshot.roots
        self.byPath = byPath
    }

    func rowID(for path: String) -> UUID? {
        for root in self.roots {
            let prefix = Self.key(root.path, caseSensitive: root.caseSensitive) + "/"
            let candidate = Self.key(path, caseSensitive: root.caseSensitive)
            guard candidate.hasPrefix(prefix) else { continue }
            if let rowID = self.byPath[root.id]?[String(candidate.dropFirst(prefix.count))] {
                return rowID
            }
        }
        return nil
    }

    private static func key(_ path: String, caseSensitive: Bool) -> String {
        let normalized = path.precomposedStringWithCanonicalMapping
        return caseSensitive ? normalized : normalized.lowercased()
    }
}

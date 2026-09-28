import Foundation

struct ResolvedBookmark: Sendable {
    let url: URL
    let isStale: Bool
    let usesSecurityScope: Bool
}

/// Create/resolve/refresh primitive shared by `SecurityScopedBookmarkStore` (playlist) and library roots.
/// It holds no state and persists nothing; each caller owns its own persistence and access policy.
enum SecurityScopedBookmark {
    static func makeData(for url: URL, usesSecurityScope: Bool = true) throws -> Data {
        try url.bookmarkData(
            options: self.creationOptions(usesSecurityScope: usesSecurityScope),
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Security-scoped resolution first, then a plain bookmark; never shows UI.
    static func resolve(_ data: Data) -> ResolvedBookmark? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return ResolvedBookmark(url: url, isStale: isStale, usesSecurityScope: true)
        } catch {
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                return ResolvedBookmark(url: url, isStale: isStale, usesSecurityScope: false)
            } catch {
                return nil
            }
        }
    }

    static func refreshedData(for url: URL, usesSecurityScope: Bool) -> Data? {
        try? self.makeData(for: url, usesSecurityScope: usesSecurityScope)
    }

    private static func creationOptions(usesSecurityScope: Bool) -> URL.BookmarkCreationOptions {
        usesSecurityScope ? [.withSecurityScope] : []
    }
}

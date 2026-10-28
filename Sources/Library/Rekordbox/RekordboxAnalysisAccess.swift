import Foundation
import os

private let accessLogger = Logger(subsystem: "com.ampx.macos", category: "RekordboxPhrases")

enum RekordboxAccessError: Error, Equatable {
    /// The chosen folder has no `share/PIONEER/USBANLZ`.
    case notAnAnalysisFolder
}

/// The one-time grant to read rekordbox's analysis folder (DJ mode spec Revision 2 § rekordbox phrases). The app is
/// sandboxed, so the user chooses `~/Library/Pioneer/rekordbox` once; its bookmark lives in `UserDefaults`.
/// Failures are logged only, and read as no access.
final class RekordboxAnalysisAccess: @unchecked Sendable {
    static let bookmarkKey = "AmpX.rekordboxAnalysisBookmark"

    private let defaults: UserDefaults
    private let bookmarks: LibraryBookmarking

    init(defaults: UserDefaults, bookmarks: LibraryBookmarking = .securityScoped) {
        self.defaults = defaults
        self.bookmarks = bookmarks
    }

    var isGranted: Bool {
        self.defaults.data(forKey: Self.bookmarkKey) != nil
    }

    /// The real home's rekordbox folder: inside the sandbox, `NSHomeDirectory()` is the app's container.
    static var suggestedFolder: URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Library/Pioneer/rekordbox", isDirectory: true)
    }

    static func analysisFolder(in folder: URL) -> URL {
        folder.appendingPathComponent("share/PIONEER/USBANLZ", isDirectory: true)
    }

    func grant(_ folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: Self.analysisFolder(in: folder).path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw RekordboxAccessError.notAnAnalysisFolder }
        try self.defaults.set(self.bookmarks.make(folder), forKey: Self.bookmarkKey)
    }

    /// The granted folder, refreshing a stale bookmark; nil without a grant or when it no longer resolves.
    func resolve() -> URL? {
        guard let data = self.defaults.data(forKey: Self.bookmarkKey) else { return nil }
        guard let resolved = self.bookmarks.resolve(data) else {
            accessLogger.info("The rekordbox analysis bookmark no longer resolves")
            return nil
        }
        if resolved.isStale, let refreshed = self.bookmarks.refresh(resolved.url, resolved.usesSecurityScope) {
            self.defaults.set(refreshed, forKey: Self.bookmarkKey)
        }
        return resolved.url
    }
}

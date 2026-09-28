import Foundation
import SwiftData

/// Root operations (spec: "Roots and security scope"): save first, then publish, then rebind scope.
/// Watcher binding and scan requests are the engine's job.
extension LibraryStore {
    func roots() throws -> [LibraryRootSnapshot] {
        try self.modelContext.fetch(FetchDescriptor<LibraryRoot>(sortBy: [SortDescriptor(\.addedAt)]))
            .map(Self.snapshot)
    }

    /// Rejects nested or overlapping roots. Sets the start-up flag before inserting, so a crash can at worst
    /// open the container once needlessly, never hide a root.
    func addRoot(url: URL) throws -> UUID {
        let target = Self.canonical(url)
        try self.checkOverlap(target, excluding: nil)
        self.dependencies.startupFlag.setHasRoots(true)
        let bookmark = try self.dependencies.bookmarks.make(target)
        let id = UUID()
        try self.commit(nil) {
            self.modelContext.insert(LibraryRoot(id: id, bookmark: bookmark, displayPath: target.path, addedAt: self.dependencies.now()))
            return [.rootsChanged(rootID: id)]
        }
        _ = self.startScope(id, target)
        return id
    }

    /// Keeps `rootID` and every row's relative path, so files at the same relative paths match on the next scan.
    func relocateRoot(id: UUID, to url: URL) throws {
        let target = Self.canonical(url)
        try self.checkOverlap(target, excluding: id)
        guard try self.root(id) != nil else { throw LibraryStoreError.unknownRoot }
        self.revokeScan(rootID: id)
        self.revokeRekordboxSync(rootID: id)
        let bookmark = try self.dependencies.bookmarks.make(target)
        try self.commit(nil) {
            guard let root = try self.root(id) else { throw LibraryStoreError.unknownRoot }
            root.bookmark = bookmark
            root.displayPath = target.path
            return [.rootsChanged(rootID: id)]
        }
        self.stopScope(id)
        _ = self.startScope(id, target)
    }

    /// Deletes the root and its rows in one save; clears the start-up flag only after the last root's save.
    func removeRoot(id: UUID) throws {
        self.revokeScan(rootID: id)
        self.revokeRekordboxSync(rootID: id)
        try self.commit(nil) {
            guard let root = try self.root(id) else { throw LibraryStoreError.unknownRoot }
            for track in try self.tracks(id) {
                self.modelContext.delete(track)
            }
            self.modelContext.delete(root)
            guard let source = try self.rekordboxSource(id) else { return [.rootRemoved(rootID: id)] }
            self.modelContext.delete(source)
            return [.rootRemoved(rootID: id), .rekordboxSourcesChanged]
        }
        self.stopScope(id)
        _ = try self.clearStartupFlagIfEmpty()
    }

    /// Unmount or access lost: revoke the run, flag the root unavailable, keep rows (and `isMissing`) as they are.
    func markUnavailable(id: UUID) throws {
        self.revokeScan(rootID: id)
        try self.setAvailable(false, id: id, token: nil)
        self.stopScope(id)
    }

    /// Access lost during a run: like `markUnavailable(id:)`, but only for the run's live token. A revoked run
    /// (relocated, removed, cancelled) must not flag the root or release the scope a newer owner holds.
    func markUnavailable(token: LibraryScanToken) throws {
        guard self.activeTokens[token.rootID] == token else { throw LibraryStoreError.revokedToken }
        try self.markUnavailable(id: token.rootID)
    }

    /// Scan step 0: resolve (refreshing stale data), confirm the folder exists and access starts, and save
    /// availability. Failure saves `isAvailable = false` and throws `unavailableRoot`.
    func resolveRoot(token: LibraryScanToken) throws -> LibraryRootSnapshot {
        guard self.activeTokens[token.rootID] == token else { throw LibraryStoreError.revokedToken }
        guard let root = try self.root(token.rootID) else { throw LibraryStoreError.unknownRoot }

        let resolved = self.dependencies.bookmarks.resolve(root.bookmark)
        guard let resolved, Self.isDirectory(resolved.url), self.startScope(token.rootID, resolved.url) else {
            try self.setAvailable(false, id: token.rootID, token: token)
            self.stopScope(token.rootID)
            throw LibraryStoreError.unavailableRoot
        }

        let refreshed = resolved.isStale ? self.dependencies.bookmarks.refresh(resolved.url, resolved.usesSecurityScope) : nil
        let path = Self.canonical(resolved.url).path
        try self.commit(token) {
            var changed = false
            if !root.isAvailable {
                root.isAvailable = true
                changed = true
            }
            if root.displayPath != path {
                root.displayPath = path
                changed = true
            }
            if let refreshed {
                root.bookmark = refreshed
            }
            return changed ? [.rootsChanged(rootID: token.rootID)] : []
        }
        return Self.snapshot(root)
    }

    /// Start-up: take the scope of every root that resolves; flag the rest unavailable.
    func startAccessForAvailableRoots() throws -> [LibraryRootSnapshot] {
        var available: [LibraryRootSnapshot] = []
        for root in try self.modelContext.fetch(FetchDescriptor<LibraryRoot>(sortBy: [SortDescriptor(\.addedAt)])) {
            if let resolved = self.dependencies.bookmarks.resolve(root.bookmark),
               Self.isDirectory(resolved.url),
               self.startScope(root.id, resolved.url)
            {
                available.append(Self.snapshot(root))
            } else {
                try self.setAvailable(false, id: root.id, token: nil)
            }
        }
        return available
    }

    func stopAllAccess() {
        for id in Array(self.activeScopes.keys) {
            self.stopScope(id)
        }
    }

    /// Flag true but no roots (e.g. a crash after setting it): clear it. Returns whether it cleared.
    func clearStartupFlagIfEmpty() throws -> Bool {
        guard try self.modelContext.fetchCount(FetchDescriptor<LibraryRoot>()) == 0 else { return false }
        self.dependencies.startupFlag.setHasRoots(false)
        return true
    }

    // MARK: - Helpers

    private func setAvailable(_ available: Bool, id: UUID, token: LibraryScanToken?) throws {
        try self.commit(token) {
            guard let root = try self.root(id), root.isAvailable != available else { return [] }
            root.isAvailable = available
            return [.rootsChanged(rootID: id)]
        }
    }

    /// Starts access once per root; a root resolving to a new location releases the old scope first.
    private func startScope(_ id: UUID, _ url: URL) -> Bool {
        let target = Self.canonical(url)
        if self.activeScopes[id] == target {
            return true
        }
        self.stopScope(id)
        guard self.dependencies.scope.start(target) else { return false }
        self.activeScopes[id] = target
        return true
    }

    private func stopScope(_ id: UUID) {
        guard let url = self.activeScopes.removeValue(forKey: id) else { return }
        self.dependencies.scope.stop(url)
    }

    /// Equal, ancestor or descendant of another root (standardized, symlink-resolved, component-wise).
    private func checkOverlap(_ target: URL, excluding id: UUID?) throws {
        let components = target.pathComponents
        for root in try self.modelContext.fetch(FetchDescriptor<LibraryRoot>()) where root.id != id {
            let other = Self.canonical(URL(fileURLWithPath: root.displayPath, isDirectory: true)).pathComponents
            if components.starts(with: other) || other.starts(with: components) {
                throw LibraryStoreError.overlappingRoot
            }
        }
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func snapshot(_ root: LibraryRoot) -> LibraryRootSnapshot {
        LibraryRootSnapshot(
            id: root.id,
            url: URL(fileURLWithPath: root.displayPath, isDirectory: true),
            displayPath: root.displayPath,
            isAvailable: root.isAvailable,
            unreadableFolderCount: root.unreadableFolderCount,
            lastCompletedScanAt: root.lastCompletedScanAt
        )
    }
}

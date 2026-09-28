import Foundation
import os

/// File-system access for scanning (spec: "Architecture"). Tests substitute a fake to simulate hard links,
/// unreadable folders and colliding size/date pairs.
protocol LibraryFileSystem: Sendable {
    func volume(at root: URL) async throws -> LibraryVolume
    /// A stat-only walk: prefetched resource values, no file contents read.
    func walk(root: URL, volume: LibraryVolume) async throws -> LibraryWalk
    func stat(at url: URL) async throws -> LibraryStat
    func fingerprint(at url: URL) async throws -> Data
    func isReachable(_ root: URL) async -> Bool
    /// Regular files directly inside `root` whose extension equals `pathExtension`, ignoring case
    /// (rekordbox sync spec § Discovery).
    func topLevelFiles(in root: URL, pathExtension: String) async throws -> [LibraryTopLevelFile]
    func readPrefix(of url: URL, length: Int) async throws -> Data
    func readAll(of url: URL) async throws -> Data
}

/// A file at a root's top level, with the stamp that tells whether it changed.
struct LibraryTopLevelFile: Sendable, Equatable {
    let url: URL
    let name: String
    let stamp: RekordboxFileStamp
}

/// Test doubles that script only scans find nothing at the top level and read nothing.
extension LibraryFileSystem {
    func topLevelFiles(in _: URL, pathExtension _: String) async throws -> [LibraryTopLevelFile] {
        []
    }

    func readPrefix(of url: URL, length _: Int) async throws -> Data {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
    }

    func readAll(of url: URL) async throws -> Data {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
    }
}

struct FoundationLibraryFileSystem: LibraryFileSystem {
    static let prefetchKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .volumeIdentifierKey,
    ]
    static let reservedFolders: Set<String> = ["_extracted", "_library"]
    private static let cancellationCheckInterval = 256

    func volume(at root: URL) async throws -> LibraryVolume {
        let values = try root.resolvingSymlinksInPath()
            .resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey, .volumeTypeNameKey])
        return LibraryVolume(
            caseSensitive: values.volumeSupportsCaseSensitiveNames ?? false,
            typeName: values.volumeTypeName ?? "unknown"
        )
    }

    func walk(root: URL, volume: LibraryVolume) async throws -> LibraryWalk {
        let resolved = root.resolvingSymlinksInPath()
        guard self.isDirectory(resolved), FileManager.default.isReadableFile(atPath: resolved.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: root.path])
        }

        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                try Self.enumerate(resolved, volume: volume) { cancelled.withLock { $0 } || Task.isCancelled }
            }.value
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    func stat(at url: URL) async throws -> LibraryStat {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values.fileSize, let modified = values.contentModificationDate else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return LibraryStat(fileSize: Int64(size), contentModifiedAt: modified)
    }

    func fingerprint(at url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) { try LibraryFingerprint.read(from: url) }.value
    }

    func isReachable(_ root: URL) async -> Bool {
        let resolved = root.resolvingSymlinksInPath()
        return self.isDirectory(resolved) && FileManager.default.isReadableFile(atPath: resolved.path)
    }

    func topLevelFiles(in root: URL, pathExtension: String) async throws -> [LibraryTopLevelFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: root.resolvingSymlinksInPath(), includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )
        return contents.compactMap { url in
            guard url.pathExtension.caseInsensitiveCompare(pathExtension) == .orderedSame,
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let size = values.fileSize, let modified = values.contentModificationDate
            else { return nil }
            return LibraryTopLevelFile(
                url: url, name: url.lastPathComponent, stamp: RekordboxFileStamp(size: Int64(size), modifiedAt: modified)
            )
        }
    }

    func readPrefix(of url: URL, length: Int) async throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: length) ?? Data()
    }

    func readAll(of url: URL) async throws -> Data {
        // Copied, not mapped: rekordbox may rewrite the export in place while it is parsed.
        try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
    }

    // MARK: - Enumeration

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func enumerate(_ root: URL, volume: LibraryVolume, isCancelled: () -> Bool) throws -> LibraryWalk {
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        func relative(_ url: URL) -> String {
            url.path.hasPrefix(rootPrefix) ? String(url.path.dropFirst(rootPrefix.count)) : ""
        }

        let rootVolume = try root.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        var uncovered: Set<String> = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Self.prefetchKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, _ in
                // An unknown failure cannot prove absence: set the folder aside and keep walking.
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                uncovered.insert(relative(isDirectory ? url : url.deletingLastPathComponent()))
                return true
            }
        ) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: root.path])
        }

        var entries: [LibraryEntry] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited % Self.cancellationCheckInterval == 0, isCancelled() {
                return LibraryWalk(entries: [], coverage: .aborted, volume: volume)
            }
            guard let values = try? url.resourceValues(forKeys: Set(Self.prefetchKeys)) else {
                uncovered.insert(relative(url.deletingLastPathComponent()))
                continue
            }
            if values.isDirectory == true {
                let otherVolume = (values.volumeIdentifier as? NSObject).map { !$0.isEqual(rootVolume) } ?? false
                if Self.reservedFolders.contains(url.lastPathComponent) || otherVolume {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true,
                  M3UParser.isSupportedAudioExtension(url.pathExtension),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate
            else { continue }
            entries.append(LibraryEntry(
                relativePath: relative(url),
                stat: LibraryStat(fileSize: Int64(size), contentModifiedAt: modified)
            ))
        }

        if isCancelled() || !FileManager.default.fileExists(atPath: root.path) {
            // Cancelled late, or the root vanished mid-walk: never report an empty tree as complete.
            return LibraryWalk(entries: [], coverage: .aborted, volume: volume)
        }
        let coverage: LibraryCoverage = uncovered.isEmpty ? .complete : .partial(uncoveredFolders: uncovered)
        return LibraryWalk(entries: entries.sorted { $0.relativePath < $1.relativePath }, coverage: coverage, volume: volume)
    }
}

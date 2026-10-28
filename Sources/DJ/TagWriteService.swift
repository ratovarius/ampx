import AVFoundation
import Foundation
import os

private let writerLogger = Logger(subsystem: "com.ampx.macos", category: "TagWriter")

/// File access for tag writing, injectable for tests.
struct TagFileAccess: Sendable {
    var read: @Sendable (URL) throws -> [TagField: String]
    var write: @Sendable ([TagField: String], URL) throws -> Void
    /// Audio duration in seconds.
    var duration: @Sendable (URL) throws -> Double
    var isWritable: @Sendable (URL) -> Bool

    static let live = TagFileAccess(
        read: { try TagFileIO.read($0) },
        write: { try TagFileIO.write($0, to: $1) },
        duration: { url in
            let file = try AVAudioFile(forReading: url)
            return Double(file.length) / file.processingFormat.sampleRate
        },
        isWritable: { url in
            FileManager.default.isWritableFile(atPath: url.path)
                && FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
        }
    )
}

/// What turning tag writing on would do, shown before the first write.
struct TagWriteSummary: Equatable, Sendable {
    var filesToUpdate = 0
    var perField: [TagField: Int] = [:]
    var skippedReadOnly: [String] = []
    var unreadable = 0
    var halfDouble: [String] = []
}

/// The outcome of the last write run, kept for the rekordbox report.
struct TagWriteReport: Codable, Equatable, Sendable {
    var written = 0
    var skippedReadOnly: [String] = []
    var failed: [String] = []
    var halfDouble: [String] = []
}

/// What the Library window needs from tag writing (a seam for tests).
protocol TagWriting: AnyObject, Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
    func preview(rowIDs: Set<UUID>?) async -> TagWriteSummary
    func write(rowIDs: Set<UUID>?, onlyDue: Bool) async -> TagWriteReport
    func lastReport() -> TagWriteReport?
}

/// The tag-writing setting and the last report, in `UserDefaults` (DJ mode spec Revision 2 § Tag writing).
final class TagWriteSettings: @unchecked Sendable {
    static let enabledKey = "AmpX.keepRekordboxTagsInFiles"
    static let reportKey = "AmpX.lastTagWriteReport"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { self.defaults.bool(forKey: Self.enabledKey) }
        set { self.defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var lastReport: TagWriteReport? {
        get { self.defaults.data(forKey: Self.reportKey).flatMap { try? JSONDecoder().decode(TagWriteReport.self, from: $0) } }
        set { self.defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.reportKey) }
    }
}

/// Writes rekordbox data into files' standard tags (DJ mode spec Revision 2 § Tag writing). Each run is an exclusive
/// job in the scanner's FIFO. A file is written through a hidden temporary copy that is read back and checked before
/// it replaces the original, so a failure or a halt never leaves a damaged or half-written file behind.
actor TagWriteService: TagWriting {
    static let durationTolerance = 0.01

    private enum Outcome {
        case written, failed, halted
    }

    private let store: LibraryStore
    private let scanner: LibraryScanner
    private let files: TagFileAccess
    /// nil keeps the setting off and the report in memory (engines created by tests).
    private let settings: TagWriteSettings?
    private let halted = OSAllocatedUnfairLock(initialState: false)
    private let latest: OSAllocatedUnfairLock<TagWriteReport?>
    private let pending = OSAllocatedUnfairLock<[Task<Void, Never>]>(initialState: [])
    private var runReport = TagWriteReport()

    init(store: LibraryStore, scanner: LibraryScanner, files: TagFileAccess = .live, settings: TagWriteSettings?) {
        self.store = store
        self.scanner = scanner
        self.files = files
        self.settings = settings
        self.latest = OSAllocatedUnfairLock(initialState: settings?.lastReport)
    }

    nonisolated var isEnabled: Bool {
        self.settings?.isEnabled ?? false
    }

    /// No effect without settings (tag writing stays off).
    nonisolated func setEnabled(_ enabled: Bool) {
        self.settings?.isEnabled = enabled
    }

    nonisolated func lastReport() -> TagWriteReport? {
        self.latest.withLock { $0 }
    }

    /// Stops between files; a file being written is left untouched.
    nonisolated func halt() {
        self.halted.withLock { $0 = true }
    }

    private nonisolated var isHalted: Bool {
        self.halted.withLock { $0 }
    }

    /// After a rekordbox import, or when a root comes back: writes due rows if the setting is on. Returns at once.
    nonisolated func requestAutomaticWrite() {
        guard self.isEnabled, !self.isHalted else { return }
        let task = Task { _ = await self.write(rowIDs: nil, onlyDue: true) }
        self.pending.withLock { $0.append(task) }
    }

    /// Test and teardown hook: returns once no requested run is pending.
    func waitUntilIdle() async {
        while true {
            let tasks = self.pending.withLock { tasks in
                defer { tasks.removeAll() }
                return tasks
            }
            guard !tasks.isEmpty else { return }
            for task in tasks {
                await task.value
            }
        }
    }

    // MARK: - Runs

    /// Reads every candidate file now and counts what a write would change.
    func preview(rowIDs: Set<UUID>?) async -> TagWriteSummary {
        var summary = TagWriteSummary()
        for row in await (try? self.store.tagWriteRows(rowIDs: rowIDs)) ?? [] {
            guard let file = try? self.files.read(row.url) else {
                summary.unreadable += 1
                continue
            }
            let decision = TagWritePlanner.decide(row, file: file)
            if decision.halfDouble {
                summary.halfDouble.append(row.url.path)
            }
            guard !decision.changes.isEmpty else { continue }
            guard self.files.isWritable(row.url) else {
                summary.skippedReadOnly.append(row.url.path)
                continue
            }
            summary.filesToUpdate += 1
            for field in decision.changes.keys {
                summary.perField[field, default: 0] += 1
            }
        }
        return summary
    }

    /// Writes the rows (all rekordbox rows when nil); `onlyDue` skips rows whose values were already written.
    func write(rowIDs: Set<UUID>?, onlyDue: Bool) async -> TagWriteReport {
        guard !self.isHalted else { return TagWriteReport() }
        self.runReport = TagWriteReport()
        await self.scanner.performExclusive { await self.perform(rowIDs: rowIDs, onlyDue: onlyDue) }
        let report = self.runReport
        self.latest.withLock { $0 = report }
        self.settings?.lastReport = report
        return report
    }

    private func perform(rowIDs: Set<UUID>?, onlyDue: Bool) async {
        var report = TagWriteReport()
        var hashes: [UUID: Data] = [:]
        defer { self.runReport = report }
        let rows = await (try? self.store.tagWriteRows(rowIDs: rowIDs)) ?? []
        for row in rows {
            guard !self.isHalted, !Task.isCancelled else { break }
            if onlyDue, !TagWritePlanner.isDue(row) {
                continue
            }
            // Decided from the file as it is now, never from an earlier summary.
            guard let file = try? self.files.read(row.url) else {
                report.failed.append(row.url.path)
                continue
            }
            let decision = TagWritePlanner.decide(row, file: file)
            let hash = TagWritePlanner.hash(TagWritePlanner.desired(row))
            if decision.halfDouble {
                report.halfDouble.append(row.url.path)
            }
            if decision.changes.isEmpty {
                if !decision.halfDouble {
                    hashes[row.rowID] = hash
                }
                continue
            }
            guard self.files.isWritable(row.url) else {
                report.skippedReadOnly.append(row.url.path)
                continue
            }
            switch self.writeAtomically(decision.changes, to: row.url) {
            case .written:
                report.written += 1
                // Half/double rows stay due, so they are listed again until the values agree.
                if !decision.halfDouble {
                    hashes[row.rowID] = hash
                }
            case .failed:
                report.failed.append(row.url.path)
            case .halted:
                break
            }
        }
        do {
            try await self.store.markTagsWritten(hashes)
        } catch {
            writerLogger.error("Recording written tags failed: \(error.localizedDescription, privacy: .public)")
        }
        writerLogger.info("Tag write: \(report.written) written, \(report.failed.count) failed, \(report.skippedReadOnly.count) read-only")
    }

    /// Copy, write the copy, read it back and check it, then replace the original. The extension is kept so the
    /// copy is opened as the same container.
    private func writeAtomically(_ changes: [TagField: String], to url: URL) -> Outcome {
        let manager = FileManager.default
        let name = url.deletingPathExtension().lastPathComponent
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(name).ampx-tagwrite.\(url.pathExtension)")
        defer { try? manager.removeItem(at: temp) }
        do {
            try? manager.removeItem(at: temp)
            try manager.copyItem(at: url, to: temp)
            try self.files.write(changes, temp)
            let readBack = try self.files.read(temp)
            guard changes.allSatisfy({ Self.matches(readBack[$0.key], $0.value, field: $0.key) }) else {
                writerLogger.error("Read-back of \(url.path, privacy: .public) did not match; original kept")
                return .failed
            }
            guard try abs(self.files.duration(temp) - self.files.duration(url)) <= Self.durationTolerance else {
                writerLogger.error("Duration of \(url.path, privacy: .public) changed after writing; original kept")
                return .failed
            }
            guard !self.isHalted else { return .halted }
            _ = try manager.replaceItemAt(url, withItemAt: temp)
            return .written
        } catch {
            writerLogger.error("Writing tags to \(url.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private static func matches(_ found: String?, _ expected: String, field: TagField) -> Bool {
        guard let found = found?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        if field == .bpm, let number = Double(found), let wanted = Double(expected) {
            return Int(number.rounded()) == Int(wanted.rounded())
        }
        return found == expected
    }
}

// Music library L1 gate: does a rename or same-volume move preserve the size and modification date the
// directory enumerator reports? Runs unsandboxed on any writable folder (disk images, SMB shares).
// Usage: swift scripts/library-gate-rename.swift <writable-dir>
import Foundation

guard CommandLine.arguments.count == 2 else {
    print("Usage: swift library-gate-rename.swift <writable-dir>")
    exit(64)
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .volumeIdentifierKey]
let fileManager = FileManager.default

struct Observed: Encodable, Equatable {
    let size: Int
    let modified: Double
}

/// Reads values through the enumerator, as the library walk does, not through a fresh URL lookup.
func observe(_ name: String) throws -> Observed {
    guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys) else {
        throw CocoaError(.fileReadUnknown)
    }
    for case let url as URL in enumerator where url.path.hasSuffix("/" + name) {
        let values = try url.resourceValues(forKeys: Set(keys))
        guard let size = values.fileSize, let date = values.contentModificationDate else { break }
        return Observed(size: size, modified: date.timeIntervalSinceReferenceDate)
    }
    throw CocoaError(.fileNoSuchFile)
}

let original = root.appendingPathComponent("gate-a.bin")
let renamed = root.appendingPathComponent("gate-b.bin")
let subfolder = root.appendingPathComponent("gate-sub", isDirectory: true)
let moved = subfolder.appendingPathComponent("gate-b.bin")
defer {
    for url in [original, renamed, subfolder] {
        try? fileManager.removeItem(at: url)
    }
}

try Data((0 ..< 65536).map { UInt8(truncatingIfNeeded: $0 &* 7) }).write(to: original)
try fileManager.createDirectory(at: subfolder, withIntermediateDirectories: true)
// Let the modification date carry a sub-second component the way real files do.
try fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600.123_456)], ofItemAtPath: original.path)

let volume = try root.resourceValues(forKeys: [.volumeTypeNameKey, .volumeSupportsCaseSensitiveNamesKey])
let before = try observe("gate-a.bin")
try fileManager.moveItem(at: original, to: renamed)
let afterRename = try observe("gate-b.bin")
try fileManager.moveItem(at: renamed, to: moved)
let afterMove = try observe("gate-sub/gate-b.bin")

struct Report: Encodable {
    let volumeType: String
    let caseSensitive: Bool?
    let renamePreserved: Bool
    let movePreserved: Bool
    let before: Observed
    let afterRename: Observed
    let afterMove: Observed
}

let report = Report(
    volumeType: volume.volumeTypeName ?? "unknown",
    caseSensitive: volume.volumeSupportsCaseSensitiveNames,
    renamePreserved: afterRename == before,
    movePreserved: afterMove == before,
    before: before,
    afterRename: afterRename,
    afterMove: afterMove
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
try print(String(decoding: encoder.encode(report), as: UTF8.self))

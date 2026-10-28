import Foundation

/// The standard tag fields DJ mode writes (DJ mode spec Revision 2 § Tag writing).
enum TagField: String, CaseIterable, Codable, Sendable {
    case bpm, key, label, remixer, composer, grouping
}

/// Swift face of the TagLib bridge: reads and writes only `TagField`s, leaving every other tag untouched.
enum TagFileIO {
    static func read(_ url: URL) throws -> [TagField: String] {
        let fields = try AmpXTagFile.readFields(atPath: url.path)
        return Dictionary(uniqueKeysWithValues: fields.compactMap { key, value in TagField(rawValue: key).map { ($0, value) } })
    }

    static func write(_ fields: [TagField: String], to url: URL) throws {
        try AmpXTagFile.writeFields(Dictionary(uniqueKeysWithValues: fields.map { ($0.key.rawValue, $0.value) }), toPath: url.path)
    }
}

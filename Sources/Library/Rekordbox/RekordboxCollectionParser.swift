import Foundation

enum RekordboxParseError: Error, Equatable {
    case malformed(line: Int, message: String)
    case notACollection
}

/// Streams a rekordbox `collection.xml` (rekordbox sync spec § `RekordboxCollectionParser`). Only
/// `DJ_PLAYLISTS/PRODUCT` and `COLLECTION/TRACK` (with its `TEMPO` children) are read; `PLAYLISTS` is skipped.
enum RekordboxCollectionParser {
    static let sniffLength = 4096
    private static let locationPrefix = "file://localhost"

    /// Discovery's cheap check on a file's first bytes: a `DJ_PLAYLISTS` root and a rekordbox `PRODUCT`.
    static func isCollectionExport(prefix: Data) -> Bool {
        guard let text = self.decodePrefix(prefix), text.contains("<DJ_PLAYLISTS"),
              let product = text.range(of: "<PRODUCT")
        else { return false }
        let tagEnd = text[product.upperBound...].firstIndex(of: ">") ?? text.endIndex
        return text[product.upperBound ..< tagEnd].contains(#"Name="rekordbox""#)
    }

    static func parse(_ data: Data) throws -> RekordboxCollection {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "unknown XML error"
            throw RekordboxParseError.malformed(line: parser.lineNumber, message: message)
        }
        guard delegate.sawRoot else { throw RekordboxParseError.notACollection }
        return RekordboxCollection(
            productVersion: delegate.productVersion,
            tracks: delegate.tracks,
            droppedWithoutLocation: delegate.dropped
        )
    }

    /// `file://localhost/…` → decoded absolute path. Percent-decoding is literal, so `#` stays in the name.
    static func path(fromLocation location: String) -> String? {
        guard location.hasPrefix(self.locationPrefix) else { return nil }
        let encoded = String(location.dropFirst(self.locationPrefix.count))
        guard encoded.hasPrefix("/"), let decoded = encoded.removingPercentEncoding else { return nil }
        return URL(fileURLWithPath: decoded).standardizedFileURL.resolvingSymlinksInPath().path
            .precomposedStringWithCanonicalMapping
    }

    private static func decodePrefix(_ data: Data) -> String? {
        // A prefix may end inside a multi-byte sequence; drop up to three trailing bytes until it decodes.
        for trim in 0 ... min(3, data.count) {
            if let text = String(data: data.dropLast(trim), encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var sawRoot = false
        var productVersion: String?
        var tracks: [RekordboxTrack] = []
        var dropped = 0

        private var path: [String] = []
        private var current: [String: String]?
        private var beats: [RekordboxBeat] = []

        func parser(
            _: XMLParser,
            didStartElement name: String,
            namespaceURI _: String?,
            qualifiedName _: String?,
            attributes: [String: String] = [:]
        ) {
            let parent = self.path.last
            self.path.append(name)
            switch (parent, name) {
            case (nil, "DJ_PLAYLISTS"):
                self.sawRoot = true
            case ("DJ_PLAYLISTS", "PRODUCT"):
                self.productVersion = attributes["Version"]
            case ("COLLECTION", "TRACK"):
                self.current = attributes
                self.beats = []
            case ("TRACK", "TEMPO") where self.current != nil:
                if let start = Double(attributes["Inizio"] ?? ""), let bpm = Double(attributes["Bpm"] ?? "") {
                    self.beats.append(RekordboxBeat(
                        start: start, bpm: bpm, meter: attributes["Metro"] ?? "", beat: Int(attributes["Battito"] ?? "") ?? 0
                    ))
                }
            default:
                break
            }
        }

        func parser(_: XMLParser, didEndElement name: String, namespaceURI _: String?, qualifiedName _: String?) {
            self.path.removeLast()
            guard name == "TRACK", self.path.last == "COLLECTION", let attributes = self.current else { return }
            self.current = nil
            guard let path = attributes["Location"].flatMap(RekordboxCollectionParser.path(fromLocation:)) else {
                self.dropped += 1
                return
            }
            self.tracks.append(RekordboxTrack(
                path: path,
                size: attributes["Size"].flatMap { Int64($0) },
                duration: attributes["TotalTime"].flatMap { Double($0) },
                bpm: attributes["AverageBpm"].flatMap { Double($0) },
                tonality: Self.text(attributes["Tonality"]),
                rating: attributes["Rating"].flatMap { Int($0) }.map { min(5, max(0, Int((Double($0) / 51).rounded()))) },
                playCount: attributes["PlayCount"].flatMap { Int($0) },
                label: Self.text(attributes["Label"]),
                remixer: Self.text(attributes["Remixer"]),
                composer: Self.text(attributes["Composer"]),
                grouping: Self.text(attributes["Grouping"]),
                mix: Self.text(attributes["Mix"]),
                beatGrid: self.beats
            ))
        }

        private static func text(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value
        }
    }
}

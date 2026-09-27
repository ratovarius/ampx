import AVFoundation
import Foundation

struct Track: Identifiable, Equatable {
    let id = UUID()
    let url: URL?
    let title: String
    let artist: String
    let duration: TimeInterval
    let fileSize: Int64

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }

    init(title: String, artist: String, duration: TimeInterval = 0, fileSize: Int64 = 0, url: URL? = nil) {
        self.url = url
        self.title = title
        self.artist = artist
        self.duration = duration
        self.fileSize = fileSize
    }

    static func load(from url: URL) async -> Track {
        let metadata = await TrackMetadataLoader.load(from: url)
        return Track(
            title: metadata.title,
            artist: metadata.artist,
            duration: metadata.duration,
            fileSize: metadata.fileSize,
            url: url
        )
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedSize: String {
        let kb = Double(fileSize) / 1024.0
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        } else {
            let mb = kb / 1024.0
            return String(format: "%.1f MB", mb)
        }
    }
}

enum TrackMetadataLoader {
    /// `Track.load(from:)` consumes only title, artist, duration and fileSize; the rest serves the library
    /// (spec: "Metadata extraction"). Absent values follow the spec's table.
    struct Metadata: Sendable {
        var title: String
        var artist: String
        var duration: TimeInterval
        var fileSize: Int64
        var album = ""
        var albumArtist = ""
        var genre: String?
        var year: Int?
        var trackNumber: Int?
        var bitrate = 0
        var bitrateIsDerived = false
        var sampleRate = 0
        var channels = 0
        var codec = ""
        var bpm: Double?
        var musicalKey: String?
        var comment: String?
        /// AVFoundation could not load the duration or an audio track.
        var readFailed = false
    }

    /// Identifiers per field, as recorded by the L1 gate for ID3 (MP3/WAV/AIFF), Vorbis (FLAC) and iTunes (M4A).
    private enum Field {
        static let album = ["id3/TALB", "vorb/ALBUM", "itsk/%A9alb"]
        static let albumArtist = ["id3/TPE2", "vorb/ALBUMARTIST", "itsk/aART"]
        static let genre = ["id3/TCON", "vorb/GENRE", "itsk/%A9gen"]
        static let year = ["id3/TYER", "id3/TDRC", "vorb/DATE", "itsk/%A9day"]
        static let trackNumber = ["id3/TRCK", "vorb/TRACKNUMBER"]
        static let iTunesTrackNumber = "itsk/trkn"
        static let bpm = ["id3/TBPM", "vorb/BPM", "itsk/tmpo"]
        static let musicalKey = ["id3/TKEY", "vorb/INITIALKEY", "itlk/com.apple.iTunes.initialkey"]
        static let comment = ["id3/COMM", "vorb/COMMENT", "itsk/%A9cmt"]
    }

    static func load(from url: URL) async -> Metadata {
        let asset = AVURLAsset(url: url)
        var trackTitle = url.deletingPathExtension().lastPathComponent
        var trackArtist = "Unknown Artist"
        var hasID3Tags = false

        let commonMetadata = await (try? asset.load(.commonMetadata)) ?? []
        for item in commonMetadata {
            guard let key = item.commonKey?.rawValue else { continue }
            switch key {
            case "title":
                if let title = try? await item.load(.stringValue) {
                    trackTitle = title
                    hasID3Tags = true
                }
            case "artist":
                if let artist = try? await item.load(.stringValue) {
                    trackArtist = artist
                    hasID3Tags = true
                }
            default:
                break
            }
        }

        if !hasID3Tags {
            let parsed = TrackMetadataParser.parse(from: url)
            trackTitle = parsed.title
            trackArtist = parsed.artist
        }

        var readFailed = false
        let durationTime: CMTime?
        do {
            durationTime = try await asset.load(.duration)
        } catch {
            durationTime = nil
            readFailed = true
        }
        let rawDuration = durationTime.map { CMTimeGetSeconds($0) } ?? 0
        let duration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 0
        let fileSize = self.readFileSize(for: url)

        var metadata = Metadata(title: trackTitle, artist: trackArtist, duration: duration, fileSize: fileSize)
        metadata.codec = self.codec(for: url)

        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let descriptions = await (try? audioTrack.load(.formatDescriptions)) ?? []
            if let basic = descriptions.first.flatMap({ CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }) {
                metadata.sampleRate = Int(basic.mSampleRate)
                metadata.channels = Int(basic.mChannelsPerFrame)
            }
            let dataRate = await (try? audioTrack.load(.estimatedDataRate)) ?? 0
            if dataRate.isFinite, dataRate > 0 {
                metadata.bitrate = Int(dataRate.rounded())
            }
        } else {
            readFailed = true
        }
        if metadata.bitrate == 0 {
            let derived = duration > 0 ? Double(fileSize) * 8 / duration : 0
            if derived.isFinite, derived > 0, derived < Double(Int.max) {
                metadata.bitrate = Int(derived.rounded())
                metadata.bitrateIsDerived = true
            }
        }
        metadata.readFailed = readFailed

        let values = await self.taggedValues(of: asset, commonMetadata: commonMetadata)
        metadata.album = self.first(Field.album, in: values) ?? ""
        metadata.albumArtist = self.first(Field.albumArtist, in: values) ?? ""
        metadata.genre = self.first(Field.genre, in: values)
        metadata.year = self.first(Field.year, in: values).flatMap(self.year(from:))
        metadata.trackNumber = self.first(Field.trackNumber, in: values).flatMap(self.leadingInteger)
            ?? values.trackNumberData.flatMap(self.iTunesTrackNumber)
        metadata.bpm = self.first(Field.bpm, in: values).flatMap(self.bpm(from:))
        metadata.musicalKey = self.first(Field.musicalKey, in: values).flatMap(self.normalizedKey)
        metadata.comment = self.first(Field.comment, in: values)
        return metadata
    }

    // MARK: - Tag values

    private struct TaggedValues {
        var strings: [String: String] = [:]
        var trackNumberData: Data?
    }

    private static func taggedValues(of asset: AVURLAsset, commonMetadata: [AVMetadataItem]) async -> TaggedValues {
        var items = commonMetadata
        for format in await (try? asset.load(.availableMetadataFormats)) ?? [] {
            items += await (try? asset.loadMetadata(for: format)) ?? []
        }
        var values = TaggedValues()
        for item in items {
            guard let identifier = item.identifier?.rawValue, values.strings[identifier] == nil else { continue }
            if identifier == Field.iTunesTrackNumber {
                values.trackNumberData = try? await item.load(.dataValue)
                continue
            }
            var text = try? await item.load(.stringValue)
            if text == nil {
                text = try? await item.load(.numberValue)?.stringValue
            }
            if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                values.strings[identifier] = text
            }
        }
        return values
    }

    private static func first(_ identifiers: [String], in values: TaggedValues) -> String? {
        identifiers.lazy.compactMap { values.strings[$0] }.first
    }

    // MARK: - Parsing (internal for tests)

    static func codec(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ext == "aif" ? "aiff" : ext
    }

    /// `3/12` → 3, ` 07 ` → 7.
    static func leadingInteger(_ text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces).prefix { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// `2024`, `2016-05-01T00:00:00Z` → the leading four-digit year.
    static func year(from text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces).prefix(4)
        guard digits.count == 4, let year = Int(digits), year > 0 else { return nil }
        return year
    }

    static func bpm(from text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite, value > 0 else {
            return nil
        }
        return value
    }

    /// Key as tagged, normalised only for case and spacing: trimmed, spaces collapsed, first letter uppercased.
    static func normalizedKey(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let first = collapsed.first else { return nil }
        return first.uppercased() + collapsed.dropFirst()
    }

    /// iTunes `trkn` data: big-endian UInt16 track number at bytes 2–3.
    private static func iTunesTrackNumber(_ data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        let number = Int(bytes[2]) << 8 | Int(bytes[3])
        return number > 0 ? number : nil
    }

    private static func readFileSize(for url: URL) -> Int64 {
        let isNetwork = FileSystemHelpers.isNetworkVolume(url)

        if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = resourceValues.fileSize
        {
            return Int64(size)
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let size = attributes[.size] as? Int64 {
                return size
            }
            if let size = attributes[.size] as? NSNumber {
                return size.int64Value
            }
            if let size = attributes[.size] as? UInt64 {
                return Int64(size)
            }
        }

        if isNetwork,
           let fileHandle = try? FileHandle(forReadingFrom: url)
        {
            defer { try? fileHandle.close() }
            if let endOffset = try? fileHandle.seekToEnd() {
                return Int64(endOffset)
            }
        }

        return 0
    }
}

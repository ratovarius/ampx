@testable import AmpX
import AVFoundation
import XCTest

/// L1 gate (spec: "L1 gate — metadata, rename evidence and cost"). Records which spec fields AVFoundation
/// exposes per container and proves AIFF/M4A play. Results print as `LIBRARY-GATE` lines for the spec.
final class LibraryMetadataGateTests: XCTestCase {
    private static let taggedFixtures = [
        "tagged-v23.mp3", "tagged-v24.mp3", "tagged.flac", "tagged.wav", "tagged.aiff", "tagged.m4a",
    ]

    /// Spec field → value the fixture generator wrote (scripts/ampx_fixtures/library.py).
    private static let expectedValues: [(field: String, value: String)] = [
        ("album", "Library Album"),
        ("albumArtist", "Album Artist"),
        ("genre", "Techno"),
        ("year", "2024"),
        ("trackNumber", "3"),
        ("bpm", "130"),
        ("musicalKey", "Am"),
        ("comment", "Library fixture"),
    ]

    private var libraryRoot: URL {
        get throws {
            try XCTUnwrap(Bundle(for: Self.self).resourceURL).appendingPathComponent("Library")
        }
    }

    func testFixtureFolderIsBundled() throws {
        let manifest = try self.libraryRoot.appendingPathComponent("manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))
    }

    func testRecordMetadataMatrix() async throws {
        var matrix: [String: [String: String]] = [:]
        var raw: [String: [String: String]] = [:]

        for name in Self.taggedFixtures {
            let asset = try AVURLAsset(url: self.libraryRoot.appendingPathComponent(name))
            let items = try await Self.metadataItems(of: asset)
            raw[name] = items.reduce(into: [:]) { $0[$1.identifier] = $1.value }

            var row: [String: String] = [:]
            for (field, expected) in Self.expectedValues {
                let sources = items.filter { Self.value($0.value, matches: expected, field: field) }.map(\.identifier)
                row[field] = sources.isEmpty ? "absent" : Set(sources).sorted().joined(separator: " | ")
            }

            let duration = try await asset.load(.duration).seconds
            XCTAssertGreaterThan(duration, 0, name)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertEqual(tracks.count, 1, name)
            if let track = tracks.first {
                let descriptions = try await track.load(.formatDescriptions)
                let basic = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
                row["sampleRate"] = basic.map { "\(Int($0.mSampleRate))" } ?? "absent"
                row["channels"] = basic.map { "\($0.mChannelsPerFrame)" } ?? "absent"
                let rate = try await track.load(.estimatedDataRate)
                row["estimatedDataRate"] = rate > 0 ? "\(Int(rate))" : "absent"
            }
            matrix[name] = row
        }

        self.emitGate("metadata", matrix)
        self.emitGate("metadata-raw", raw)
    }

    @MainActor
    func testAIFFAndM4APlay() throws {
        let player = AudioPlayer(installRemoteCommands: false)
        for name in ["tagged.aiff", "tagged.m4a"] {
            let url = try self.libraryRoot.appendingPathComponent(name)
            let loaded = expectation(description: "load \(name)")
            let outcome = SendableBox(false)
            player.loadTrack(Track(title: name, artist: "Gate", url: url)) { success in
                outcome.value = success
                loaded.fulfill()
            }
            wait(for: [loaded], timeout: 5)
            XCTAssertTrue(outcome.value, "\(name) did not load")
            XCTAssertGreaterThan(player.duration, 0, name)

            player.play()
            player.stop()
            let flushed = expectation(description: "flush \(name)")
            player.testing_afterAudioQueueFlush { flushed.fulfill() }
            wait(for: [flushed], timeout: 2)
            self.emitGate("playback", [name: outcome.value ? "loaded, played, stopped" : "failed"])
        }
    }

    // MARK: - Helpers

    private struct Item {
        let identifier: String
        let value: String
    }

    private static func metadataItems(of asset: AVURLAsset) async throws -> [Item] {
        var metadata = try await asset.load(.commonMetadata)
        for format in try await asset.load(.availableMetadataFormats) {
            metadata += try await asset.loadMetadata(for: format)
        }
        var items: [Item] = []
        for item in metadata {
            let identifier = item.identifier?.rawValue ?? item.commonKey.map { "common/\($0.rawValue)" } ?? "unknown"
            await items.append(Item(identifier: identifier, value: self.describe(item)))
        }
        return items
    }

    private static func describe(_ item: AVMetadataItem) async -> String {
        if let string = try? await item.load(.stringValue) {
            return string
        }
        if let number = try? await item.load(.numberValue) {
            return number.stringValue
        }
        if let data = try? await item.load(.dataValue) {
            return "data:" + data.map { String($0) }.joined(separator: ",")
        }
        return "?"
    }

    private static func value(_ value: String, matches expected: String, field: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == expected {
            return true
        }
        switch field {
        case "trackNumber":
            // "3/12" in ID3/Vorbis; big-endian UInt16 at bytes 2–3 in iTunes `trkn` data.
            if trimmed.split(separator: "/").first.map(String.init) == expected {
                return true
            }
            if trimmed.hasPrefix("data:") {
                let bytes = trimmed.dropFirst(5).split(separator: ",").compactMap { Int($0) }
                return bytes.count >= 4 && String(bytes[2] << 8 | bytes[3]) == expected
            }
            return false
        case "year":
            return trimmed.hasPrefix(expected)
        case "bpm":
            return Double(trimmed) == Double(expected)
        default:
            return false
        }
    }
}

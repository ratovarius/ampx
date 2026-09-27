@testable import AmpX
import UniformTypeIdentifiers
import XCTest

/// Spec: the single audio extension set gains aif/aiff/m4a after the playback gate passed (Task 1), and the
/// Add Files panel derives its types from it so the panel and folder import cannot disagree.
final class LibraryExtensionsTests: XCTestCase {
    func testAIFFAndM4AAcceptedCaseInsensitively() {
        for ext in ["aif", "AIF", "aiff", "AIFF", "m4a", "M4A", "mp3", "FLAC", "wav"] {
            XCTAssertTrue(M3UParser.isSupportedAudioExtension(ext), ext)
        }
    }

    func testUnsupportedExtensionsRejected() {
        for ext in ["ogg", "opus", "m3u", "txt", ""] {
            XCTAssertFalse(M3UParser.isSupportedAudioExtension(ext), ext)
        }
    }

    @MainActor
    func testAddFilesPanelMatchesSupportedExtensionsPlusM3U() throws {
        let types = PlaylistManager.addFilesPanelContentTypes
        for ext in M3UParser.supportedExtensions.union(["m3u"]) {
            let type = try XCTUnwrap(UTType(filenameExtension: ext), ext)
            XCTAssertTrue(types.contains(type), ext)
        }
        XCTAssertTrue(types.contains { $0.conforms(to: .aiff) })
        XCTAssertTrue(types.contains { $0.conforms(to: .mpeg4Audio) })
    }
}

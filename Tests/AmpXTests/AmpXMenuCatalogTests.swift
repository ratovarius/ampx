@testable import AmpX
import XCTest

final class AmpXMenuCatalogTests: XCTestCase {
    func testFileItemsIncludeAddAndPlaylistIO() {
        XCTAssertEqual(
            AmpXMenuCatalog.FileItem.allCases.map(\.rawValue),
            [
                "Add Files…",
                "Add Folder…",
                "Load Playlist…",
                "Save Playlist…",
            ]
        )
    }

    func testPlaybackItemsIncludeTransportAndToggles() {
        XCTAssertEqual(
            AmpXMenuCatalog.PlaybackItem.allCases.map(\.rawValue),
            [
                "Play",
                "Pause",
                "Stop",
                "Previous Track",
                "Next Track",
                "Shuffle",
                "Repeat",
            ]
        )
    }

    func testViewPanelsMatchClassicChrome() {
        XCTAssertEqual(
            AmpXMenuCatalog.ViewPanel.allCases.map(\.rawValue),
            ["Equalizer", "Playlist", "Visualizer"]
        )
    }

    func testUIScaleLivesUnderViewNotTopLevelZoom() {
        XCTAssertEqual(AmpXMenuCatalog.uiScaleMenuTitle, "UI Scale")
        XCTAssertFalse(
            AmpXMenuCatalog.uiScaleMenuTitle.localizedCaseInsensitiveContains("Zoom"),
            "UI scale must not reuse the Window → Zoom name"
        )
    }

    func testFileShortcutsMatchClassicHotkeysWithoutCommand() {
        XCTAssertEqual(AmpXMenuCatalog.FileShortcut.addFilesKey, "l")
        XCTAssertFalse(AmpXMenuCatalog.FileShortcut.addFilesUsesCommand)
        XCTAssertFalse(AmpXMenuCatalog.FileShortcut.addFilesUsesShift)
        XCTAssertTrue(AmpXMenuCatalog.FileShortcut.addFolderUsesShift)
        XCTAssertFalse(AmpXMenuCatalog.FileShortcut.addFolderUsesCommand)
    }
}

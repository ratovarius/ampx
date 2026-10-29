@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § rekordbox phrases (access).
final class RekordboxAnalysisAccessTests: XCTestCase {
    private typealias T = LibraryTestSupport

    private func rekordboxFolder(withAnalysis: Bool = true) throws -> URL {
        let folder = try T.temporaryDirectory(self).appendingPathComponent("rekordbox", isDirectory: true)
        let target = withAnalysis ? RekordboxAnalysisAccess.analysisFolder(in: folder) : folder
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return folder
    }

    func testGrantAcceptsFolderWithAnalysisAndPersists() throws {
        let defaults = T.isolatedDefaults(self)
        let folder = try self.rekordboxFolder()
        let access = RekordboxAnalysisAccess(defaults: defaults, bookmarks: T.plainBookmarks)
        XCTAssertFalse(access.isGranted)
        XCTAssertNil(access.resolve())

        try access.grant(folder)

        let reopened = RekordboxAnalysisAccess(defaults: defaults, bookmarks: T.plainBookmarks)
        XCTAssertTrue(reopened.isGranted)
        XCTAssertEqual(reopened.resolve()?.standardizedFileURL.path, folder.standardizedFileURL.path)
    }

    func testGrantRejectsFolderWithoutAnalysis() throws {
        let access = RekordboxAnalysisAccess(defaults: T.isolatedDefaults(self), bookmarks: T.plainBookmarks)
        XCTAssertThrowsError(try access.grant(try self.rekordboxFolder(withAnalysis: false))) { error in
            XCTAssertEqual(error as? RekordboxAccessError, .notAnAnalysisFolder)
        }
        XCTAssertFalse(access.isGranted)
    }

    func testAnalysisFolderLayout() {
        XCTAssertEqual(
            RekordboxAnalysisAccess.analysisFolder(in: URL(fileURLWithPath: "/x/rekordbox")).path,
            "/x/rekordbox/share/PIONEER/USBANLZ"
        )
    }

    func testSuggestedFolderIsTheRealHome() {
        let path = RekordboxAnalysisAccess.suggestedFolder.path
        XCTAssertTrue(path.hasSuffix("/Library/Pioneer/rekordbox"), path)
        XCTAssertFalse(path.contains("/Library/Containers/"), "the sandbox home is not where rekordbox lives")
    }
}

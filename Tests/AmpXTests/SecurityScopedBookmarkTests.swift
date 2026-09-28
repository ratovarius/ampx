@testable import AmpX
import XCTest

/// Shared bookmark primitive extracted from `SecurityScopedBookmarkStore` (spec: "Bookmark primitive").
final class SecurityScopedBookmarkTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecurityScopedBookmarkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.directory)
    }

    func testMalformedDataResolvesNil() {
        XCTAssertNil(SecurityScopedBookmark.resolve(Data([0, 1, 2])))
    }

    func testPlainRoundTrip() throws {
        let folder = try self.makeFolder("Root")
        let data = try SecurityScopedBookmark.makeData(for: folder, usesSecurityScope: false)
        let resolved = try XCTUnwrap(SecurityScopedBookmark.resolve(data))
        XCTAssertEqual(resolved.url.standardizedFileURL.resolvingSymlinksInPath(), folder.resolvingSymlinksInPath())
        XCTAssertFalse(resolved.isStale)
    }

    func testSecurityScopedRoundTrip() throws {
        let folder = try self.makeFolder("Scoped")
        let data = try SecurityScopedBookmark.makeData(for: folder)
        let resolved = try XCTUnwrap(SecurityScopedBookmark.resolve(data))
        XCTAssertEqual(resolved.url.standardizedFileURL.resolvingSymlinksInPath(), folder.resolvingSymlinksInPath())
    }

    func testRefreshedDataResolvesAfterRename() throws {
        let folder = try self.makeFolder("Before")
        let data = try SecurityScopedBookmark.makeData(for: folder, usesSecurityScope: false)
        let renamed = self.directory.appendingPathComponent("After", isDirectory: true)
        try FileManager.default.moveItem(at: folder, to: renamed)

        let followed = try XCTUnwrap(SecurityScopedBookmark.resolve(data))
        XCTAssertEqual(followed.url.lastPathComponent, "After")

        let refreshed = try XCTUnwrap(SecurityScopedBookmark.refreshedData(for: followed.url, usesSecurityScope: false))
        let resolved = try XCTUnwrap(SecurityScopedBookmark.resolve(refreshed))
        XCTAssertEqual(resolved.url.resolvingSymlinksInPath(), renamed.resolvingSymlinksInPath())
        XCTAssertFalse(resolved.isStale)
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = self.directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

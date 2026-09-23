@testable import AmpX
import XCTest

final class EntheaBundleLoaderTests: XCTestCase {
    func testEntheaDirectoryIsBundledAsADirectory() {
        XCTAssertNotNil(
            EntheaBundleLoader.directoryURL(in: .main),
            "Resources/Enthea must be a folder reference in project.pbxproj, not loose files"
        )
    }

    func testIndexHTMLResolvesFromMainBundle() {
        XCTAssertNotNil(EntheaBundleLoader.indexHTMLURL(in: .main))
    }

    func testBridgeScriptResolvesFromMainBundle() {
        let bridge = EntheaBundleLoader.directoryURL(in: .main)?
            .appendingPathComponent("bridge.js")
        XCTAssertEqual(bridge.map { FileManager.default.fileExists(atPath: $0.path) }, true)
    }
}

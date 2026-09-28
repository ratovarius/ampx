@testable import AmpX
import XCTest

/// Allowlist recorded by the L1 gate (spec: "Rename-tracking allowlist", "L1 gate results").
final class LibraryRenameTrackingTests: XCTestCase {
    func testFileSystemsThatPassedTheGateAreEnabled() {
        for type in ["apfs", "hfs", "exfat"] {
            XCTAssertTrue(LibraryRenameTracking.isEnabled(volumeType: type), type)
        }
    }

    func testUnmeasuredAndUnknownFileSystemsAreDisabled() {
        for type in ["smbfs", "msdos", "nfs", "afpfs", "webdav", "unknown", ""] {
            XCTAssertFalse(LibraryRenameTracking.isEnabled(volumeType: type), type)
        }
    }

    func testAllowlistIsExactlyTheVerifiedSet() {
        XCTAssertEqual(LibraryRenameTracking.verifiedVolumeTypes, ["apfs", "hfs", "exfat"])
    }
}

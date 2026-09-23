@testable import AmpX
import AppKit
import XCTest

final class AmpXFontsTests: XCTestCase {
    func testResolveUsesMonospacedSystemFallbackWhenLookupReturnsNil() {
        let fallback = AmpXFonts.resolve(
            name: "RobotoMono-Regular",
            size: 12,
            weight: .regular,
            lookup: { _, _ in nil }
        )
        let expected = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        XCTAssertEqual(fallback.fontName, expected.fontName)
    }

    func testRegisterTwiceUsesRobotoMonoFamily() {
        AmpXFonts.register(bundle: .main)
        let first = AmpXFonts.font(size: 12, weight: .regular)
        XCTAssertEqual(first.familyName, "Roboto Mono")

        AmpXFonts.register(bundle: .main)
        let second = AmpXFonts.font(size: 14, weight: .medium)
        XCTAssertEqual(second.familyName, "Roboto Mono")
    }

    func testWeightFacesResolveToDistinctPostScriptNames() {
        AmpXFonts.register(bundle: .main)
        let regular = AmpXFonts.font(size: 12, weight: .regular)
        let medium = AmpXFonts.font(size: 12, weight: .medium)
        let semibold = AmpXFonts.font(size: 12, weight: .semibold)
        XCTAssertEqual(regular.fontName, "RobotoMono-Regular")
        XCTAssertEqual(medium.fontName, "RobotoMono-Medium")
        XCTAssertEqual(semibold.fontName, "RobotoMono-SemiBold")
    }
}

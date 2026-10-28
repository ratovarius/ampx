@testable import AmpX
import XCTest

final class CamelotKeyTests: XCTestCase {
    func testAllTwentyFourKeys() {
        let wheel: [(String, String)] = [
            ("Abm", "1A"), ("B", "1B"), ("Ebm", "2A"), ("F#", "2B"), ("Bbm", "3A"), ("Db", "3B"),
            ("Fm", "4A"), ("Ab", "4B"), ("Cm", "5A"), ("Eb", "5B"), ("Gm", "6A"), ("Bb", "6B"),
            ("Dm", "7A"), ("F", "7B"), ("Am", "8A"), ("C", "8B"), ("Em", "9A"), ("G", "9B"),
            ("Bm", "10A"), ("D", "10B"), ("F#m", "11A"), ("A", "11B"), ("Dbm", "12A"), ("E", "12B"),
        ]
        for (key, camelot) in wheel {
            XCTAssertEqual(CamelotKey.from(musicalKey: key), camelot, key)
        }
    }

    func testRekordboxSpellings() {
        XCTAssertEqual(CamelotKey.from(musicalKey: "F#m"), "11A")
        XCTAssertEqual(CamelotKey.from(musicalKey: "Dbm"), "12A")
        XCTAssertEqual(CamelotKey.from(musicalKey: "Abm"), "1A")
        XCTAssertEqual(CamelotKey.from(musicalKey: "Bbm"), "3A")
        XCTAssertEqual(CamelotKey.from(musicalKey: "Db"), "3B")
    }

    func testEnharmonicsAndSymbols() {
        XCTAssertEqual(CamelotKey.from(musicalKey: "G#m"), "1A")
        XCTAssertEqual(CamelotKey.from(musicalKey: "C♯m"), "12A")
        XCTAssertEqual(CamelotKey.from(musicalKey: "E♭"), "5B")
        XCTAssertEqual(CamelotKey.from(musicalKey: " Gb "), "2B")
    }

    func testUnknownSpellingIsNil() {
        for value in ["", "o", "12A", "H", "Amm"] {
            XCTAssertNil(CamelotKey.from(musicalKey: value), value)
        }
    }

    func testSortOrder() {
        XCTAssertLessThan(CamelotKey.sortOrder("1A"), CamelotKey.sortOrder("1B"))
        XCTAssertLessThan(CamelotKey.sortOrder("1B"), CamelotKey.sortOrder("2A"))
        XCTAssertLessThan(CamelotKey.sortOrder("2A"), CamelotKey.sortOrder("12B"))
        XCTAssertLessThan(CamelotKey.sortOrder("12B"), CamelotKey.sortOrder(nil))
        XCTAssertEqual(CamelotKey.sortOrder("zz"), Int.max)
    }
}

@testable import AmpX
import XCTest

/// GENRE / ARTIST lists (Library Module spec § Layout, Behaviour).
@MainActor
final class LibraryFacetListViewTests: XCTestCase {
    private func makeList(title: String = "GENRE") -> LibraryFacetListView {
        let list = LibraryFacetListView(skin: ClassicModernSkin(), title: title)
        list.frame = CGRect(x: 0, y: 0, width: 230, height: LibraryFacetListView.titleHeight + 22 * 5)
        return list
    }

    func testSortsByNameWithAbsentLast() {
        let list = self.makeList()
        list.counts = [.text("techno"): 201, .absent: 3, .text("Afro House"): 5, .text("Deep & Organic House"): 360]
        XCTAssertEqual(list.values.map(\.0), [.text("Afro House"), .text("Deep & Organic House"), .text("techno"), .absent])
        XCTAssertEqual(list.values.map(\.1), [5, 360, 201, 3])
    }

    func testClickAndCommandClickReport() {
        let list = self.makeList()
        list.counts = [.text("House"): 1, .text("Techno"): 2]
        var clicks: [(LibraryFacetValue, Bool)] = []
        list.onClick = { clicks.append(($0, $1)) }
        list.handleClick(atRowY: 22 + 3, command: false)
        list.handleClick(atRowY: 3, command: true)
        list.handleClick(atRowY: 22 * 4, command: false)
        XCTAssertEqual(clicks.map(\.0), [.text("Techno"), .text("House")])
        XCTAssertEqual(clicks.map(\.1), [false, true])
    }

    func testAbsentLabel() {
        XCTAssertEqual(self.makeList(title: "GENRE").label(for: .absent), "(No Genre)")
        XCTAssertEqual(self.makeList(title: "ARTIST").label(for: .absent), "(No Artist)")
        XCTAssertEqual(self.makeList().label(for: .text("Trance")), "Trance")
    }

    func testTitleShowsValueCount() {
        let list = self.makeList()
        list.counts = [.text("A"): 1, .text("B"): 1, .absent: 1]
        XCTAssertEqual(list.titleText, "GENRE 3")
    }

    func testScrollsLongLists() {
        let list = self.makeList()
        list.counts = Dictionary(uniqueKeysWithValues: (0 ..< 40).map { (LibraryFacetValue.text(String(format: "Artist %02d", $0)), 1) })
        list.scroll(to: 22 * 30)
        XCTAssertEqual(list.visibleRange, 30 ..< 35)
        var clicked: LibraryFacetValue?
        list.onClick = { value, _ in clicked = value }
        list.handleClick(atRowY: 3, command: false)
        XCTAssertEqual(clicked, .text("Artist 30"))
    }

    func testAccessibilityValueCount() throws {
        let list = self.makeList(title: "ARTIST")
        list.counts = [.text("Kora"): 17]
        list.selected = [.text("Kora")]
        let rows = try XCTUnwrap(list.accessibilityChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(rows.first?.accessibilityLabel(), "Kora, 17")
        XCTAssertEqual(rows.first?.isAccessibilitySelected(), true)
        XCTAssertEqual(list.accessibilityLabel(), "ARTIST")
    }
}

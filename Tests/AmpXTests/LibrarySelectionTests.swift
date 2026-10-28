@testable import AmpX
import XCTest

final class LibrarySelectionTests: XCTestCase {
    private let order = (1 ... 6).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }

    func testClickSelectsOne() {
        var selection = LibrarySelection()
        selection.click(self.order[2], order: self.order)
        XCTAssertEqual(selection.ids, [self.order[2]])
        XCTAssertEqual(selection.focused, self.order[2])
        XCTAssertEqual(selection.anchor, self.order[2])
    }

    func testShiftClickExtendsFromAnchor() {
        var selection = LibrarySelection()
        selection.click(self.order[1], order: self.order)
        selection.shiftClick(self.order[4], order: self.order)
        XCTAssertEqual(selection.ids, Set(self.order[1 ... 4]))
        selection.shiftClick(self.order[0], order: self.order)
        XCTAssertEqual(selection.ids, Set(self.order[0 ... 1]), "the anchor stays; the range follows the new end")
        XCTAssertEqual(selection.focused, self.order[0])
    }

    func testCommandClickToggles() {
        var selection = LibrarySelection()
        selection.click(self.order[0], order: self.order)
        selection.commandClick(self.order[3])
        XCTAssertEqual(selection.ids, [self.order[0], self.order[3]])
        selection.commandClick(self.order[0])
        XCTAssertEqual(selection.ids, [self.order[3]])
        XCTAssertEqual(selection.anchor, self.order[0])
    }

    func testArrowAndShiftArrow() {
        var selection = LibrarySelection()
        selection.moveFocus(by: 1, extend: false, order: self.order)
        XCTAssertEqual(selection.ids, [self.order[0]], "no focus yet: down focuses the first row")
        selection.moveFocus(by: 2, extend: false, order: self.order)
        XCTAssertEqual(selection.ids, [self.order[2]])
        selection.moveFocus(by: 1, extend: true, order: self.order)
        selection.moveFocus(by: 1, extend: true, order: self.order)
        XCTAssertEqual(selection.ids, Set(self.order[2 ... 4]))
        selection.moveFocus(by: 50, extend: false, order: self.order)
        XCTAssertEqual(selection.focused, self.order[5], "clamped to the last row")
        var fromEnd = LibrarySelection()
        fromEnd.moveFocus(by: -1, extend: false, order: self.order)
        XCTAssertEqual(fromEnd.focused, self.order[5])
    }

    func testHomeEnd() {
        var selection = LibrarySelection()
        selection.click(self.order[3], order: self.order)
        selection.moveFocusToEdge(end: true, extend: true, order: self.order)
        XCTAssertEqual(selection.ids, Set(self.order[3 ... 5]))
        selection.moveFocusToEdge(end: false, extend: false, order: self.order)
        XCTAssertEqual(selection.ids, [self.order[0]])
    }

    func testSelectAll() {
        var selection = LibrarySelection()
        selection.selectAll(order: self.order)
        XCTAssertEqual(selection.ids, Set(self.order))
    }

    func testRetainDropsVanished() {
        var selection = LibrarySelection()
        selection.click(self.order[1], order: self.order)
        selection.shiftClick(self.order[3], order: self.order)
        selection.retain(present: [self.order[0], self.order[2]])
        XCTAssertEqual(selection.ids, [self.order[2]])
        XCTAssertNil(selection.focused, "the focused row vanished")
        XCTAssertNil(selection.anchor)
    }

    func testEmptyOrderIsNoOp() {
        var selection = LibrarySelection()
        selection.moveFocus(by: 1, extend: false, order: [])
        selection.selectAll(order: [])
        XCTAssertTrue(selection.ids.isEmpty)
        XCTAssertNil(selection.focused)
    }
}

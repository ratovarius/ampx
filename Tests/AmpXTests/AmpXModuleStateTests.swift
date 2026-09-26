@testable import AmpX
import XCTest

final class AmpXModuleStateTests: XCTestCase {
    func testDefaultStateHasEntheaClosed() {
        let state = AmpXModuleState()
        XCTAssertEqual(state.closed, [.enthea])
        XCTAssertTrue(state.collapsed.isEmpty)
    }

    func testPlayerCannotBeClosed() {
        var state = AmpXModuleState()
        state.close(.player)
        XCTAssertFalse(state.closed.contains(.player))
    }

    func testCloseKeepsCollapsed() {
        var state = AmpXModuleState()
        state.setCollapsed(.equalizer, true)
        state.close(.equalizer)
        XCTAssertTrue(state.closed.contains(.equalizer))
        XCTAssertTrue(state.collapsed.contains(.equalizer))
    }

    func testReopenRemovesOnlyClosedMembership() {
        var state = AmpXModuleState()
        state.setCollapsed(.playlist, true)
        state.close(.playlist)
        state.reopen(.playlist)
        XCTAssertFalse(state.closed.contains(.playlist))
        XCTAssertTrue(state.collapsed.contains(.playlist))
    }

    func testCloseIsIdempotent() {
        var state = AmpXModuleState()
        state.close(.equalizer)
        let once = state
        state.close(.equalizer)
        XCTAssertEqual(state, once)
    }

    func testReopenIsIdempotentWhenNotClosed() {
        var state = AmpXModuleState()
        let before = state
        state.reopen(.playlist)
        XCTAssertEqual(state, before)
    }

    func testSetCollapsedIsIdempotent() {
        var state = AmpXModuleState()
        state.setCollapsed(.equalizer, true)
        state.setCollapsed(.equalizer, true)
        XCTAssertEqual(state.collapsed, [.equalizer])
        state.setCollapsed(.equalizer, false)
        XCTAssertTrue(state.collapsed.isEmpty)
    }
}

@testable import AmpX
import XCTest

final class AmpXModuleOrderTests: XCTestCase {
    func testDefaultStateHasEntheaClosed() {
        let state = AmpXModuleOrder()
        XCTAssertEqual(state.order, [.player, .equalizer, .playlist, .enthea])
        XCTAssertEqual(state.closed, [.enthea])
        XCTAssertTrue(state.collapsed.isEmpty)
        XCTAssertTrue(state.detached.isEmpty)
    }

    func testCloseReopenPreservesDetachedMembershipAndOrder() {
        var state = AmpXModuleOrder()
        state.detach(.playlist)
        state.close(.playlist)
        state.reopen(.playlist)
        XCTAssertEqual(state.order, [.player, .equalizer, .playlist, .enthea])
        XCTAssertTrue(state.detached.contains(.playlist))
    }

    func testPlayerCloseAndDetachAreRejectedWithoutMutation() {
        var state = AmpXModuleOrder()
        let before = state
        state.close(.player)
        state.detach(.player)
        XCTAssertFalse(state.closed.contains(.player))
        XCTAssertFalse(state.detached.contains(.player))
        XCTAssertEqual(state, before)
    }

    func testCloseRetainsOrderCollapsedAndDetached() {
        var state = AmpXModuleOrder()
        state.setCollapsed(.equalizer, true)
        state.detach(.playlist)
        state.close(.playlist)
        XCTAssertEqual(state.order, [.player, .equalizer, .playlist, .enthea])
        XCTAssertTrue(state.collapsed.contains(.equalizer))
        XCTAssertTrue(state.detached.contains(.playlist))
        XCTAssertTrue(state.closed.contains(.playlist))
    }

    func testReopenRemovesOnlyClosedMembership() {
        var state = AmpXModuleOrder()
        state.setCollapsed(.equalizer, true)
        state.detach(.equalizer)
        state.close(.equalizer)
        state.reopen(.equalizer)
        XCTAssertFalse(state.closed.contains(.equalizer))
        XCTAssertTrue(state.detached.contains(.equalizer))
        XCTAssertTrue(state.collapsed.contains(.equalizer))
        XCTAssertEqual(state.order, [.player, .equalizer, .playlist, .enthea])
    }

    func testMoveReordersUsingFinalIndexAfterRemoval() {
        var state = AmpXModuleOrder()
        state.move(.playlist, to: 0)
        XCTAssertEqual(state.order, [.playlist, .player, .equalizer, .enthea])
    }

    func testMoveClampsIndexToValidRangeAfterRemoval() {
        var state = AmpXModuleOrder()
        state.move(.equalizer, to: 100)
        XCTAssertEqual(state.order, [.player, .playlist, .enthea, .equalizer])

        state.move(.player, to: -5)
        XCTAssertEqual(state.order, [.player, .playlist, .enthea, .equalizer])
    }

    func testMoveIsStableWhenIndexUnchanged() {
        var state = AmpXModuleOrder()
        state.move(.equalizer, to: 1)
        XCTAssertEqual(state.order, [.player, .equalizer, .playlist, .enthea])
    }

    func testRedockRemovesDetachedAndClosedThenMoves() {
        var state = AmpXModuleOrder()
        state.detach(.equalizer)
        state.setCollapsed(.equalizer, true)
        state.close(.equalizer)
        state.redock(.equalizer, at: 2)
        XCTAssertFalse(state.detached.contains(.equalizer))
        XCTAssertFalse(state.closed.contains(.equalizer))
        XCTAssertTrue(state.collapsed.contains(.equalizer))
        XCTAssertEqual(state.order, [.player, .playlist, .equalizer, .enthea])
    }

    func testRedockClampsIndexBoundaries() {
        var state = AmpXModuleOrder()
        state.detach(.playlist)
        state.redock(.playlist, at: 100)
        XCTAssertEqual(state.order, [.player, .equalizer, .enthea, .playlist])
        XCTAssertFalse(state.detached.contains(.playlist))

        state.detach(.equalizer)
        state.redock(.equalizer, at: -3)
        XCTAssertEqual(state.order, [.equalizer, .player, .enthea, .playlist])
    }

    func testDetachIsIdempotent() {
        var state = AmpXModuleOrder()
        state.detach(.playlist)
        state.detach(.playlist)
        XCTAssertEqual(state.detached, [.playlist])
    }

    func testCloseIsIdempotent() {
        var state = AmpXModuleOrder()
        state.close(.playlist)
        state.close(.playlist)
        XCTAssertEqual(state.closed, [.enthea, .playlist])
    }

    func testReopenIsIdempotentWhenNotClosed() {
        var state = AmpXModuleOrder()
        state.reopen(.player)
        XCTAssertFalse(state.closed.contains(.player))
        XCTAssertEqual(state.closed, [.enthea])
    }

    func testSetCollapsedIsIdempotent() {
        var state = AmpXModuleOrder()
        state.setCollapsed(.equalizer, true)
        state.setCollapsed(.equalizer, true)
        XCTAssertEqual(state.collapsed, [.equalizer])

        state.setCollapsed(.equalizer, false)
        state.setCollapsed(.equalizer, false)
        XCTAssertTrue(state.collapsed.isEmpty)
    }
}

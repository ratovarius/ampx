@testable import AmpX
import XCTest

final class AmpXLayoutTests: XCTestCase {
    func testScaleClampsToReferenceBounds() {
        XCTAssertEqual(AmpXLayout.scale(width: 490), 1)
        XCTAssertEqual(AmpXLayout.scale(width: 416.5), 0.85)
        XCTAssertEqual(AmpXLayout.scale(width: 980), 1.35)
    }

    func testPlayerOnlyLayoutAtUnitScale() {
        var state = AmpXModuleOrder()
        state.close(.equalizer)
        state.close(.playlist)
        let layout = AmpXLayout.calculate(
            state: state,
            width: 490,
            playlistViewportHeight: 180,
            availableHeight: 1000
        )
        XCTAssertEqual(layout.scale, 1)
        XCTAssertEqual(layout.contentHeight, 223.5)
        XCTAssertEqual(layout.frames.count, 1)
        XCTAssertEqual(layout.frames[.player]?.minX, 0)
        XCTAssertEqual(layout.frames[.player]?.width, 490)
        XCTAssertEqual(layout.frames[.player]?.height, 223.5)
    }

    func testWideLayoutKeepsReferenceCompositionAtLeft() throws {
        var state = AmpXModuleOrder()
        state.close(.equalizer)
        state.close(.playlist)
        let wide = AmpXLayout.calculate(
            state: state,
            width: 800,
            playlistViewportHeight: 180,
            availableHeight: 1000
        )
        XCTAssertEqual(wide.scale, 1)
        XCTAssertEqual(try XCTUnwrap(wide.frames[.player]?.minX), 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(wide.frames[.player]?.width), 490, accuracy: 0.0001)
    }

    func testTableDrivenLayouts() {
        let cases: [(name: String, state: AmpXModuleOrder, expectedHeight: CGFloat, moduleCount: Int)] = [
            (
                "full default stack",
                AmpXModuleOrder(),
                223.5 + 225.5 + 305,
                3
            ),
            (
                "collapsed equalizer",
                {
                    var state = AmpXModuleOrder()
                    state.setCollapsed(.equalizer, true)
                    return state
                }(),
                223.5 + AmpXCompactMetrics.equalizerHeight + 305,
                3
            ),
            (
                "player only",
                {
                    var state = AmpXModuleOrder()
                    state.close(.equalizer)
                    state.close(.playlist)
                    return state
                }(),
                223.5,
                1
            ),
        ]

        for testCase in cases {
            let layout = AmpXLayout.calculate(
                state: testCase.state,
                width: 490,
                playlistViewportHeight: AmpXMetrics.defaultPlaylistViewportHeight,
                availableHeight: 10000
            )
            XCTAssertEqual(
                layout.contentHeight,
                testCase.expectedHeight,
                accuracy: 0.0001,
                "Unexpected content height for \(testCase.name)"
            )
            XCTAssertEqual(
                layout.frames.count,
                testCase.moduleCount,
                "Unexpected module count for \(testCase.name)"
            )
        }
    }

    func testIgnoresDetachedAndClosedModulesInStackLayout() {
        var state = AmpXModuleOrder()
        state.detach(.playlist)
        state.close(.equalizer)
        let layout = AmpXLayout.calculate(
            state: state,
            width: 490,
            playlistViewportHeight: 180,
            availableHeight: 1000
        )
        XCTAssertEqual(layout.frames.count, 1)
        XCTAssertNotNil(layout.frames[.player])
        XCTAssertNil(layout.frames[.playlist])
        XCTAssertNil(layout.frames[.equalizer])
    }

    func testShortScreenShrinksOnlyThePlaylistViewportByTheExcess() throws {
        var state = AmpXModuleOrder()
        state.reopen(.enthea)
        let tall = AmpXLayout.calculate(
            state: state,
            width: 661.5,
            playlistViewportHeight: 180,
            availableHeight: 10000
        )
        let available = tall.contentHeight - 50
        let fitted = AmpXLayout.calculate(
            state: state,
            width: 661.5,
            playlistViewportHeight: 180,
            availableHeight: available
        )

        XCTAssertEqual(fitted.scale, 1)
        XCTAssertEqual(fitted.contentHeight, available, accuracy: 0.001, "Stack exactly fills the available height")
        XCTAssertEqual(fitted.playlistViewportHeight, 130, accuracy: 0.001)
        for id: AmpXModuleID in [.player, .equalizer, .enthea] {
            XCTAssertEqual(
                try XCTUnwrap(fitted.frames[id]).height,
                try XCTUnwrap(tall.frames[id]).height,
                accuracy: 0.001,
                "\(id) must keep its height"
            )
        }

        let tooShort = AmpXLayout.calculate(
            state: state,
            width: 661.5,
            playlistViewportHeight: 180,
            availableHeight: 500
        )
        XCTAssertEqual(tooShort.playlistViewportHeight, AmpXMetrics.minimumPlaylistViewportHeight)
    }

    func testCollapsedPlaylistIsNotResizedToFit() {
        var state = AmpXModuleOrder()
        state.setCollapsed(.playlist, true)
        let result = AmpXLayout.calculate(
            state: state,
            width: 490,
            playlistViewportHeight: 180,
            availableHeight: 300
        )
        XCTAssertEqual(result.playlistViewportHeight, 180)
        XCTAssertEqual(result.frames[.playlist]?.height, AmpXCompactMetrics.playlistHeight)
    }

    func testCustomPlaylistViewportAdjustsPlaylistModuleHeight() {
        let state = AmpXModuleOrder()
        let layout = AmpXLayout.calculate(
            state: state,
            width: 490,
            playlistViewportHeight: 120,
            availableHeight: 10000
        )
        let expectedPlaylistHeight = AmpXMetrics.headerHeight
            + AmpXMetrics.playlistNonRowChrome
            + 120
        XCTAssertEqual(layout.frames[.playlist]?.height, expectedPlaylistHeight)
        XCTAssertEqual(layout.playlistViewportHeight, 120)
    }
}

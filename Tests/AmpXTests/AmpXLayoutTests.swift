@testable import AmpX
import XCTest

final class AmpXLayoutTests: XCTestCase {
    private let viewport: CGFloat = 180

    private func size(_ id: AmpXModuleID, state: AmpXModuleState = AmpXModuleState(), playlistWidth: CGFloat = 490) -> CGSize {
        AmpXLayout.moduleSize(id, state: state, playlistViewportHeight: self.viewport, playlistWidth: playlistWidth)
    }

    func testModuleSizeUsesFullHeights() {
        XCTAssertEqual(self.size(.player), CGSize(width: AmpXMetrics.compositionWidth, height: AmpXMetrics.playerHeight))
        XCTAssertEqual(self.size(.equalizer).height, AmpXMetrics.equalizerHeight)
        XCTAssertEqual(
            self.size(.playlist).height,
            AmpXMetrics.headerHeight + AmpXMetrics.playlistNonRowChrome + self.viewport
        )
        XCTAssertEqual(self.size(.enthea).height, AmpXMetrics.entheaHeight)
    }

    func testModuleSizeCollapsedUsesCompactHeights() {
        var state = AmpXModuleState()
        state.setCollapsed(.player, true)
        state.setCollapsed(.playlist, true)
        XCTAssertEqual(self.size(.player, state: state).height, AmpXCompactMetrics.playerHeight)
        XCTAssertEqual(self.size(.playlist, state: state).height, AmpXCompactMetrics.playlistHeight)
    }

    func testPlaylistWidthNeverBelowMinimum() {
        XCTAssertEqual(self.size(.playlist, playlistWidth: 10).width, AmpXMetrics.minimumPlaylistWidth)
        XCTAssertEqual(self.size(.playlist, playlistWidth: 700).width, 700)
        XCTAssertEqual(self.size(.equalizer, playlistWidth: 700).width, AmpXMetrics.compositionWidth)
    }

    func testDefaultFramesStackFlushWithEntheaRight() throws {
        let frames = AmpXLayout.defaultFrames(
            state: AmpXModuleState(),
            playlistViewportHeight: self.viewport,
            playlistWidth: AmpXMetrics.defaultPlaylistWidth,
            anchorTopLeft: CGPoint(x: 100, y: 1000)
        )
        let player = try XCTUnwrap(frames[.player])
        let equalizer = try XCTUnwrap(frames[.equalizer])
        let playlist = try XCTUnwrap(frames[.playlist])
        let enthea = try XCTUnwrap(frames[.enthea])

        XCTAssertEqual(player.minX, 100)
        XCTAssertEqual(player.maxY, 1000)
        XCTAssertEqual(equalizer.maxY, player.minY)
        XCTAssertEqual(equalizer.minX, player.minX)
        XCTAssertEqual(playlist.maxY, equalizer.minY)
        XCTAssertEqual(playlist.minX, player.minX)
        XCTAssertEqual(enthea.minX, player.maxX)
        XCTAssertEqual(enthea.maxY, player.maxY)
    }

    func testDefaultAnchorCentresBelowTop() {
        let anchor = AmpXLayout.defaultAnchor(visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055))
        XCTAssertEqual(anchor, CGPoint(x: 960 - AmpXMetrics.compositionWidth / 2, y: 1035))
    }

    func testAdjustedPlaylistViewportHeightNeverBelowMinimum() {
        XCTAssertEqual(AmpXLayout.adjustedPlaylistViewportHeight(preferred: 180, heightDelta: 40), 220)
        XCTAssertEqual(
            AmpXLayout.adjustedPlaylistViewportHeight(preferred: 180, heightDelta: -1000),
            AmpXMetrics.minimumPlaylistViewportHeight
        )
    }
}

@testable import AmpX
import XCTest

@MainActor
final class AmpXStackViewportTests: XCTestCase {
    func testShortScreenShrinksOnlyPlaylistDownToThreeRows() {
        var state = AmpXModuleOrder()
        state.reopen(.enthea)
        let result = AmpXLayout.calculate(
            state: state,
            width: 661.5,
            playlistViewportHeight: 180,
            availableHeight: 500
        )
        XCTAssertEqual(result.playlistViewportHeight, AmpXMetrics.minimumPlaylistViewportHeight)
        XCTAssertEqual(result.frames[.player]?.height ?? 0, AmpXMetrics.playerHeight, accuracy: 0.001)
        XCTAssertEqual(result.frames[.equalizer]?.height ?? 0, AmpXMetrics.equalizerHeight, accuracy: 0.001)
        XCTAssertEqual(result.frames[.enthea]?.height ?? 0, AmpXMetrics.entheaHeight, accuracy: 0.001)
    }

    func testRestoredScreenSpaceReturnsPreferredPlaylistViewport() {
        var state = AmpXModuleOrder()
        state.reopen(.enthea)

        let cramped = AmpXLayout.calculate(
            state: state,
            width: 661.5,
            playlistViewportHeight: 180,
            availableHeight: 500
        )
        XCTAssertEqual(cramped.playlistViewportHeight, AmpXMetrics.minimumPlaylistViewportHeight)

        let restored = AmpXLayout.calculate(
            state: state,
            width: 661.5,
            playlistViewportHeight: 180,
            availableHeight: 2000
        )
        XCTAssertEqual(restored.playlistViewportHeight, 180)
    }

    func testStackShowsWholeCompositionWithoutScrolling() {
        let viewport = self.makeViewport()
        let layout = AmpXLayout.calculate(
            state: AmpXModuleOrder(),
            width: 490,
            playlistViewportHeight: AmpXMetrics.defaultPlaylistViewportHeight,
            availableHeight: 10000
        )
        viewport.frame = CGRect(x: 0, y: 0, width: 490, height: layout.contentHeight)
        viewport.applyLayout(layout, state: AmpXModuleOrder())

        XCTAssertEqual(viewport.visibleContentRect, CGRect(x: 0, y: 0, width: 490, height: layout.contentHeight))
        XCTAssertEqual(viewport.stackView.frame.origin.y, 0)
        XCTAssertFalse(viewport.subviews.contains { $0 is AmpXScrollbar }, "The module stack has no scrollbar")
    }

    func testStackContentPointMatchesViewportPoint() throws {
        let viewport = self.makeViewport(inWindowAt: NSPoint(x: 100, y: 200))
        let viewportPoint = NSPoint(x: 50, y: 80)
        let windowPoint = viewport.convert(viewportPoint, to: nil)
        let screenPoint = try XCTUnwrap(viewport.window?.convertPoint(toScreen: windowPoint))
        let contentPoint = viewport.stackContentPoint(fromScreenPoint: screenPoint)

        XCTAssertEqual(contentPoint.x, viewportPoint.x, accuracy: 0.5)
        XCTAssertEqual(contentPoint.y, viewportPoint.y, accuracy: 0.5)
    }

    func testContainsUsesScreenConversionFromForeignWindow() throws {
        let stackWindow = NSWindow(
            contentRect: CGRect(x: 100, y: 200, width: 490, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let viewport = self.makeViewport()
        stackWindow.contentView = viewport
        viewport.frame = try XCTUnwrap(stackWindow.contentView?.bounds)

        let foreignWindow = NSWindow(
            contentRect: CGRect(x: 700, y: 500, width: 200, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let overStackScreenPoint = stackWindow.convertPoint(toScreen: NSPoint(x: 245, y: 200))
        let outsideStackScreenPoint = foreignWindow.convertPoint(toScreen: NSPoint(x: 10, y: 10))

        XCTAssertTrue(viewport.contains(screenPoint: overStackScreenPoint))
        XCTAssertFalse(viewport.contains(screenPoint: outsideStackScreenPoint))
    }

    private func makeViewport(inWindowAt origin: NSPoint = .zero) -> AmpXStackViewport {
        let viewport = AmpXStackViewport()
        viewport.frame = CGRect(x: 0, y: 0, width: 490, height: 400)

        if origin != .zero {
            let window = NSWindow(
                contentRect: CGRect(origin: origin, size: viewport.frame.size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = viewport
            viewport.frame = window.contentView!.bounds
        }

        return viewport
    }
}

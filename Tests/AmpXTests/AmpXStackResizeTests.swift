@testable import AmpX
import AppKit
import XCTest

/// Regressions for the borderless stack host's live resize and its ragged right edge.
@MainActor
final class AmpXStackResizeTests: XCTestCase {
    private func makeCoordinator() -> AmpXHostCoordinator {
        let suite = "AmpXStackResizeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: AmpXLayoutStore(defaults: defaults),
            screen: NSScreen.main!
        )
        addTeardownBlock { @MainActor in
            for id in coordinator.state.detached {
                coordinator.closeModule(id)
            }
            coordinator.closeStack()
        }
        coordinator.showStack()
        return coordinator
    }

    /// AppKit's native resize sets the frame and notifies the delegate; `setFrame` does both.
    private func liveResize(
        _ controller: AmpXStackWindowController,
        by delta: CGSize
    ) throws {
        let window = try XCTUnwrap(controller.window)
        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification))
        var dragged = window.frame
        dragged.size.width += delta.width
        dragged.size.height += delta.height
        // Dragging the bottom edge keeps the top edge fixed.
        dragged.origin.y -= delta.height
        window.setFrame(dragged, display: false)
        controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
    }

    // MARK: - No black filler beside the narrow modules

    /// A Playlist wider than the Player/Equalizer leaves the host's right column uncovered; the
    /// window must not paint an opaque rectangle there (it read as a black block above the Playlist).
    func testWideStackHostPaintsNothingBesideTheNarrowModules() throws {
        let coordinator = self.makeCoordinator()
        coordinator.setPlaylistWidth(700)
        let window = try XCTUnwrap(coordinator.stackWindow)

        XCTAssertEqual(window.frame.width, 700, "Precondition: the host is as wide as the Playlist")
        XCTAssertEqual(coordinator.moduleView(for: .player)?.frame.width, AmpXMetrics.compositionWidth)
        XCTAssertFalse(window.isOpaque, "An opaque host fills the gap beside the narrow modules")
        XCTAssertEqual(
            window.backgroundColor.alphaComponent,
            0,
            "The host background must be clear so only module views draw"
        )
    }

    // MARK: - Diagonal live resize

    /// A diagonal drag changes both axes in one event. Applying only the dominant one and snapping
    /// the other back made the window oscillate between layouts (the reported flicker).
    func testDiagonalLiveResizeAppliesBothAxes() throws {
        let coordinator = self.makeCoordinator()
        coordinator.setPlaylistWidth(600)
        let controller = try XCTUnwrap(coordinator.stackWindowController)
        let window = try XCTUnwrap(controller.window)
        let start = window.frame

        try self.liveResize(controller, by: CGSize(width: 60, height: 40))

        XCTAssertEqual(window.frame.width, start.width + 60, accuracy: 1, "Width must follow the drag")
        XCTAssertEqual(window.frame.height, start.height + 40, accuracy: 1, "Height must follow the drag")
        XCTAssertEqual(window.frame.maxY, start.maxY, accuracy: 1, "The top edge stays put")
    }

    /// Repeating the same diagonal step must keep growing steadily instead of jumping between sizes.
    func testRepeatedDiagonalStepsDoNotOscillate() throws {
        let coordinator = self.makeCoordinator()
        coordinator.setPlaylistWidth(600)
        let controller = try XCTUnwrap(coordinator.stackWindowController)
        let window = try XCTUnwrap(controller.window)
        let start = window.frame

        var heights: [CGFloat] = []
        for _ in 0 ..< 4 {
            try self.liveResize(controller, by: CGSize(width: 10, height: 10))
            heights.append(window.frame.height)
        }

        XCTAssertEqual(window.frame.width, start.width + 40, accuracy: 1)
        XCTAssertEqual(heights, heights.sorted(), "Height must grow monotonically, never flicker back")
        XCTAssertEqual(window.frame.height, start.height + 40, accuracy: 1)
    }
}

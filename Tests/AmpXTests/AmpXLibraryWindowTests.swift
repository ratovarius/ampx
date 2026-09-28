@testable import AmpX
import XCTest

/// Library module window (spec 2026-09-27-library-module-design.md § UI spec amendment 1–3).
@MainActor
final class AmpXLibraryWindowTests: XCTestCase {
    private final class TallScreen: NSScreen {
        override var frame: NSRect {
            NSRect(x: 0, y: 0, width: 2560, height: 1600)
        }

        override var visibleFrame: NSRect {
            NSRect(x: 0, y: 0, width: 2560, height: 1575)
        }

        override var backingScaleFactor: CGFloat {
            2
        }
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "AmpXLibraryWindowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        self.addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeCoordinator(store: AmpXLayoutStore? = nil, screen: NSScreen = AmpXTestScreen.standard) -> AmpXHostCoordinator {
        let store = store ?? AmpXLayoutStore(defaults: self.isolatedDefaults(), screen: screen)
        let coordinator = AmpXHostCoordinator(
            state: store.load().state, skin: ClassicModernSkin(), layoutStore: store, screen: screen, entheaEnabled: false
        )
        self.addTeardownBlock { @MainActor in coordinator.hideAllWindowsForTesting() }
        return coordinator
    }

    // MARK: - State and persistence

    func testLibraryClosedByDefault() {
        XCTAssertTrue(AmpXModuleState().closed.contains(.library))
        let coordinator = self.makeCoordinator()
        coordinator.showAll()
        XCTAssertNil(coordinator.window(for: .library))
    }

    func testLegacyLayoutWithoutLibraryKeepsItClosed() {
        let defaults = self.isolatedDefaults()
        // A V2 payload written before the Library existed: `closed` lists only ENTHEA.
        let legacy = #"{"version":2,"collapsed":[],"closed":["enthea"],"frames":{},"playlistViewportHeight":196,"playlistWidth":490}"#
        defaults.set(Data(legacy.utf8), forKey: AmpXLayoutStore.storageKey)
        let layout = AmpXLayoutStore(defaults: defaults, screen: AmpXTestScreen.standard).load()
        XCTAssertTrue(layout.state.closed.contains(.library))
        XCTAssertEqual(layout.librarySize, AmpXMetrics.defaultLibrarySize)
    }

    func testLibrarySizeRoundTripsAndClampsToMinimum() {
        let defaults = self.isolatedDefaults()
        let store = AmpXLayoutStore(defaults: defaults, screen: AmpXTestScreen.standard)
        var layout = store.load()
        layout.state.reopen(.library)
        layout.librarySize = CGSize(width: 1200, height: 640)
        store.save(layout)
        let loaded = store.load()
        XCTAssertFalse(loaded.state.closed.contains(.library))
        XCTAssertEqual(loaded.librarySize, CGSize(width: 1200, height: 640))

        layout.librarySize = CGSize(width: 300, height: 100)
        store.save(layout)
        XCTAssertEqual(store.load().librarySize, AmpXMetrics.minimumLibrarySize)
    }

    // MARK: - Default frame

    func testDefaultLibraryFrameBelowStack() throws {
        let screen = TallScreen()
        let layout = AmpXLayoutStore.defaultLayout(for: screen)
        let library = try XCTUnwrap(layout.frames[.library])
        let playlist = try XCTUnwrap(layout.frames[.playlist])
        XCTAssertEqual(library.size, AmpXMetrics.defaultLibrarySize)
        XCTAssertEqual(library.maxY, playlist.minY, "flush below the stack")
        XCTAssertEqual(library.minX, playlist.minX)
    }

    func testLibraryFrameClampedToVisibleScreen() throws {
        // The standard test screen has no room below the stack: the frame must still lie on-screen.
        let visible = AmpXTestScreen.standard.visibleFrame
        let library = try XCTUnwrap(AmpXLayoutStore.defaultLayout(for: AmpXTestScreen.standard).frames[.library])
        XCTAssertTrue(visible.contains(library), "\(library) not inside \(visible)")

        // A saved frame on a display that is gone comes back on-screen at no less than the minimum size.
        let defaults = self.isolatedDefaults()
        let store = AmpXLayoutStore(defaults: defaults, screen: AmpXTestScreen.standard)
        var layout = store.load()
        layout.state.reopen(.library)
        layout.frames[.library] = CGRect(x: 5000, y: 3000, width: 1000, height: 500)
        store.save(layout)
        let restored = try XCTUnwrap(store.load().frames[.library])
        XCTAssertTrue(visible.contains(restored), "\(restored)")
        XCTAssertGreaterThanOrEqual(restored.width, AmpXMetrics.minimumLibrarySize.width)
    }

    /// A size saved on a larger display is bounded to this one, never below the minimum.
    func testOversizedSavedLibraryIsBoundedToScreen() throws {
        let visible = AmpXTestScreen.standard.visibleFrame
        let store = AmpXLayoutStore(defaults: self.isolatedDefaults(), screen: AmpXTestScreen.standard)
        var layout = store.load()
        layout.state.reopen(.library)
        layout.librarySize = CGSize(width: 5000, height: 3000)
        layout.frames[.library] = CGRect(x: visible.minX, y: visible.minY, width: 5000, height: 3000)
        store.save(layout)

        let restored = store.load().librarySize
        XCTAssertLessThanOrEqual(restored.width, visible.width)
        XCTAssertLessThanOrEqual(restored.height, visible.height)

        let coordinator = self.makeCoordinator(store: store)
        coordinator.showAll()
        let window = try XCTUnwrap(coordinator.window(for: .library))
        XCTAssertTrue(visible.insetBy(dx: -1, dy: -1).contains(window.frame), "\(window.frame) not inside \(visible)")
    }

    // MARK: - Window

    func testReopenLibraryShowsAtSavedFrame() throws {
        let coordinator = self.makeCoordinator()
        coordinator.showAll()
        coordinator.reopenModule(.library)
        let window = try XCTUnwrap(coordinator.window(for: .library))
        XCTAssertTrue(window.isVisible)
        let first = window.frame
        coordinator.closeModule(.library)
        XCTAssertFalse(window.isVisible)
        coordinator.reopenModule(.library)
        XCTAssertEqual(coordinator.window(for: .library)?.frame, first)
    }

    func testCollapsedLibraryIsHeaderOnly() throws {
        let coordinator = self.makeCoordinator()
        coordinator.showAll()
        coordinator.reopenModule(.library)
        let expanded = try XCTUnwrap(coordinator.window(for: .library)?.frame)
        coordinator.setCollapsed(.library, true)
        let collapsed = try XCTUnwrap(coordinator.window(for: .library)?.frame)
        XCTAssertEqual(collapsed.height, AmpXMetrics.headerHeight.rounded())
        XCTAssertEqual(collapsed.width, expanded.width)
        XCTAssertEqual(collapsed.maxY, expanded.maxY, "windowshade keeps the top edge")
    }

    func testLibraryHeaderHasNoMinimize() {
        let header = AmpXModuleHeaderView(moduleID: .library, skin: ClassicModernSkin())
        XCTAssertEqual(header.headerButtonLayout().map(\.button), [.collapse, .close])
        XCTAssertTrue(AmpXModuleView.stretchesHorizontally(.library))
    }

    func testLibraryWindowResizeConstraints() throws {
        let coordinator = self.makeCoordinator()
        coordinator.showAll()
        coordinator.reopenModule(.library)
        let window = try XCTUnwrap(coordinator.window(for: .library))
        XCTAssertEqual(window.contentMinSize, AmpXMetrics.minimumLibrarySize)
        XCTAssertEqual(window.contentMaxSize.width, .greatestFiniteMagnitude)
        coordinator.setCollapsed(.library, true)
        XCTAssertEqual(window.contentMaxSize.height, window.contentMinSize.height, "a collapsed Library does not resize vertically")
    }

    func testLibrarySnapsAndMovesWithPlayerWhenAttached() {
        let screen = TallScreen()
        let frames = AmpXLayoutStore.defaultLayout(for: screen).frames
        let open = frames.filter { [.player, .equalizer, .playlist, .library].contains($0.key) }
        XCTAssertTrue(AmpXSnapGeometry.connected(from: .player, frames: open).contains(.library))
    }
}

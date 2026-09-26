@testable import AmpX
import XCTest

/// Tests for the geometry-primary docking core: the pure 2D parent derivation (`AmpXDockGraph`)
/// and the offset persistence (`AmpXPanelPositionStore`). These replace the former
/// `AmpXPanelStackTests` (the 1-D ordered model the geometry-primary design superseded).
final class AmpXDockGraphTests: XCTestCase {
    private let main = CGRect(x: 100, y: 500, width: 275, height: 116)

    private func below(_ anchor: CGRect, height: CGFloat = 84) -> CGRect {
        CGRect(x: anchor.minX, y: anchor.minY - height, width: anchor.width, height: height)
    }

    private func rightOf(_ anchor: CGRect, width: CGFloat = 275, height: CGFloat = 232) -> CGRect {
        CGRect(x: anchor.maxX, y: anchor.maxY - height, width: width, height: height)
    }

    // MARK: - Reflow (Webamp withWindowGraphIntegrity)

    func testReflowShadingMainPullsStackUp() {
        let eq = self.below(self.main)
        let playlist = self.below(eq, height: 232)
        let shadedHeight: CGFloat = 14
        let result = AmpXDockGraph.reflow(
            before: [AmpXDockNode.main: self.main, .panel(.equalizer): eq, .panel(.playlist): playlist],
            sizes: [.main: CGSize(width: 275, height: shadedHeight), .panel(.equalizer): eq.size, .panel(.playlist): playlist.size]
        )
        let delta = self.main.height - shadedHeight
        XCTAssertEqual(result[.main]?.maxY, self.main.maxY)
        XCTAssertEqual(result[.panel(.equalizer)]?.maxY, result[.main]?.minY)
        XCTAssertEqual(result[.panel(.equalizer)]?.minY, eq.minY + delta)
        XCTAssertEqual(result[.panel(.playlist)]?.maxY, result[.panel(.equalizer)]?.minY)
    }

    func testReflowGrowingPlaylistLeavesSideWindowAndMovesWindowBelow() {
        let playlist = self.below(self.main, height: 232)
        let side = self.rightOf(playlist)
        let under = self.below(playlist)
        let result = AmpXDockGraph.reflow(
            before: [AmpXDockNode.main: self.main, .panel(.playlist): playlist, .panel(.visualizer): side, .panel(.equalizer): under],
            sizes: [.main: self.main.size, .panel(.playlist): CGSize(width: 275, height: 300), .panel(.visualizer): side.size, .panel(.equalizer): under.size]
        )
        XCTAssertEqual(result[.panel(.visualizer)], side)
        XCTAssertEqual(result[.panel(.equalizer)]?.maxY, result[.panel(.playlist)]?.minY)
        XCTAssertEqual(result[.panel(.playlist)]?.maxY, playlist.maxY)
    }

    func testReflowWideningMovesRightNeighbor() {
        let side = self.rightOf(self.main)
        let result = AmpXDockGraph.reflow(
            before: [AmpXDockNode.main: self.main, .panel(.visualizer): side],
            sizes: [.main: CGSize(width: 550, height: self.main.height), .panel(.visualizer): side.size]
        )
        XCTAssertEqual(result[.panel(.visualizer)]?.minX, self.main.minX + 550)
        XCTAssertEqual(result[.panel(.visualizer)]?.maxY, side.maxY)
    }

    func testReflowLeavesDetachedWindowAlone() {
        let floating = CGRect(x: 900, y: 100, width: 275, height: 116)
        let result = AmpXDockGraph.reflow(
            before: [AmpXDockNode.main: self.main, .panel(.equalizer): floating],
            sizes: [.main: CGSize(width: 275, height: 14), .panel(.equalizer): floating.size]
        )
        XCTAssertEqual(result[.panel(.equalizer)], floating)
    }

    // MARK: - Vertical

    func testVerticalChainBelowMain() {
        let eq = self.below(self.main)
        let playlist = self.below(eq, height: 232)
        let parents = AmpXDockGraph.parents(
            frames: [.main: self.main, .panel(.equalizer): eq, .panel(.playlist): playlist],
            order: [.equalizer, .playlist]
        )
        XCTAssertEqual(parents[.equalizer], .main)
        XCTAssertEqual(parents[.playlist], .panel(.equalizer))
        XCTAssertTrue(AmpXDockGraph.floating(order: [.equalizer, .playlist], parents: parents).isEmpty)
    }

    func testReorderedVerticalChain() {
        // Playlist directly below main, EQ below the playlist.
        let playlist = self.below(self.main, height: 232)
        let eq = self.below(playlist)
        let parents = AmpXDockGraph.parents(
            frames: [.main: self.main, .panel(.equalizer): eq, .panel(.playlist): playlist],
            order: [.equalizer, .playlist]
        )
        XCTAssertEqual(parents[.playlist], .main)
        XCTAssertEqual(parents[.equalizer], .panel(.playlist))
    }

    // MARK: - Horizontal (W: left/right docking)

    func testHorizontalDockToRightOfMain() {
        let playlist = self.rightOf(self.main)
        let parents = AmpXDockGraph.parents(
            frames: [.main: self.main, .panel(.playlist): playlist],
            order: [.equalizer, .playlist]
        )
        XCTAssertEqual(parents[.playlist], .main, "a panel snapped to the main window's right edge docks to it")
    }

    func testVisualizerDocksRightOfMainWithEQPlaylistColumn() {
        let eq = self.below(self.main)
        let playlist = self.below(eq, height: 232)
        let viz = self.rightOf(self.main, width: 600, height: 450)
        let parents = AmpXDockGraph.parents(
            frames: [
                .main: self.main,
                .panel(.equalizer): eq,
                .panel(.playlist): playlist,
                .panel(.visualizer): viz,
            ],
            order: [.equalizer, .playlist, .visualizer]
        )
        XCTAssertEqual(parents[.equalizer], .main)
        XCTAssertEqual(parents[.playlist], .panel(.equalizer))
        XCTAssertEqual(parents[.visualizer], .main)
    }

    func testHorizontalRowChainsLeftToRight() {
        // A horizontal row: main — EQ — playlist, each touching the previous window's right edge.
        // The playlist is far enough right that it only abuts the EQ, not the main window.
        let eq = CGRect(x: self.main.maxX, y: self.main.minY, width: 275, height: self.main.height)
        let playlist = CGRect(x: eq.maxX, y: self.main.minY, width: 275, height: self.main.height)
        let parents = AmpXDockGraph.parents(
            frames: [.main: self.main, .panel(.equalizer): eq, .panel(.playlist): playlist],
            order: [.equalizer, .playlist]
        )
        XCTAssertEqual(parents[.equalizer], .main)
        XCTAssertEqual(parents[.playlist], .panel(.equalizer))
    }

    // MARK: - Floating

    func testDetachedPanelIsFloating() {
        let faraway = CGRect(x: 1200, y: 50, width: 275, height: 232)
        let parents = AmpXDockGraph.parents(
            frames: [.main: self.main, .panel(.playlist): faraway],
            order: [.equalizer, .playlist]
        )
        XCTAssertNil(parents[.playlist])
        XCTAssertEqual(AmpXDockGraph.floating(order: [.playlist], parents: parents), [.playlist])
    }

    func testLonePlaylistDocksDirectlyBelowMain() {
        // EQ hidden: only the playlist is present, snapped below main → docks to main (no gap).
        let playlist = self.below(self.main, height: 232)
        let parents = AmpXDockGraph.parents(
            frames: [.main: self.main, .panel(.playlist): playlist],
            order: [.equalizer, .playlist]
        )
        XCTAssertEqual(parents[.playlist], .main)
    }
}

final class AmpXPanelPositionStoreTests: XCTestCase {
    @MainActor
    func testStoreAndRestoreOffset() {
        let store = AmpXPanelPositionStore(defaults: self.freshDefaults())
        let main = CGPoint(x: 100, y: 500)
        store.store(.playlist, panelOrigin: CGPoint(x: 120, y: 300), mainOrigin: main)

        XCTAssertEqual(store.offset(for: .playlist), CGSize(width: 20, height: -200))
        // Origin restores relative to a new main position.
        let restored = store.origin(for: .playlist, mainOrigin: CGPoint(x: 200, y: 600))
        XCTAssertEqual(restored, CGPoint(x: 220, y: 400))
    }

    @MainActor
    func testUnknownPanelHasNoOffset() {
        let store = AmpXPanelPositionStore(defaults: self.freshDefaults())
        XCTAssertNil(store.offset(for: .equalizer))
        XCTAssertNil(store.origin(for: .equalizer, mainOrigin: .zero))
    }

    @MainActor
    func testOffsetPersistsAcrossInstances() {
        let defaults = self.freshDefaults()
        let first = AmpXPanelPositionStore(defaults: defaults)
        first.store(.equalizer, panelOrigin: CGPoint(x: 100, y: 416), mainOrigin: CGPoint(x: 100, y: 500))

        let second = AmpXPanelPositionStore(defaults: defaults)
        XCTAssertEqual(second.offset(for: .equalizer), CGSize(width: 0, height: -84))
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "AmpXPanelPositionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

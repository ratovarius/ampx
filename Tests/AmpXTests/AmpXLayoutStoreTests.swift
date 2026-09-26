@testable import AmpX
import XCTest

@MainActor
final class AmpXLayoutStoreTests: XCTestCase {
    private let screen = AmpXTestScreen.standard

    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "AmpXLayoutStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func cleanup(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }

    private func store(_ defaults: UserDefaults) -> AmpXLayoutStore {
        AmpXLayoutStore(defaults: defaults, screen: self.screen)
    }

    func testRoundTripPersistsAllFrames() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        var layout = AmpXLayoutStore.defaultLayout(for: self.screen)
        layout.frames[.equalizer] = CGRect(x: 900, y: 300, width: 490, height: 200)
        layout.state.setCollapsed(.playlist, true)
        layout.state.reopen(.enthea)
        layout.playlistWidth = 600
        self.store(defaults).save(layout)

        XCTAssertEqual(self.store(defaults).load(), layout)
    }

    func testDefaultLayoutUsesDefaultFramesAtDefaultAnchor() {
        let layout = AmpXLayoutStore.defaultLayout(for: self.screen)
        let expected = AmpXLayout.defaultFrames(
            state: layout.state,
            playlistViewportHeight: layout.playlistViewportHeight,
            playlistWidth: layout.playlistWidth,
            anchorTopLeft: AmpXLayout.defaultAnchor(visibleFrame: self.screen.visibleFrame)
        )
        XCTAssertEqual(layout.frames, expected)
        XCTAssertEqual(layout.state, AmpXModuleState())
    }

    func testMissingFramesFallBackToDefaults() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        let json = """
        {"version": 2, "collapsed": [], "closed": ["enthea"],
         "frames": {"player": {"x": 300, "y": 800, "width": 490, "height": 223.5}},
         "playlistViewportHeight": 180, "playlistWidth": 490}
        """
        defaults.set(Data(json.utf8), forKey: AmpXLayoutStore.storageKey)

        let loaded = self.store(defaults).load()
        let expected = AmpXLayout.defaultFrames(
            state: loaded.state,
            playlistViewportHeight: 180,
            playlistWidth: 490,
            anchorTopLeft: CGPoint(x: 300, y: 1023.5)
        )
        XCTAssertEqual(loaded.frames[.player], CGRect(x: 300, y: 800, width: 490, height: 223.5))
        XCTAssertEqual(loaded.frames[.equalizer], expected[.equalizer])
        XCTAssertEqual(loaded.frames[.playlist], expected[.playlist])
        XCTAssertEqual(loaded.frames[.enthea], expected[.enthea])
    }

    func testOffscreenFramesAreClampedOnLoad() throws {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        var layout = AmpXLayoutStore.defaultLayout(for: self.screen)
        layout.frames[.equalizer] = CGRect(x: 5000, y: -900, width: 490, height: 200)
        self.store(defaults).save(layout)

        let frame = try XCTUnwrap(self.store(defaults).load().frames[.equalizer])
        XCTAssertTrue(self.screen.visibleFrame.contains(frame), "\(frame)")
    }

    func testDockedClusterIsClampedAsOneAndStaysDocked() throws {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        let visible = self.screen.visibleFrame
        var layout = AmpXLayoutStore.defaultLayout(for: self.screen)
        let player = try XCTUnwrap(layout.frames[.player])
        let enthea = try XCTUnwrap(layout.frames[.enthea])
        // Player near the right edge with ENTHEA flush to its right, hanging off screen.
        let shift = visible.maxX - player.maxX - 20
        for (id, frame) in layout.frames {
            layout.frames[id] = frame.offsetBy(dx: shift, dy: 0)
        }
        XCTAssertGreaterThan(enthea.offsetBy(dx: shift, dy: 0).maxX, visible.maxX)
        self.store(defaults).save(layout)

        let loaded = self.store(defaults).load()
        let loadedPlayer = try XCTUnwrap(loaded.frames[.player])
        let loadedEnthea = try XCTUnwrap(loaded.frames[.enthea])
        XCTAssertEqual(loadedEnthea.minX, loadedPlayer.maxX)
        XCTAssertEqual(loadedEnthea.maxY, loadedPlayer.maxY)
        XCTAssertLessThanOrEqual(loadedEnthea.maxX, visible.maxX)
        XCTAssertEqual(loaded.frames[.equalizer]?.minX, loadedPlayer.minX)
    }

    func testOversizedPlaylistPreferencesAreBoundedToScreen() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        var layout = AmpXLayoutStore.defaultLayout(for: self.screen)
        layout.playlistWidth = 20000
        layout.playlistViewportHeight = 20000
        self.store(defaults).save(layout)

        let loaded = self.store(defaults).load()
        let size = AmpXLayout.moduleSize(
            .playlist,
            state: loaded.state,
            playlistViewportHeight: loaded.playlistViewportHeight,
            playlistWidth: loaded.playlistWidth
        )
        XCTAssertLessThanOrEqual(size.width, self.screen.visibleFrame.width)
        XCTAssertLessThanOrEqual(size.height, self.screen.visibleFrame.height)
    }

    func testV1MigrationKeepsStateAndAnchorsAtStackTopLeft() throws {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        let json = """
        {"version": 1, "order": ["player", "equalizer", "playlist", "enthea"],
         "collapsed": ["equalizer"], "detached": ["playlist"], "closed": [],
         "stackFrame": {"x": 200, "y": 400, "width": 490, "height": 500},
         "playlistViewportHeight": 240, "playlistWidth": 600}
        """
        defaults.set(Data(json.utf8), forKey: AmpXLayoutStore.legacyStorageKey)

        let loaded = self.store(defaults).load()
        let player = try XCTUnwrap(loaded.frames[.player])
        XCTAssertEqual(player.minX, 200)
        XCTAssertEqual(player.maxY, 900)
        XCTAssertEqual(loaded.state.collapsed, [.equalizer])
        XCTAssertEqual(loaded.state.closed, [])
        XCTAssertEqual(loaded.playlistViewportHeight, 240)
        XCTAssertEqual(loaded.playlistWidth, 600)
        XCTAssertEqual(loaded.frames[.equalizer]?.maxY, player.minY)
    }

    func testCorruptDataReturnsDefault() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        defaults.set(Data("not-json".utf8), forKey: AmpXLayoutStore.storageKey)
        XCTAssertEqual(self.store(defaults).load(), AmpXLayoutStore.defaultLayout(for: self.screen))
    }

    func testPlayerIsNeverClosedAndUnknownIDsAreIgnored() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        let json = """
        {"version": 2, "collapsed": ["nope"], "closed": ["player", "equalizer", "mystery"],
         "frames": {}, "playlistViewportHeight": 180, "playlistWidth": 490}
        """
        defaults.set(Data(json.utf8), forKey: AmpXLayoutStore.storageKey)

        let loaded = self.store(defaults).load()
        XCTAssertEqual(loaded.state.closed, [.equalizer])
        XCTAssertTrue(loaded.state.collapsed.isEmpty)
        XCTAssertEqual(Set(loaded.frames.keys), Set(AmpXModuleID.allCases))
    }

    func testNonFiniteGeometryFallsBackToDefaults() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        let json = """
        {"version": 2, "collapsed": [], "closed": [],
         "frames": {"equalizer": {"x": 10, "y": 10, "width": 0, "height": 100}},
         "playlistViewportHeight": -4, "playlistWidth": 1}
        """
        defaults.set(Data(json.utf8), forKey: AmpXLayoutStore.storageKey)

        let loaded = self.store(defaults).load()
        XCTAssertEqual(loaded.playlistViewportHeight, AmpXMetrics.defaultPlaylistViewportHeight)
        XCTAssertEqual(loaded.playlistWidth, AmpXMetrics.minimumPlaylistWidth)
        XCTAssertGreaterThan(loaded.frames[.equalizer]?.width ?? 0, 0)
    }
}

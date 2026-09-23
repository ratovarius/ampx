@testable import AmpX
import XCTest

@MainActor
final class AmpXLayoutStoreTests: XCTestCase {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "AmpXLayoutStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func cleanup(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }

    func testCorruptJSONFallsBackToDefaults() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        defaults.set(Data("not-json".utf8), forKey: "AmpXModuleLayoutV1")
        let loaded = AmpXLayoutStore(defaults: defaults).load()
        XCTAssertEqual(loaded.state.order.first, .player)
        XCTAssertFalse(loaded.state.closed.contains(.player))
    }

    func testUnknownModuleIDIsIgnoredWhileRetainingKnownEntries() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        let json = """
        {
          "version": 1,
          "order": ["player", "unknown-module", "playlist", "equalizer"],
          "collapsed": [],
          "detached": [],
          "closed": ["enthea"]
        }
        """
        defaults.set(Data(json.utf8), forKey: "AmpXModuleLayoutV1")

        let loaded = AmpXLayoutStore(defaults: defaults).load()
        XCTAssertEqual(loaded.state.order, [.player, .playlist, .equalizer, .enthea])
    }

    func testDuplicateIDsAreNormalized() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        let json = """
        {
          "version": 1,
          "order": ["player", "equalizer", "equalizer", "playlist"],
          "collapsed": ["equalizer", "equalizer"],
          "detached": [],
          "closed": ["enthea", "enthea"]
        }
        """
        defaults.set(Data(json.utf8), forKey: "AmpXModuleLayoutV1")

        let loaded = AmpXLayoutStore(defaults: defaults).load()
        XCTAssertEqual(loaded.state.order, [.player, .equalizer, .playlist, .enthea])
        XCTAssertEqual(loaded.state.collapsed, [.equalizer])
        XCTAssertEqual(loaded.state.closed, [.enthea])
    }

    func testMissingPlayerIsRestoredAndProtected() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        let json = """
        {
          "version": 1,
          "order": ["equalizer", "playlist"],
          "collapsed": [],
          "detached": [],
          "closed": ["player"]
        }
        """
        defaults.set(Data(json.utf8), forKey: "AmpXModuleLayoutV1")

        let loaded = AmpXLayoutStore(defaults: defaults).load()
        XCTAssertEqual(loaded.state.order.first, .player)
        XCTAssertFalse(loaded.state.closed.contains(.player))
        XCTAssertFalse(loaded.state.detached.contains(.player))
    }

    func testNonFiniteGeometryFallsBackToScreenDefaults() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        let json = """
        {
          "version": 1,
          "order": ["player", "equalizer", "playlist", "enthea"],
          "collapsed": [],
          "detached": [],
          "closed": ["enthea"],
          "stackFrame": { "x": "NaN", "y": 0, "width": -10, "height": 0 },
          "detachedFrames": {
            "playlist": { "x": 0, "y": 0, "width": "Infinity", "height": 200 }
          },
          "playlistViewportHeight": "NaN"
        }
        """
        defaults.set(Data(json.utf8), forKey: "AmpXModuleLayoutV1")

        let loaded = AmpXLayoutStore(defaults: defaults, screen: testScreen()).load()
        XCTAssertTrue(loaded.stackFrame.width.isFinite)
        XCTAssertTrue(loaded.stackFrame.height.isFinite)
        XCTAssertGreaterThan(loaded.stackFrame.width, 0)
        XCTAssertGreaterThan(loaded.stackFrame.height, 0)
        XCTAssertTrue(loaded.detachedFrames.isEmpty)
        XCTAssertEqual(loaded.playlistViewportHeight, AmpXMetrics.defaultPlaylistViewportHeight)
    }

    func testDetachedStateRoundTrips() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        var state = AmpXModuleOrder()
        state.detach(.playlist)
        state.setCollapsed(.equalizer, true)

        let layout = AmpXSavedLayout(
            state: state,
            stackFrame: CGRect(x: 100, y: 200, width: 490, height: 600),
            detachedFrames: [.playlist: CGRect(x: 50, y: 80, width: 490, height: 400)],
            playlistViewportHeight: 180
        )

        let store = AmpXLayoutStore(defaults: defaults, screen: testScreen())
        store.save(layout)
        let loaded = store.load()

        XCTAssertTrue(loaded.state.detached.contains(.playlist))
        XCTAssertTrue(loaded.state.collapsed.contains(.equalizer))
        XCTAssertEqual(loaded.detachedFrames[.playlist], CGRect(x: 50, y: 80, width: 490, height: 400))
        XCTAssertEqual(loaded.playlistViewportHeight, 180)
    }

    func testLaunchLayoutStartsEveryModuleDocked() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        var state = AmpXModuleOrder()
        state.detach(.playlist)
        state.detach(.equalizer)

        let layout = AmpXSavedLayout(
            state: state,
            stackFrame: CGRect(x: 100, y: 200, width: 490, height: 600),
            detachedFrames: [.playlist: CGRect(x: 50, y: 80, width: 490, height: 400)],
            playlistViewportHeight: 180
        )

        let store = AmpXLayoutStore(defaults: defaults, screen: testScreen())
        store.save(layout)
        let loaded = store.loadForLaunch()

        XCTAssertTrue(loaded.state.detached.isEmpty)
        XCTAssertEqual(loaded.detachedFrames[.playlist], CGRect(x: 50, y: 80, width: 490, height: 400))
    }

    func testSaveAndLoadRoundTrip() {
        let (defaults, name) = self.isolatedDefaults()
        defer { cleanup(name) }

        var state = AmpXModuleOrder()
        state.close(.equalizer)
        state.setCollapsed(.playlist, true)

        let layout = AmpXSavedLayout(
            state: state,
            stackFrame: CGRect(x: 120, y: 240, width: 500, height: 620),
            detachedFrames: [:],
            playlistViewportHeight: 150
        )

        let store = AmpXLayoutStore(defaults: defaults, screen: testScreen())
        store.save(layout)
        let loaded = store.load()

        XCTAssertEqual(loaded, layout)
    }

    private func testScreen() -> NSScreen {
        NSScreen.main!
    }
}

@testable import AmpX
import XCTest

/// One window per module with Winamp docking rules (spec 2026-09-26-winamp-docking-design.md).
@MainActor
final class AmpXHostCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        state: AmpXModuleState = AmpXModuleState(),
        store: AmpXLayoutStore? = nil,
        entheaEnabled: Bool = false,
        terminate: @escaping () -> Void = {}
    ) -> AmpXHostCoordinator {
        let coordinator = AmpXHostCoordinator(
            state: state,
            skin: ClassicModernSkin(),
            layoutStore: store ?? self.makeIsolatedLayoutStore(),
            screen: AmpXTestScreen.standard,
            entheaEnabled: entheaEnabled,
            terminate: terminate
        )
        self.addTeardownBlock { @MainActor in coordinator.hideAllWindowsForTesting() }
        return coordinator
    }

    private func entheaOpenState() -> AmpXModuleState {
        var state = AmpXModuleState()
        state.reopen(.enthea)
        return state
    }

    private func frame(_ coordinator: AmpXHostCoordinator, _ id: AmpXModuleID) throws -> CGRect {
        try XCTUnwrap(coordinator.window(for: id)?.frame, "\(id) has no window")
    }

    // MARK: - Windows

    func testDefaultLaunchShowsOneWindowPerOpenModule() throws {
        let coordinator = self.makeCoordinator()
        coordinator.showAll()

        let expected = AmpXLayoutStore.defaultLayout(for: AmpXTestScreen.standard).frames
        for id: AmpXModuleID in [.player, .equalizer, .playlist] {
            XCTAssertEqual(coordinator.window(for: id)?.isVisible, true, "\(id)")
            XCTAssertEqual(try self.frame(coordinator, id), expected[id], "\(id)")
        }
        XCTAssertNil(coordinator.window(for: .enthea))
        XCTAssertFalse(coordinator.window(for: .player) === coordinator.window(for: .equalizer))
    }

    func testDefaultHostCreatesModuleViewsWithoutEnthea() {
        let coordinator = self.makeCoordinator()
        for moduleID: AmpXModuleID in [.player, .equalizer, .playlist] {
            XCTAssertNotNil(coordinator.moduleView(for: moduleID))
        }
        XCTAssertNil(coordinator.moduleView(for: .enthea))
    }

    // MARK: - Close / reopen

    func testCloseEqualizerLeavesGap() throws {
        let coordinator = self.makeCoordinator()
        coordinator.showAll()
        let playlist = try self.frame(coordinator, .playlist)

        coordinator.closeModule(.equalizer)

        XCTAssertEqual(coordinator.window(for: .equalizer)?.isVisible, false)
        XCTAssertTrue(coordinator.state.closed.contains(.equalizer))
        XCTAssertEqual(try self.frame(coordinator, .playlist), playlist)
    }

    func testReopenRestoresLastFrame() throws {
        let coordinator = self.makeCoordinator()
        coordinator.showAll()
        let moved = CGRect(x: 1200, y: 300, width: AmpXMetrics.compositionWidth, height: AmpXMetrics.equalizerHeight.rounded())
        coordinator.applyFrames([.equalizer: moved])

        coordinator.closeModule(.equalizer)
        coordinator.reopenModule(.equalizer)

        XCTAssertEqual(try self.frame(coordinator, .equalizer), moved)
    }

    func testCloseModulePersists() {
        let store = self.makeIsolatedLayoutStore()
        let coordinator = self.makeCoordinator(store: store)
        coordinator.showAll()
        coordinator.closeModule(.playlist)
        XCTAssertTrue(store.load().state.closed.contains(.playlist))
    }

    func testClosingPlayerQuits() {
        var quit = false
        let coordinator = self.makeCoordinator(terminate: { quit = true })
        coordinator.showAll()
        coordinator.closeModule(.player)
        XCTAssertTrue(quit)
        XCTAssertFalse(coordinator.state.closed.contains(.player))
    }

    // MARK: - Windowshade and resize

    func testCollapsePlayerPullsEqualizerButNotSideWindow() throws {
        let coordinator = self.makeCoordinator(state: self.entheaOpenState(), entheaEnabled: true)
        coordinator.showAll()
        let enthea = try self.frame(coordinator, .enthea)
        let playerTop = try self.frame(coordinator, .player).maxY

        coordinator.setCollapsed(.player, true)

        let player = try self.frame(coordinator, .player)
        XCTAssertEqual(player.maxY, playerTop)
        XCTAssertEqual(try self.frame(coordinator, .equalizer).maxY, player.minY)
        XCTAssertEqual(try self.frame(coordinator, .playlist).maxY, try self.frame(coordinator, .equalizer).minY)
        XCTAssertEqual(try self.frame(coordinator, .enthea), enthea)
    }

    func testExpandingAgainRestoresTheStack() {
        let coordinator = self.makeCoordinator()
        coordinator.showAll()
        let before = coordinator.openFrames()

        coordinator.setCollapsed(.player, true)
        coordinator.setCollapsed(.player, false)

        XCTAssertEqual(coordinator.openFrames(), before)
    }

    func testPlaylistResizeMovesWindowBelowOnly() throws {
        let coordinator = self.makeCoordinator(state: self.entheaOpenState(), entheaEnabled: true)
        coordinator.showAll()
        let playlist = try self.frame(coordinator, .playlist)
        let below = CGRect(
            x: playlist.minX,
            y: playlist.minY - AmpXMetrics.entheaHeight,
            width: AmpXMetrics.compositionWidth,
            height: AmpXMetrics.entheaHeight
        )
        let beside = CGRect(
            x: playlist.maxX,
            y: playlist.maxY - AmpXMetrics.equalizerHeight.rounded(),
            width: AmpXMetrics.compositionWidth,
            height: AmpXMetrics.equalizerHeight.rounded()
        )
        coordinator.applyFrames([.enthea: below, .equalizer: beside])

        coordinator.handlePlaylistResize(.began)
        coordinator.handlePlaylistResize(.changed(CGSize(width: 0, height: 40)))
        coordinator.handlePlaylistResize(.ended)

        let resized = try self.frame(coordinator, .playlist)
        XCTAssertEqual(resized.height, playlist.height + 40)
        XCTAssertEqual(resized.maxY, playlist.maxY)
        XCTAssertEqual(try self.frame(coordinator, .enthea).maxY, resized.minY)
        XCTAssertEqual(try self.frame(coordinator, .equalizer), beside)
    }

    // MARK: - Minimize, theater, persistence

    func testPlayerMiniaturizeHidesOthersAndRestores() {
        let coordinator = self.makeCoordinator()
        coordinator.showAll()

        coordinator.moduleWindowDidMiniaturize(.player)
        XCTAssertEqual(coordinator.window(for: .equalizer)?.isVisible, false)
        XCTAssertEqual(coordinator.window(for: .playlist)?.isVisible, false)

        coordinator.moduleWindowDidDeminiaturize(.player)
        XCTAssertEqual(coordinator.window(for: .equalizer)?.isVisible, true)
        XCTAssertEqual(coordinator.window(for: .playlist)?.isVisible, true)
    }

    func testFlushLayoutPersistenceWritesLiveFrames() {
        let store = self.makeIsolatedLayoutStore()
        let coordinator = self.makeCoordinator(store: store)
        coordinator.showAll()
        let moved = CGRect(x: 40, y: 60, width: AmpXMetrics.compositionWidth, height: AmpXMetrics.equalizerHeight.rounded())
        coordinator.window(for: .equalizer)?.setFrame(moved, display: false)

        coordinator.flushLayoutPersistence()

        XCTAssertEqual(store.load().frames[.equalizer], moved)
    }

    func testRelaunchRestoresFrames() throws {
        let store = self.makeIsolatedLayoutStore()
        let first = self.makeCoordinator(store: store)
        first.showAll()
        let moved = CGRect(x: 900, y: 200, width: AmpXMetrics.compositionWidth, height: AmpXMetrics.equalizerHeight.rounded())
        first.applyFrames([.equalizer: moved])

        let second = self.makeCoordinator(store: store)
        second.showAll()
        XCTAssertEqual(try self.frame(second, .equalizer), moved)
    }

    // MARK: - ENTHEA availability

    func testDisabledEntheaCannotReopenOrEnterTheater() {
        let coordinator = self.makeCoordinator(state: self.entheaOpenState(), entheaEnabled: false)
        XCTAssertNil(coordinator.moduleView(for: .enthea))
        XCTAssertTrue(coordinator.state.closed.contains(.enthea))

        coordinator.reopenModule(.enthea)
        coordinator.toggleTheater()
        XCTAssertTrue(coordinator.state.closed.contains(.enthea))
        XCTAssertFalse(coordinator.isInTheater)
    }

    func testDisabledEntheaPreservesItsSavedOpenState() {
        let store = self.makeIsolatedLayoutStore()
        var saved = store.load()
        saved.state.reopen(.enthea)
        saved.state.setCollapsed(.enthea, true)
        store.save(saved)

        let coordinator = self.makeCoordinator(state: saved.state, store: store, entheaEnabled: false)
        coordinator.closeModule(.equalizer)

        let persisted = store.load()
        XCTAssertFalse(persisted.state.closed.contains(.enthea), "Temporary unavailability must not overwrite the saved open state")
        XCTAssertTrue(persisted.state.collapsed.contains(.enthea))
        XCTAssertTrue(persisted.state.closed.contains(.equalizer))
    }

    func testOpenEntheaStateMountsHostWhenFeatureIsEnabled() {
        let coordinator = self.makeCoordinator(state: self.entheaOpenState(), entheaEnabled: true)
        let content = coordinator.moduleView(for: .enthea)?.content as? EntheaModuleContent
        XCTAssertNotNil(content?.hostViewForTesting)
    }

    func testClosedEntheaStateDoesNotMountHost() throws {
        let coordinator = self.makeCoordinator(entheaEnabled: true)
        let content = try XCTUnwrap(coordinator.moduleView(for: .enthea)?.content as? EntheaModuleContent)
        XCTAssertNil(content.hostViewForTesting)
    }
}

extension AmpXHostCoordinator {
    /// Test teardown: hides every module window without quitting (closing the Player quits).
    func hideAllWindowsForTesting() {
        for id in AmpXModuleID.allCases {
            self.window(for: id)?.orderOut(nil)
        }
    }
}

/// Coordinator behavior tests must never overwrite the running app's saved layout.
extension XCTestCase {
    @MainActor
    func makeIsolatedLayoutStore() -> AmpXLayoutStore {
        let suite = "AmpXLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AmpXLayoutStore(defaults: defaults, screen: AmpXTestScreen.standard)
    }
}

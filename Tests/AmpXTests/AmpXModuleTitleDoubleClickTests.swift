@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXModuleTitleDoubleClickTests: XCTestCase {
    func testExpandedTitleAndGripDoubleClickToggleOnceWithoutStartingDrag() {
        for id in AmpXModuleID.allCases {
            let header = AmpXModuleHeaderView(moduleID: id, skin: ClassicModernSkin())
            header.frame = CGRect(x: 0, y: 0, width: 490, height: AmpXMetrics.headerHeight)
            var toggles = 0
            var gripEvents = 0
            header.onCollapse = { toggles += 1 }
            header.onGripMouseDown = { _ in gripEvents += 1 }
            header.onGripMouseUp = { _ in gripEvents += 1 }
            for point in [self.center(header.titleGroupFrame), self.center(header.gripFrame), CGPoint(x: 70, y: 10)] {
                let before = toggles
                self.doubleClick(header, at: point)
                XCTAssertEqual(toggles, before + 1, "\(id): \(point)")
            }
            XCTAssertEqual(gripEvents, 0)
        }
    }

    func testExpandedHeaderButtonsKeepTheirOwnActions() {
        let header = AmpXModuleHeaderView(moduleID: .player, skin: ClassicModernSkin())
        header.frame = CGRect(x: 0, y: 0, width: 490, height: AmpXMetrics.headerHeight)
        var actions: [String] = []
        header.onCollapse = { actions.append("collapse") }
        header.onClose = { actions.append("close") }
        header.onMinimize = { actions.append("minimize") }
        for item in header.headerButtonLayout() {
            self.doubleClick(header, at: self.center(item.frame))
        }
        XCTAssertEqual(actions, ["minimize", "collapse", "close"])
    }

    func testCompactTitleDoubleClickExpandsButProtectedControlsDoNot() throws {
        let coordinator = self.makeCoordinator()
        for id in [AmpXModuleID.player, .equalizer, .playlist] {
            let compact = try XCTUnwrap(coordinator.moduleView(for: id)?.compactContent)
            compact.frame = CGRect(x: 0, y: 0, width: id == .playlist ? 800 : 490, height: AmpXCompactMetrics.playerHeight)
            compact.layoutSubtreeIfNeeded()
            var expansions = 0
            var gripEvents = 0
            compact.onExpand = { expansions += 1 }
            compact.onGripMouseDown = { _ in gripEvents += 1 }
            compact.onGripMouseUp = { _ in gripEvents += 1 }
            self.doubleClick(compact, at: self.center(compact.chromeLayout.brand))
            self.doubleClick(compact, at: self.center(compact.chromeLayout.grip))
            XCTAssertEqual(expansions, 2)
            XCTAssertEqual(gripEvents, 0)
            for rect in compact.protectedRects {
                self.doubleClick(compact, at: self.center(rect))
            }
            self.doubleClick(compact, at: CGPoint(x: -1, y: -1))
            XCTAssertEqual(expansions, 2, "Controls and out-of-bounds clicks must not expand \(id)")
        }
    }

    func testSingleGripClicksKeepDragBehavior() {
        let header = AmpXModuleHeaderView(moduleID: .equalizer, skin: ClassicModernSkin())
        header.frame = CGRect(x: 0, y: 0, width: 490, height: AmpXMetrics.headerHeight)
        let compact = AmpXCompactModuleView(moduleID: .equalizer, skin: ClassicModernSkin())
        compact.frame = CGRect(x: 0, y: 0, width: 490, height: AmpXCompactMetrics.equalizerHeight)
        var toggles = 0
        var gripEvents = 0
        header.onCollapse = { toggles += 1 }
        compact.onExpand = { toggles += 1 }
        header.onGripMouseDown = { _ in gripEvents += 1 }
        header.onGripMouseUp = { _ in gripEvents += 1 }
        compact.onGripMouseDown = { _ in gripEvents += 1 }
        compact.onGripMouseUp = { _ in gripEvents += 1 }
        for (view, point) in [(header as NSView, self.center(header.gripFrame)),
                              (compact as NSView, self.center(compact.chromeLayout.grip))] {
            view.mouseDown(with: self.event(.leftMouseDown, view: view, point: point, clicks: 1))
            view.mouseUp(with: self.event(.leftMouseUp, view: view, point: point, clicks: 1))
        }
        XCTAssertEqual(toggles, 0)
        XCTAssertEqual(gripEvents, 4)
    }

    func testDoubleClickRoundTripsDockedAndDetachedModulesWithoutChangingWidthOrHost() throws {
        let coordinator = self.makeCoordinator()
        coordinator.showStack()
        coordinator.setPlaylistWidth(800)
        defer {
            for id in coordinator.state.detached { coordinator.closeModule(id) }
            coordinator.closeStack()
        }
        for id in [AmpXModuleID.player, .equalizer, .playlist] {
            let module = try XCTUnwrap(coordinator.moduleView(for: id))
            for detached in id == .player ? [false] : [false, true] {
                if detached { coordinator.detach(id, at: CGPoint(x: 100, y: 600), inheritedWidth: 490) }
                let host = try XCTUnwrap(module.window)
                let expandedSize = module.frame.size
                let content = module.content
                let top = host.frame.maxY
                self.doubleClick(module.header, at: self.center(module.header.gripFrame))
                XCTAssertTrue(coordinator.state.collapsed.contains(id))
                XCTAssertFalse(coordinator.dragController.isDragging)
                XCTAssertEqual(module.frame.width, expandedSize.width)
                XCTAssertEqual(host.frame.maxY, top, accuracy: 0.5)
                if let compact = module.compactContent {
                    self.doubleClick(compact, at: self.center(compact.chromeLayout.grip))
                }
                XCTAssertFalse(coordinator.state.collapsed.contains(id))
                XCTAssertFalse(coordinator.dragController.isDragging)
                XCTAssertIdentical(module.window, host)
                XCTAssertIdentical(module.content, content)
                XCTAssertEqual(module.frame.size, expandedSize)
                if detached { coordinator.redock(id, at: 2) }
            }
        }
    }

    private func makeCoordinator() -> AmpXHostCoordinator {
        AmpXHostCoordinator(
            state: AmpXModuleOrder(), skin: ClassicModernSkin(), layoutStore: makeIsolatedLayoutStore(),
            audioPlayer: AudioPlayer(installRemoteCommands: false),
            playlistManager: PlaylistManager(audioPlayer: MockAudioPlayer(), restoreBookmarks: false,
                                              restorePlaylist: false, alertPresenter: SilentPlaylistAlertPresenter()),
            entheaEnabled: false
        )
    }

    private func center(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private func doubleClick(_ view: NSView, at point: CGPoint) {
        let down = self.event(.leftMouseDown, view: view, point: point, clicks: 2)
        let up = self.event(.leftMouseUp, view: view, point: point, clicks: 2)
        view.mouseDown(with: down)
        view.mouseUp(with: up)
    }

    private func event(_ type: NSEvent.EventType, view: NSView, point: CGPoint, clicks: Int) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1
        )!
    }
}

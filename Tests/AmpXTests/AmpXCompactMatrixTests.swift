@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXCompactMatrixTests: XCTestCase {
    func testEveryCollapseCombinationWidthOrderAndRightColumnHasNoVerticalGaps() throws {
        for width: CGFloat in [490, 800] {
            for right in [false, true] {
                for reordered in [false, true] {
                    for mask in 0 ..< 8 {
                        var state = AmpXModuleOrder()
                        if right {
                            state.reopen(.enthea)
                        }
                        if reordered {
                            state.order = [.playlist, .player, .equalizer, .enthea]
                        }
                        for (index, id) in [AmpXModuleID.player, .equalizer, .playlist].enumerated() {
                            state.setCollapsed(id, mask & (1 << index) != 0)
                        }
                        let layout = AmpXLayout.calculate(
                            state: state,
                            width: width,
                            playlistViewportHeight: 180,
                            availableHeight: 10000,
                            playlistWidth: width
                        )
                        var bottom: CGFloat = 0
                        for id in state.order where id != .enthea {
                            let frame = try XCTUnwrap(layout.frames[id])
                            XCTAssertEqual(frame.minY, bottom, accuracy: 0.0001)
                            XCTAssertEqual(frame.width, id == .playlist ? width : 490)
                            bottom = frame.maxY
                        }
                        XCTAssertEqual(layout.frames[.enthea]?.minX, right ? width + 6 : nil)
                        XCTAssertEqual(layout.contentHeight, right ? max(bottom, AmpXMetrics.entheaHeight) : bottom)
                        if state.collapsed.contains(.playlist) {
                            XCTAssertEqual(layout.frames[.playlist]?.height, AmpXCompactMetrics.playlistHeight)
                            XCTAssertEqual(layout.playlistViewportHeight, 180)
                        }
                        state.close(.equalizer)
                        state.detach(.playlist)
                        let excluded = AmpXLayout.calculate(
                            state: state,
                            width: width,
                            playlistViewportHeight: 180,
                            availableHeight: 10000,
                            playlistWidth: width
                        )
                        XCTAssertNil(excluded.frames[.equalizer])
                        XCTAssertNil(excluded.frames[.playlist])
                        XCTAssertEqual(excluded.frames[.enthea]?.minX, right ? 496 : nil)
                    }
                }
            }
        }
    }

    func testLaunchRestoresCompactWidthAndViewportIgnoringOldSavedHeight() throws {
        let store = makeIsolatedLayoutStore()
        var saved = store.load()
        saved.state.setCollapsed(.playlist, true)
        saved.state.detach(.playlist)
        saved.playlistWidth = 800
        saved.playlistViewportHeight = 190
        saved.detachedFrames[.playlist] = CGRect(x: 200, y: 300, width: 800, height: 600)
        saved.stackFrame.size.height = 900
        store.save(saved)
        let restored = store.loadForLaunch()
        XCTAssertTrue(restored.state.detached.isEmpty, "Established launch policy docks modules")
        let coordinator = self.makeCoordinator(state: restored.state, store: store)
        coordinator.showStack()
        defer { coordinator.closeStack() }
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        XCTAssertEqual(module.frame.width, 800)
        XCTAssertEqual(module.frame.height, AmpXCompactMetrics.playlistHeight, accuracy: 0.5)
        coordinator.closeModule(.playlist)
        XCTAssertEqual(coordinator.stackWindow?.frame.width, 490)
        coordinator.reopenModule(.playlist)
        XCTAssertEqual(module.frame.width, 800)
        coordinator.setCollapsed(.playlist, false)
        XCTAssertEqual(module.frame.height, AmpXMetrics.headerHeight + AmpXMetrics.playlistNonRowChrome + 190, accuracy: 0.5)
    }

    func testCompactViewsAndSharedBindingsReleaseWithCoordinator() async {
        weak var weakPlayer: PlayerCompactContent?
        weak var weakEQ: EqualizerCompactContent?
        weak var weakPlaylist: PlaylistCompactContent?
        weak var weakFooter: PlaylistFooterView?
        autoreleasepool {
            let coordinator = self.makeCoordinator(state: AmpXModuleOrder(), store: makeIsolatedLayoutStore())
            weakPlayer = coordinator.moduleView(for: .player)?.compactContent as? PlayerCompactContent
            weakEQ = coordinator.moduleView(for: .equalizer)?.compactContent as? EqualizerCompactContent
            weakPlaylist = coordinator.moduleView(for: .playlist)?.compactContent as? PlaylistCompactContent
            weakFooter = coordinator.moduleView(for: .playlist)?.content.subviews.compactMap { $0 as? PlaylistFooterView }.first
        }
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertNil(weakPlayer)
        XCTAssertNil(weakEQ)
        XCTAssertNil(weakPlaylist)
        XCTAssertNil(weakFooter)
    }

    private func makeCoordinator(state: AmpXModuleOrder, store: AmpXLayoutStore) -> AmpXHostCoordinator {
        AmpXHostCoordinator(
            state: state, skin: ClassicModernSkin(), layoutStore: store,
            audioPlayer: AudioPlayer(installRemoteCommands: false),
            playlistManager: PlaylistManager(
                audioPlayer: MockAudioPlayer(),
                restoreBookmarks: false,
                restorePlaylist: false,
                alertPresenter: SilentPlaylistAlertPresenter()
            ),
            entheaEnabled: false
        )
    }
}

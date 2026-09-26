@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXCompactMatrixTests: XCTestCase {
    /// Every windowshade combination keeps the default Winamp stack flush: collapsing any window
    /// pulls the windows docked beneath it up, and ENTHEA stays docked to the Player's right edge.
    func testEveryCollapseCombinationKeepsDockedWindowsFlush() throws {
        for width: CGFloat in [490, 800] {
            for right in [false, true] {
                for mask in 0 ..< 8 {
                    var expanded = AmpXModuleState()
                    if right {
                        expanded.reopen(.enthea)
                    }
                    let before = AmpXLayout.defaultFrames(
                        state: expanded,
                        playlistViewportHeight: 180,
                        playlistWidth: width,
                        anchorTopLeft: CGPoint(x: 100, y: 1000)
                    ).filter { !expanded.closed.contains($0.key) }
                    var state = expanded
                    for (index, id) in [AmpXModuleID.player, .equalizer, .playlist].enumerated() {
                        state.setCollapsed(id, mask & (1 << index) != 0)
                    }
                    let sizes = Dictionary(uniqueKeysWithValues: before.keys.map { id in
                        (id, AmpXLayout.moduleSize(id, state: state, playlistViewportHeight: 180, playlistWidth: width))
                    })
                    let after = AmpXSnapGeometry.reflow(before: before, sizes: sizes)

                    let player = try XCTUnwrap(after[.player])
                    let equalizer = try XCTUnwrap(after[.equalizer])
                    let playlist = try XCTUnwrap(after[.playlist])
                    XCTAssertEqual(player.maxY, 1000)
                    XCTAssertEqual(equalizer.maxY, player.minY)
                    XCTAssertEqual(playlist.maxY, equalizer.minY)
                    XCTAssertEqual(playlist.width, width)
                    XCTAssertEqual(equalizer.width, 490)
                    if state.collapsed.contains(.playlist) {
                        XCTAssertEqual(playlist.height, AmpXCompactMetrics.playlistHeight.rounded())
                    }
                    if right {
                        XCTAssertEqual(after[.enthea], before[.enthea], "ENTHEA is beside the Player, not below it")
                    }
                }
            }
        }
    }

    func testLaunchRestoresCompactWidthViewportAndFrame() throws {
        let store = makeIsolatedLayoutStore()
        var saved = store.load()
        saved.state.setCollapsed(.playlist, true)
        saved.playlistWidth = 800
        saved.playlistViewportHeight = 190
        saved.frames[.playlist] = CGRect(x: 200, y: 300, width: 800, height: 600)
        store.save(saved)
        let restored = store.load()
        let coordinator = self.makeCoordinator(state: restored.state, store: store)
        coordinator.showAll()
        defer { coordinator.hideAllWindowsForTesting() }
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let window = try XCTUnwrap(coordinator.window(for: .playlist))
        XCTAssertEqual(module.frame.width, 800)
        XCTAssertEqual(module.frame.height, AmpXCompactMetrics.playlistHeight, accuracy: 0.5)
        XCTAssertEqual(window.frame.minX, 200)
        XCTAssertEqual(window.frame.maxY, 900, "The saved top-left corner wins over the stale saved height")
        coordinator.closeModule(.playlist)
        XCTAssertEqual(coordinator.window(for: .player)?.frame.width, 490)
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
            let coordinator = self.makeCoordinator(state: AmpXModuleState(), store: makeIsolatedLayoutStore())
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

    private func makeCoordinator(state: AmpXModuleState, store: AmpXLayoutStore) -> AmpXHostCoordinator {
        AmpXHostCoordinator(
            state: state, skin: ClassicModernSkin(), layoutStore: store, screen: AmpXTestScreen.standard,
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

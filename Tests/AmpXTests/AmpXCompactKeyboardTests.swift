@testable import AmpX
import AppKit
import XCTest

@MainActor
final class AmpXCompactKeyboardTests: XCTestCase {
    func testActualCompactPlaylistFocusCannotEditHiddenRowsAndReturnActivatesMenu() throws {
        let audio = AudioPlayer(installRemoteCommands: false)
        let manager = PlaylistManager(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let coordinator = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            audioPlayer: audio,
            playlistManager: manager,
            entheaEnabled: false
        )
        coordinator.showStack()
        defer { coordinator.closeStack() }
        let module = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        let rows = try XCTUnwrap(module.content.subviews.compactMap { $0 as? PlaylistRowsView }.first)
        let adapter = try XCTUnwrap(rows.keyboardAdapter)
        let track = Track(title: "Selected", artist: "Test")
        manager.addTracks([track])
        adapter.selection.selectOnly(track.id)
        coordinator.setCollapsed(.playlist, true)
        let compact = try XCTUnwrap(module.compactContent as? PlaylistCompactContent)
        let window = try XCTUnwrap(module.window)
        XCTAssertTrue(window.makeFirstResponder(compact.listOptionsButton))
        let context = AmpXKeyRouter.focusContext(from: window)
        XCTAssertEqual(context.module, .playlist)
        XCTAssertFalse(context.playlistEditingEnabled)
        XCTAssertFalse(AmpXPlaylistKeyboard.isActive)
        for code: UInt16 in [51, 117, 125, 126] {
            XCTAssertFalse(AmpXKeyRouter.dispatch(
                self.key(code),
                context: context,
                window: window,
                audioPlayer: audio,
                playlistManager: manager,
                entheaTheater: nil
            ))
        }
        var menuPresses = 0
        compact.listOptionsButton.action = { menuPresses += 1 }
        XCTAssertTrue(AmpXKeyRouter.dispatch(
            self.key(36),
            context: context,
            window: window,
            audioPlayer: audio,
            playlistManager: manager,
            entheaTheater: nil
        ))
        XCTAssertEqual(menuPresses, 1)
        XCTAssertEqual(manager.tracks.map(\.id), [track.id])
        XCTAssertEqual(adapter.selection.selectedIDs, [track.id])
        XCTAssertEqual(AmpXKeyRouter.route(event: self.key(49), context: context), .global)
        coordinator.setCollapsed(.playlist, false)
        // AppKit may still report this test window occluded until the next window-server
        // transaction. Exercise the visible presentation callback explicitly.
        module.applyPresentationVisibility(.init(expanded: true, compact: false))
        XCTAssertTrue(AmpXPlaylistKeyboard.isActive)
    }

    func testCollapsedPlaylistRetainsModuleIdentityWithoutEditingRows() {
        let context = AmpXFocusContext(module: .playlist, control: nil, playlistEditingEnabled: false)
        for code: UInt16 in [126, 125, 36, 51, 117] {
            XCTAssertEqual(AmpXKeyRouter.route(event: self.key(code), context: context), .unhandled)
        }
        XCTAssertEqual(context.module, .playlist)
        XCTAssertEqual(AmpXKeyRouter.route(event: self.key(49), context: context), .global)
    }

    func testCompactTimerAndSpectrumHandleReturnWhileSpaceRemainsGlobal() {
        let state = AmpXPlayerPresentationState()
        let timer = TimeDisplayView(skin: ClassicModernSkin(), presentationState: state)
        timer.style = .compact
        let spectrum = SpectrumWellView(skin: ClassicModernSkin())
        spectrum.geometry = .compact
        let body = AmpXModuleContent(skin: ClassicModernSkin())
        body.addSubview(timer)
        body.addSubview(spectrum)
        let module = AmpXModuleView(moduleID: .player, content: body, skin: ClassicModernSkin())
        let window = AmpXHostWindow(
            contentRect: CGRect(x: 100, y: 100, width: 490, height: 290),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = module
        defer { window.close() }
        for view in [timer as NSView, spectrum] {
            XCTAssertTrue(window.makeFirstResponder(view))
            let context = AmpXKeyRouter.focusContext(from: window)
            XCTAssertEqual(context.control, .button)
            XCTAssertEqual(context.module, .player)
            XCTAssertEqual(AmpXKeyRouter.route(event: self.key(49), context: context), .global)
            XCTAssertTrue(AmpXKeyRouter.dispatch(
                self.key(36),
                context: context,
                window: window,
                audioPlayer: nil,
                playlistManager: nil,
                entheaTheater: nil
            ))
        }
        XCTAssertTrue(state.showRemainingTime)
        XCTAssertEqual(spectrum.settings.style, .smoothSpectrum)
    }

    func testSpaceDoesNotActivateCompactStopOrExpand() {
        for code: UInt16 in [49, 36, 76] {
            XCTAssertEqual(
                AmpXKeyRouter.route(event: self.key(code), context: .init(module: .player, control: .button)),
                code == 49 ? .global : .control
            )
        }
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: code
        )!
    }
}

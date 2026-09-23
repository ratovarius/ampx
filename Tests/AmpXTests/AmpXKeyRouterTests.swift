@testable import AmpX
import XCTest

@MainActor
final class AmpXKeyRouterTests: XCTestCase {
    func testSpaceWithFocusedButtonRoutesToGlobalPlayPause() {
        let event = self.keyDown(keyCode: 49, characters: " ")
        let context = AmpXFocusContext(module: .player, control: .button)
        XCTAssertEqual(AmpXKeyRouter.route(event: event, context: context), .global)
    }

    func testReturnWithFocusedButtonRoutesToControl() {
        let context = AmpXFocusContext(module: .player, control: .button)
        for keyCode: UInt16 in [36, 76] {
            XCTAssertEqual(
                AmpXKeyRouter.route(event: self.keyDown(keyCode: keyCode), context: context),
                .control
            )
        }
    }

    func testArrowsWithFocusedSliderRouteToControl() {
        let context = AmpXFocusContext(module: .equalizer, control: .slider)
        for keyCode: UInt16 in [123, 124, 125, 126] {
            XCTAssertEqual(
                AmpXKeyRouter.route(event: self.keyDown(keyCode: keyCode), context: context),
                .control
            )
        }
    }

    func testEscapeWithFocusedControlRoutesToControl() {
        let event = self.keyDown(keyCode: 53)
        XCTAssertEqual(
            AmpXKeyRouter.route(event: event, context: AmpXFocusContext(module: .player, control: .button)),
            .control
        )
    }

    func testPlaylistArrowKeysRouteToPlaylistWhenModuleFocused() {
        let context = AmpXFocusContext(module: .playlist, control: nil)
        XCTAssertEqual(
            AmpXKeyRouter.route(event: self.keyDown(keyCode: 126), context: context),
            .playlist
        )
        XCTAssertEqual(
            AmpXKeyRouter.route(event: self.keyDown(keyCode: 36), context: context),
            .playlist
        )
    }

    func testPlaylistBindingsPreserveModifiers() {
        let context = AmpXFocusContext(module: .playlist, control: nil)
        XCTAssertEqual(
            AmpXKeyRouter.route(
                event: self.keyDown(keyCode: 0, modifierFlags: [.command]),
                context: context
            ),
            .playlist
        )
        XCTAssertEqual(
            AmpXKeyRouter.route(
                event: self.keyDown(keyCode: 126, modifierFlags: [.option]),
                context: context
            ),
            .playlist
        )
        XCTAssertEqual(
            AmpXKeyRouter.route(
                event: self.keyDown(keyCode: 126, modifierFlags: [.control]),
                context: context
            ),
            .unhandled
        )
    }

    func testEntheaKeysRouteToEntheaModule() {
        let context = AmpXFocusContext(module: .enthea, control: nil)
        XCTAssertEqual(
            AmpXKeyRouter.route(event: self.keyDown(keyCode: 3), context: context),
            .enthea
        )
        XCTAssertEqual(
            AmpXKeyRouter.route(event: self.keyDown(keyCode: 53), context: context),
            .enthea
        )
    }

    func testGlobalPlaybackRoutesWhenNoControlFocused() {
        let context = AmpXFocusContext(module: .player, control: nil)
        XCTAssertEqual(
            AmpXKeyRouter.route(event: self.keyDown(keyCode: 49), context: context),
            .global
        )
        XCTAssertEqual(
            AmpXKeyRouter.route(event: self.keyDown(keyCode: 6), context: context),
            .global
        )
    }

    func testGlobalLetterShortcutsRouteWhenControlFocused() {
        for control: AmpXControlFocus in [.button, .slider] {
            let context = AmpXFocusContext(module: .player, control: control)
            XCTAssertEqual(
                AmpXKeyRouter.route(event: self.keyDown(keyCode: 6), context: context),
                .global
            )
        }
    }

    func testTextResponderBypassesGlobalSingleLetterShortcuts() {
        let context = AmpXFocusContext(module: .player, control: nil, textResponderActive: true)
        XCTAssertEqual(
            AmpXKeyRouter.route(event: self.keyDown(keyCode: 8), context: context),
            .unhandled
        )
        XCTAssertEqual(
            AmpXKeyRouter.route(event: self.keyDown(keyCode: 49, characters: " "), context: context),
            .unhandled
        )
        XCTAssertEqual(
            AmpXKeyRouter.route(event: self.keyDown(keyCode: 123), context: context),
            .global
        )
    }

    func testModuleCommandKeysAreRecognized() {
        XCTAssertEqual(
            AmpXKeyRouter.moduleCommand(for: self.keyDown(keyCode: 126, modifierFlags: [.command, .option])),
            .moveUp
        )
        XCTAssertEqual(
            AmpXKeyRouter.moduleCommand(for: self.keyDown(keyCode: 125, modifierFlags: [.command, .option])),
            .moveDown
        )
        XCTAssertEqual(
            AmpXKeyRouter.moduleCommand(for: self.keyDown(keyCode: 2, modifierFlags: [.command, .option])),
            .toggleDetach
        )
        XCTAssertEqual(
            AmpXKeyRouter.moduleCommand(for: self.keyDown(keyCode: 8, modifierFlags: [.command, .option])),
            .toggleCollapse
        )
    }

    func testModuleCommandsDoNotRouteToGlobal() {
        let context = AmpXFocusContext(module: .player, control: nil)
        let event = self.keyDown(keyCode: 8, modifierFlags: [.command, .option])
        XCTAssertEqual(AmpXKeyRouter.route(event: event, context: context), .unhandled)
        XCTAssertNotNil(AmpXKeyRouter.moduleCommand(for: event))
    }

    func testControlPrecedenceOverPlaylistModule() {
        let context = AmpXFocusContext(module: .playlist, control: .button)
        XCTAssertEqual(
            AmpXKeyRouter.route(event: self.keyDown(keyCode: 126), context: context),
            .playlist
        )
        XCTAssertEqual(
            AmpXKeyRouter.route(event: self.keyDown(keyCode: 36), context: context),
            .control
        )
    }

    func testLeftRightSeekWhilePlaylistFocusedButUpDownMoveSelection() {
        let context = AmpXFocusContext(module: .playlist, control: nil)
        for keyCode: UInt16 in [123, 124] {
            XCTAssertEqual(AmpXKeyRouter.route(event: self.keyDown(keyCode: keyCode), context: context), .global)
        }
        for keyCode: UInt16 in [125, 126] {
            XCTAssertEqual(AmpXKeyRouter.route(event: self.keyDown(keyCode: keyCode), context: context), .playlist)
        }
    }

    func testOptionThreeShowsFileInfoFromEveryModule() {
        let event = self.keyDown(keyCode: 20, modifierFlags: [.option])
        for module: AmpXModuleID in [.player, .equalizer, .playlist] {
            let context = AmpXFocusContext(module: module, control: nil)
            XCTAssertEqual(AmpXKeyRouter.route(event: event, context: context), .global)
        }
        let typing = AmpXFocusContext(module: .player, control: nil, textResponderActive: true)
        XCTAssertEqual(AmpXKeyRouter.route(event: event, context: typing), .unhandled)
    }

    func testCommandTTogglesTimeModeOutsideModuleRouting() {
        let event = self.keyDown(keyCode: 17, modifierFlags: [.command])
        XCTAssertEqual(AmpXKeyRouter.playerCommand(for: event), .toggleTimeMode)
        XCTAssertEqual(
            AmpXKeyRouter.route(event: event, context: AmpXFocusContext(module: .playlist, control: nil)),
            .unhandled
        )
        XCTAssertNil(AmpXKeyRouter.playerCommand(for: self.keyDown(keyCode: 17)))
    }

    func testDispatchInvokesRecipientOnce() {
        var controlCount = 0
        var globalCount = 0
        let event = self.keyDown(keyCode: 36)
        let context = AmpXFocusContext(module: .player, control: .button)
        let handled = AmpXKeyRouter.dispatch(
            event,
            context: context,
            controlHandler: { controlCount += 1 },
            playlistHandler: {},
            entheaHandler: {},
            globalHandler: { globalCount += 1 }
        )
        XCTAssertTrue(handled)
        XCTAssertEqual(controlCount, 1)
        XCTAssertEqual(globalCount, 0)
    }

    private func keyDown(
        keyCode: UInt16,
        characters: String = "",
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

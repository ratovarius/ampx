@testable import AmpX
import XCTest

@MainActor
final class AmpXAccessibilityTests: XCTestCase {
    func testButtonExposesPressAction() {
        let skin = ClassicModernSkin()
        let button = AmpXButton(skin: skin)
        button.label = "Play"
        XCTAssertEqual(button.accessibilityRole(), .button)
        XCTAssertEqual(button.accessibilityLabel(), "Play")

        var fired = false
        button.action = { fired = true }
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertTrue(fired)
    }

    func testSliderExposesValueRangeAndStepActions() {
        let skin = ClassicModernSkin()
        let slider = AmpXSlider(skin: skin)
        slider.range = -12 ... 12
        slider.step = 1
        slider.setValue(0, sendChange: false)
        slider.accessibilityTitle = "Bass"

        XCTAssertEqual(slider.accessibilityRole(), .slider)
        XCTAssertEqual(slider.accessibilityLabel(), "Bass")
        XCTAssertEqual(slider.accessibilityValue() as? Double, 0)
        XCTAssertEqual(slider.accessibilityMinValue() as? Double, -12)
        XCTAssertEqual(slider.accessibilityMaxValue() as? Double, 12)

        XCTAssertTrue(slider.accessibilityPerformIncrement())
        XCTAssertEqual(slider.value, 1, accuracy: 0.0001)
        XCTAssertTrue(slider.accessibilityPerformDecrement())
        XCTAssertEqual(slider.value, 0, accuracy: 0.0001)
    }

    func testModuleHeaderIsFocusableAndExposesActions() {
        let skin = ClassicModernSkin()
        let header = AmpXModuleHeaderView(moduleID: .playlist, skin: skin)
        XCTAssertTrue(header.acceptsFirstResponder)

        var collapsed = false
        var closed = false
        header.onCollapse = { collapsed = true }
        header.onClose = { closed = true }

        let actions = header.accessibilityCustomActions() ?? []
        let titles = actions.map(\.name)
        XCTAssertTrue(titles.contains("Collapse"))
        XCTAssertTrue(titles.contains("Close"))
        XCTAssertTrue(titles.contains("Detach"))

        XCTAssertTrue(header.accessibilityCollapse())
        XCTAssertTrue(header.accessibilityClose())
        XCTAssertTrue(collapsed)
        XCTAssertTrue(closed)
    }

    func testModuleViewWiresTabTraversalAcrossControls() {
        let skin = ClassicModernSkin()
        let module = AmpXModuleView(
            moduleID: .player,
            content: PlayerModuleContent(
                skin: skin,
                audioPlayer: AudioPlayer(installRemoteCommands: false),
                playlistManager: PlaylistManager(
                    audioPlayer: MockAudioPlayer(),
                    restoreBookmarks: false,
                    restorePlaylist: false,
                    alertPresenter: SilentPlaylistAlertPresenter()
                ),
                onToggleModule: { _ in }
            ),
            skin: skin
        )
        module.frame = CGRect(x: 0, y: 0, width: 490, height: 400)
        module.wireFocusTraversal()

        let controls = module.focusableViews()
        XCTAssertGreaterThan(controls.count, 2)
        XCTAssertEqual(controls.first?.nextKeyView, controls[1])
        XCTAssertEqual(controls.last?.nextKeyView, controls.first)
    }

    func testCollapseFocusesCompactExpandAndExpansionRestoresContentFocus() throws {
        let coordinator = AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore()
        )
        coordinator.showStack()

        let module = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        let slider = try XCTUnwrap(module.content.subviews.compactMap { $0 as? AmpXSlider }.first)
        coordinator.stackWindow?.makeFirstResponder(slider)

        coordinator.setCollapsed(.equalizer, true)
        XCTAssertTrue(module.content.isHidden)
        XCTAssertEqual(coordinator.stackWindow?.firstResponder, module.compactContent?.expandButton)

        coordinator.setCollapsed(.equalizer, false)
        XCTAssertFalse(module.content.isHidden)
        XCTAssertEqual(coordinator.stackWindow?.firstResponder, slider)
    }

    func testCloseModuleTransfersFocusToNextModuleWrappingToPlayer() throws {
        let state = AmpXModuleOrder()
        let coordinator = AmpXHostCoordinator(state: state, skin: ClassicModernSkin(), layoutStore: makeIsolatedLayoutStore())
        coordinator.showStack()

        let equalizer = try XCTUnwrap(coordinator.moduleView(for: .equalizer))
        let playlist = try XCTUnwrap(coordinator.moduleView(for: .playlist))
        coordinator.stackWindow?.makeKeyAndOrderFront(nil)
        coordinator.stackWindow?.makeFirstResponder(equalizer.header)

        coordinator.closeModule(.equalizer)
        XCTAssertEqual(coordinator.focusedModuleID, .playlist)

        coordinator.closeModule(.playlist)
        XCTAssertEqual(coordinator.focusedModuleID, .player)
    }
}

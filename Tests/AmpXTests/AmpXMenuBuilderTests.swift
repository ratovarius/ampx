@testable import AmpX
import XCTest

@MainActor
final class AmpXMenuBuilderTests: XCTestCase {
    private func makeApplication(tracks: [Track] = [], entheaEnabled: Bool = false) -> AmpXApplicationController {
        let player = AudioPlayer(installRemoteCommands: false)
        let manager = PlaylistManager(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        manager.tracks = tracks
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleState(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            audioPlayer: player,
            playlistManager: manager,
            entheaEnabled: entheaEnabled
        )
        return AmpXApplicationController(
            audioPlayer: player,
            playlistManager: manager,
            hosts: hosts
        )
    }

    func testMainMenuHasSingleFileMenuWithCatalogItems() throws {
        let application = self.makeApplication()
        let menu = AmpXMenuBuilder.makeMainMenu(application: application)
        XCTAssertEqual(menu.items.first?.title, ProcessInfo.processInfo.processName)
        XCTAssertEqual(menu.items.filter { $0.title == "File" }.count, 1)

        let file = try XCTUnwrap(menu.item(withTitle: "File")?.submenu)
        file.update()
        XCTAssertEqual(
            file.items.filter { !$0.isSeparatorItem }.map(\.title),
            AmpXMenuCatalog.FileItem.allCases.map(\.rawValue)
        )

        let save = try XCTUnwrap(file.item(withTitle: "Save Playlist…"))
        XCTAssertFalse(save.isEnabled)
        XCTAssertNotNil(save.target)
        XCTAssertNotNil(save.action)
    }

    func testSavePlaylistEnabledWhenTracksPresent() throws {
        let application = self.makeApplication(tracks: [
            Track(title: "One", artist: "Artist", url: URL(fileURLWithPath: "/tmp/one.mp3")),
        ])
        let menu = AmpXMenuBuilder.makeMainMenu(application: application)
        let file = try XCTUnwrap(menu.item(withTitle: "File")?.submenu)
        file.update()
        let save = try XCTUnwrap(file.item(withTitle: "Save Playlist…"))
        XCTAssertTrue(save.isEnabled)
    }

    func testPlaybackMenuMatchesCatalog() throws {
        let application = self.makeApplication()
        let menu = AmpXMenuBuilder.makeMainMenu(application: application)
        let playback = try XCTUnwrap(menu.item(withTitle: "Playback")?.submenu)
        playback.update()
        XCTAssertEqual(
            playback.items.filter { !$0.isSeparatorItem }.map(\.title),
            AmpXMenuCatalog.PlaybackItem.allCases.map(\.rawValue)
        )
    }

    func testViewMenuReflectsModuleVisibility() throws {
        let application = self.makeApplication(entheaEnabled: true)
        let menu = AmpXMenuBuilder.makeMainMenu(application: application)
        let view = try XCTUnwrap(menu.item(withTitle: "View")?.submenu)
        view.update()

        let eq = try XCTUnwrap(view.item(withTitle: AmpXMenuCatalog.ViewPanel.equalizer.rawValue))
        let pl = try XCTUnwrap(view.item(withTitle: AmpXMenuCatalog.ViewPanel.playlist.rawValue))
        let viz = try XCTUnwrap(view.item(withTitle: AmpXMenuCatalog.ViewPanel.visualizer.rawValue))
        XCTAssertEqual(eq.state, .on)
        XCTAssertEqual(pl.state, .on)
        XCTAssertEqual(viz.state, .off)

        application.hosts.closeModule(.equalizer)
        view.update()
        XCTAssertEqual(eq.state, .off)
    }

    func testDisabledEntheaHasNoMenuEntryAndRejectsItsAction() throws {
        let application = self.makeApplication()
        let menu = AmpXMenuBuilder.makeMainMenu(application: application)
        let view = try XCTUnwrap(menu.item(withTitle: "View")?.submenu)
        XCTAssertNil(view.item(withTitle: AmpXMenuCatalog.ViewPanel.visualizer.rawValue))

        let staleItem = NSMenuItem(
            title: "Visualizer",
            action: #selector(AmpXApplicationController.toggleVisualizer(_:)),
            keyEquivalent: ""
        )
        XCTAssertFalse(application.validateMenuItem(staleItem))
        application.toggleVisualizer(nil)
        XCTAssertTrue(application.hosts.state.closed.contains(.enthea))
        XCTAssertNil(application.hosts.moduleView(for: .enthea))
    }

    func testWindowMenuIncludesAmpXReopenAndModuleCommands() throws {
        let application = self.makeApplication()
        let menu = AmpXMenuBuilder.makeMainMenu(application: application)
        let window = try XCTUnwrap(menu.item(withTitle: "Window")?.submenu)
        let titles = window.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertTrue(titles.contains("AmpX"))
        XCTAssertFalse(titles.contains("Move Module Up"))
        XCTAssertFalse(titles.contains("Move Module Down"))
        XCTAssertFalse(titles.contains("Detach/Re-dock Module"))
        XCTAssertTrue(titles.contains("Collapse/Expand Module"))
        XCTAssertTrue(titles.contains("Close"))
        XCTAssertFalse(titles.contains("Close Stack"))
        XCTAssertTrue(titles.contains("Bring All to Front"))
    }

    func testWindowMenuLibraryToggleAndShortcut() throws {
        let application = self.makeApplication()
        let menu = AmpXMenuBuilder.makeMainMenu(application: application)
        let window = try XCTUnwrap(menu.item(withTitle: "Window")?.submenu)
        let library = try XCTUnwrap(window.item(withTitle: AmpXMenuCatalog.ViewPanel.library.rawValue))
        XCTAssertEqual(library.keyEquivalent, "l")
        XCTAssertEqual(library.keyEquivalentModifierMask, .command)
        window.update()
        XCTAssertEqual(library.state, .off)

        application.toggleLibrary(nil)
        window.update()
        XCTAssertEqual(library.state, .on)
        XCTAssertFalse(application.hosts.state.closed.contains(.library))
        XCTAssertNotNil(application.hosts.moduleView(for: .library))

        application.toggleLibrary(nil)
        XCTAssertTrue(application.hosts.state.closed.contains(.library))
        application.hosts.hideAllWindowsForTesting()
    }

    /// ⌘X ⌘C ⌘V ⌘A reach the focused text input (the Library search) through the responder chain.
    func testEditMenuHasStandardTextCommands() throws {
        let menu = AmpXMenuBuilder.makeMainMenu(application: self.makeApplication())
        let edit = try XCTUnwrap(menu.item(withTitle: "Edit")?.submenu)
        let expected: [(String, Selector, String)] = [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSResponder.selectAll(_:)), "a"),
        ]
        for (title, action, key) in expected {
            let item = try XCTUnwrap(edit.item(withTitle: title), title)
            XCTAssertEqual(item.action, action)
            XCTAssertNil(item.target)
            XCTAssertEqual(item.keyEquivalent, key)
            XCTAssertEqual(item.keyEquivalentModifierMask, .command)
        }
    }

    func testFileMenuAddLibraryFolder() throws {
        let application = self.makeApplication()
        let menu = AmpXMenuBuilder.makeMainMenu(application: application)
        let file = try XCTUnwrap(menu.item(withTitle: "File")?.submenu)
        let item = try XCTUnwrap(file.item(withTitle: AmpXMenuCatalog.FileItem.addLibraryFolder.rawValue))
        XCTAssertEqual(item.action, #selector(AmpXApplicationController.addLibraryFolder(_:)))
        XCTAssertTrue(item.target === application)
    }

    func testShuffleAndRepeatReflectPlaylistState() throws {
        let application = self.makeApplication()
        application.playlistManager.shuffleEnabled = true
        application.playlistManager.repeatEnabled = true
        let menu = AmpXMenuBuilder.makeMainMenu(application: application)
        let playback = try XCTUnwrap(menu.item(withTitle: "Playback")?.submenu)
        playback.update()
        let shuffle = try XCTUnwrap(playback.item(withTitle: AmpXMenuCatalog.PlaybackItem.shuffle.rawValue))
        let repeatItem = try XCTUnwrap(playback.item(withTitle: AmpXMenuCatalog.PlaybackItem.repeat.rawValue))
        XCTAssertEqual(shuffle.state, .on)
        XCTAssertEqual(repeatItem.state, .on)
    }

    // MARK: - Automix (DJ mode spec Revision 2 § User-facing settings)

    private func automixMenu(_ application: AmpXApplicationController) throws -> NSMenu {
        let menu = AmpXMenuBuilder.makeMainMenu(application: application)
        let playback = try XCTUnwrap(menu.item(withTitle: "Playback")?.submenu)
        playback.update()
        let options = try XCTUnwrap(playback.item(withTitle: AmpXMenuCatalog.PlaybackItem.automixOptions.rawValue)?.submenu)
        options.update()
        return options
    }

    private func checked(_ menu: NSMenu, _ action: Selector) -> [String] {
        menu.items.filter { $0.action == action && $0.state == .on }.map(\.title)
    }

    func testPlaybackMenuHasAutomixToggleAndOptions() throws {
        let application = self.makeApplication()
        application.automixSettings.settings.enabled = true
        let menu = AmpXMenuBuilder.makeMainMenu(application: application)
        let playback = try XCTUnwrap(menu.item(withTitle: "Playback")?.submenu)
        playback.update()
        let toggle = try XCTUnwrap(playback.item(withTitle: "Automix"))
        XCTAssertEqual(toggle.state, .on)
        XCTAssertNotNil(playback.item(withTitle: "Automix Options")?.submenu)
    }

    func testAutomixOptionsGroupsAndDefaultsChecked() throws {
        let options = try self.automixMenu(self.makeApplication())
        let headers = options.items.filter(\.isSectionHeader).map(\.title)
        XCTAssertEqual(headers, AmpXMenuCatalog.AutomixOption.Group.allCases.map(\.rawValue))
        let app = AmpXApplicationController.self
        XCTAssertEqual(self.checked(options, #selector(app.chooseAutomixMixPoints(_:))), ["Intro / Outro"])
        XCTAssertEqual(self.checked(options, #selector(app.chooseAutomixTransition(_:))), ["Crossfade"])
        XCTAssertEqual(self.checked(options, #selector(app.chooseAutomixLastPhraseBlend(_:))), ["16 Bars"])
        XCTAssertEqual(self.checked(options, #selector(app.chooseAutomixLongestBlend(_:))), ["32 Bars"])
        XCTAssertEqual(self.checked(options, #selector(app.toggleAutomixGlideBack(_:))), [])
        XCTAssertEqual(self.checked(options, #selector(app.chooseAutomixGlideSpeed(_:))), ["0.1 BPM per 4 Bars"])
        XCTAssertEqual(self.checked(options, #selector(app.toggleAutomixContinuation(_:))), [AmpXMenuCatalog.AutomixOption.Toggle.continuation.rawValue])
        XCTAssertEqual(self.checked(options, #selector(app.chooseAutomixPickFrom(_:))), ["Current view"])
    }

    func testChoosingOptionPersists() throws {
        let application = self.makeApplication()
        let options = try self.automixMenu(application)
        let bassSwap = try XCTUnwrap(options.items.first { $0.title == "Bass Swap" })
        application.perform(bassSwap.action, with: bassSwap)
        let longest64 = try XCTUnwrap(options.items.first {
            $0.action == #selector(AmpXApplicationController.chooseAutomixLongestBlend(_:)) && $0.title == "64 Bars"
        })
        application.perform(longest64.action, with: longest64)
        let whole = try XCTUnwrap(options.items.first { $0.title == "Whole library" })
        application.perform(whole.action, with: whole)
        let glide = try XCTUnwrap(options.items.first { $0.title == AmpXMenuCatalog.AutomixOption.Toggle.glideBack.rawValue })
        application.perform(glide.action, with: glide)
        let settings = application.automixSettings.settings
        XCTAssertEqual(settings.transition, .bassSwap)
        XCTAssertEqual(settings.longestBlendBars, 64)
        XCTAssertEqual(settings.pickFrom, .wholeLibrary)
        XCTAssertTrue(settings.glideBack)
        application.toggleAutomix(nil)
        XCTAssertTrue(application.automixSettings.settings.enabled)
    }
}

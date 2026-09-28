@testable import AmpX
import XCTest

/// Library keyboard, menu and launch wiring (Library Module spec § Keyboard, § Start-up and app wiring).
@MainActor
final class LibraryWiringTests: XCTestCase {
    private typealias T = LibraryTestSupport

    private final class FakePanels: LibraryPanelPresenting {
        var folder: URL?
        private(set) var errors: [String] = []

        func chooseFolder(title _: String) async -> URL? {
            self.folder
        }

        func confirmRemove(message _: String, info _: String) async -> Bool {
            true
        }

        func showError(_ message: String) {
            self.errors.append(message)
        }
    }

    private var directory: URL!
    private var storeURL: URL!
    private var flag: FlagSpy!
    private var panels: FakePanels!
    private var audio: MockAudioPlayer!
    private var playlist: PlaylistManager!
    private var controllers: [LibraryController] = []
    private var applications: [AmpXApplicationController] = []

    override func setUp() async throws {
        self.directory = try T.temporaryDirectory(self)
        self.storeURL = self.directory.appendingPathComponent("Store/Library.store")
        self.flag = FlagSpy(log: EventLog())
        self.panels = FakePanels()
        self.audio = MockAudioPlayer()
        self.playlist = PlaylistManager(
            audioPlayer: self.audio, restoreBookmarks: false, restorePlaylist: false,
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: T.isolatedDefaults(self)),
            stateStore: PlaylistStateStore(userDefaults: T.isolatedDefaults(self)), alertPresenter: SilentPlaylistAlertPresenter()
        )
    }

    override func tearDown() async throws {
        for application in self.applications {
            application.hosts.moduleView(for: .library).flatMap { $0.content as? LibraryModuleContent }?.windowDidClose()
            application.hosts.hideAllWindowsForTesting()
        }
        for controller in self.controllers {
            await controller.stop()
        }
    }

    private func makeController() -> LibraryController {
        let scope = ScopeSpy()
        var configuration = LibraryEngineConfiguration(
            startupFlag: self.flag, bookmarkStore: SecurityScopedBookmarkStore(userDefaults: T.isolatedDefaults(self))
        )
        configuration.storeURL = self.storeURL
        configuration.loadMetadata = FakeMetadataLoader().load
        configuration.storeDependencies = { flag in
            var dependencies = LibraryStoreDependencies(startupFlag: flag)
            dependencies.scope = scope.scope
            dependencies.bookmarks = LibraryTestSupport.plainBookmarks
            return dependencies
        }
        let controller = LibraryController(configuration: configuration)
        self.controllers.append(controller)
        return controller
    }

    private func makeApplication(controller: LibraryController?) -> AmpXApplicationController {
        let player = AudioPlayer(installRemoteCommands: false)
        let hosts = AmpXHostCoordinator(
            state: AmpXModuleState(),
            skin: ClassicModernSkin(),
            layoutStore: makeIsolatedLayoutStore(),
            screen: AmpXTestScreen.standard,
            audioPlayer: player,
            playlistManager: self.playlist,
            entheaEnabled: false,
            libraryController: controller,
            libraryPanels: self.panels
        )
        let application = AmpXApplicationController(
            audioPlayer: player,
            playlistManager: self.playlist,
            hosts: hosts,
            libraryController: controller,
            playsStartupSound: false
        )
        self.applications.append(application)
        return application
    }

    /// Opens the Library window and returns its content and window.
    private func openLibrary(_ application: AmpXApplicationController) throws -> (LibraryModuleContent, NSWindow) {
        application.hosts.reopenModule(.library)
        let view = try XCTUnwrap(application.hosts.moduleView(for: .library))
        let content = try XCTUnwrap(view.content as? LibraryModuleContent)
        let window = try XCTUnwrap(view.window)
        content.layoutSubtreeIfNeeded()
        return (content, window)
    }

    private func eventually(_ condition: () -> Bool, timeout: TimeInterval = 5, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "condition not met in \(timeout) s", line: line)
    }

    private func keyDown(_ keyCode: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
    }

    @discardableResult
    private func dispatch(_ event: NSEvent, in window: NSWindow) -> Bool {
        AmpXKeyRouter.dispatch(
            event,
            context: AmpXKeyRouter.focusContext(from: window),
            window: window,
            audioPlayer: nil,
            playlistManager: self.playlist,
            entheaTheater: nil
        )
    }

    private func syntheticModel(titles: [String]) -> LibraryBrowserModel {
        let rows = titles.map { title in
            LibraryRow(
                id: UUID(), rootID: UUID(), url: URL(fileURLWithPath: "/Music/\(title).mp3"),
                title: title, artist: "Artist", album: "", albumArtist: "",
                genre: nil, trackNumber: nil, duration: 60, fileSize: 1, bpm: nil, musicalKey: nil,
                bitrate: 0, bitrateIsDerived: false, codec: "mp3", isAvailable: true, searchKey: title
            )
        }
        let services = LibraryBrowserServices(
            query: { query, generation in query.evaluate(rows: rows, snapshotVersion: 0, generation: generation) },
            rows: { ids in rows.filter { ids.contains($0.id) } },
            versions: { AsyncStream { _ in } },
            progress: { AsyncStream { _ in } },
            roots: { [] }
        )
        return LibraryBrowserModel(services: services, playlist: self.playlist, bookmarkStore: .shared, beep: {})
    }

    // MARK: - Keyboard

    func testSpaceTypesIntoLibrarySearch() throws {
        let application = self.makeApplication(controller: nil)
        let (content, window) = try self.openLibrary(application)
        XCTAssertTrue(window.makeFirstResponder(content.toolbar.search))

        let context = AmpXKeyRouter.focusContext(from: window)
        XCTAssertEqual(context.module, .library)
        XCTAssertTrue(context.textResponderActive)
        let space = self.keyDown(49, " ")
        XCTAssertFalse(self.dispatch(space, in: window))
        window.firstResponder?.keyDown(with: space)
        XCTAssertEqual(content.toolbar.search.committedText, " ")
    }

    func testCommandFFocusesSearch() throws {
        let application = self.makeApplication(controller: nil)
        let (content, window) = try self.openLibrary(application)
        XCTAssertTrue(window.makeFirstResponder(content.table))

        XCTAssertTrue(self.dispatch(self.keyDown(3, "f", flags: .command), in: window))
        XCTAssertTrue(window.firstResponder === content.toolbar.search)
        XCTAssertTrue(self.dispatch(self.keyDown(3, "f", flags: .command), in: window))
        XCTAssertTrue(window.firstResponder === content.toolbar.search)
    }

    func testArrowsReturnAndSelectAllDriveTheTable() async throws {
        let application = self.makeApplication(controller: nil)
        let (content, window) = try self.openLibrary(application)
        content.attach(model: self.syntheticModel(titles: ["A", "B", "C"]))
        await self.eventually { content.table.rows.count == 3 }
        XCTAssertTrue(window.makeFirstResponder(content.table))
        let ids = content.table.rows.map(\.id)

        XCTAssertTrue(self.dispatch(self.keyDown(125), in: window))
        XCTAssertEqual(content.table.selection.focused, ids[0])
        XCTAssertTrue(self.dispatch(self.keyDown(125, flags: .shift), in: window))
        XCTAssertEqual(content.table.selection.ids, Set(ids[0 ... 1]))
        XCTAssertEqual(content.model?.selection, Set(ids[0 ... 1]))
        XCTAssertTrue(self.dispatch(self.keyDown(119), in: window))
        XCTAssertEqual(content.table.selection.ids, [ids[2]])
        XCTAssertTrue(self.dispatch(self.keyDown(115), in: window))
        XCTAssertEqual(content.table.selection.ids, [ids[0]])

        XCTAssertTrue(self.dispatch(self.keyDown(36), in: window))
        await self.eventually { self.playlist.tracks.map(\.title) == ["A"] }
        XCTAssertEqual(self.audio.loadTrackCalls.last?.title, "A")

        XCTAssertTrue(self.dispatch(self.keyDown(0, "a", flags: .command), in: window))
        XCTAssertEqual(content.table.selection.ids, Set(ids))
        XCTAssertTrue(self.dispatch(self.keyDown(36, flags: .command), in: window))
        await self.eventually { self.playlist.tracks.map(\.title) == ["A", "A", "B", "C"] }
    }

    // MARK: - Launch and menus

    func testLaunchWithFlagOffOpensNoContainer() async {
        let controller = self.makeController()
        let application = self.makeApplication(controller: controller)
        application.start()
        await application.libraryStartTask?.value
        XCTAssertNotNil(application.libraryStartTask)
        XCTAssertEqual(controller.state, .notConfigured)
        XCTAssertNil(controller.engine)
        XCTAssertFalse(FileManager.default.fileExists(atPath: self.storeURL.path))
    }

    func testLaunchWithFlagOnOpensEngine() async throws {
        let first = self.makeController()
        let engine = try await first.ensureEngine()
        _ = try await engine.addRoot(url: T.temporaryDirectory(self))
        await first.stop()

        let controller = self.makeController()
        let application = self.makeApplication(controller: controller)
        application.start()
        await application.libraryStartTask?.value
        XCTAssertEqual(controller.state, .ready)
    }

    func testAddLibraryFolderFromMenuOpensEngineAndShowsLibrary() async throws {
        let controller = self.makeController()
        let application = self.makeApplication(controller: controller)
        XCTAssertTrue(application.hosts.state.closed.contains(.library))
        self.panels.folder = try T.temporaryDirectory(self)

        application.addLibraryFolder(nil)
        XCTAssertFalse(application.hosts.state.closed.contains(.library))
        XCTAssertNotNil(application.hosts.moduleView(for: .library))
        await self.eventually { controller.state == .ready }
        let engine = try XCTUnwrap(controller.engine)
        let roots = try await engine.roots()
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(self.panels.errors, [])
    }
}

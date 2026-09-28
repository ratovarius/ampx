@testable import AmpX
import SwiftData
import XCTest

/// Engine lifecycle behind the Library window (Library Module spec § Start-up and app wiring).
@MainActor
final class LibraryControllerTests: XCTestCase {
    private typealias T = LibraryTestSupport

    private var directory: URL!
    private var storeURL: URL!
    private var flag: FlagSpy!
    private var scope: ScopeSpy!
    private var controllers: [LibraryController] = []

    override func setUpWithError() throws {
        self.directory = try T.temporaryDirectory(self)
        self.storeURL = self.directory.appendingPathComponent("Store/Library.store")
        let log = EventLog()
        self.flag = FlagSpy(log: log)
        self.scope = ScopeSpy(log: log)
    }

    override func tearDown() async throws {
        for controller in self.controllers {
            await controller.stop()
        }
    }

    private func makeController() -> LibraryController {
        let scope = self.scope!
        var configuration = LibraryEngineConfiguration(
            startupFlag: self.flag,
            bookmarkStore: SecurityScopedBookmarkStore(userDefaults: T.isolatedDefaults(self))
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

    func testFlagOffStaysNotConfiguredAndOpensNoContainer() async {
        let controller = self.makeController()
        await controller.startIfConfigured()
        XCTAssertEqual(controller.state, .notConfigured)
        XCTAssertNil(controller.engine)
        XCTAssertFalse(FileManager.default.fileExists(atPath: self.storeURL.path))
    }

    func testFlagOnOpensEngine() async throws {
        let first = self.makeController()
        let engine = try await first.ensureEngine()
        _ = try await engine.addRoot(url: T.temporaryDirectory(self))
        await first.stop()

        let controller = self.makeController()
        await controller.startIfConfigured()
        XCTAssertEqual(controller.state, .ready)
        XCTAssertNotNil(controller.engine)
    }

    func testEnsureEngineOpensOnceWhenCalledTwiceConcurrently() async throws {
        let controller = self.makeController()
        async let first = controller.ensureEngine()
        async let second = controller.ensureEngine()
        let engines = try await (first, second)
        XCTAssertTrue(engines.0 === engines.1)
        XCTAssertEqual(controller.state, .ready)
        let again = try await controller.ensureEngine()
        XCTAssertTrue(again === engines.0)
    }

    func testNewerSchemaFailureMessage() async throws {
        try FileManager.default.createDirectory(at: self.storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try LibraryTestSchemaV2.makeContainer(url: self.storeURL)
        self.flag.setHasRoots(true)
        let controller = self.makeController()
        await controller.startIfConfigured()
        XCTAssertEqual(controller.state, .failed("This library was saved by a newer version of AmpX and was left untouched."))
        XCTAssertNil(controller.engine)
    }

    func testMakeBrowserModelOnlyWhenReady() async throws {
        let controller = self.makeController()
        let playlist = PlaylistManager(
            audioPlayer: MockAudioPlayer(), restoreBookmarks: false, restorePlaylist: false,
            stateStore: PlaylistStateStore(userDefaults: T.isolatedDefaults(self)), alertPresenter: SilentPlaylistAlertPresenter()
        )
        XCTAssertNil(controller.makeBrowserModel(playlist: playlist))
        _ = try await controller.ensureEngine()
        let model = try XCTUnwrap(controller.makeBrowserModel(playlist: playlist))
        model.stop()
    }

    func testStopStopsEngine() async throws {
        let controller = self.makeController()
        let engine = try await controller.ensureEngine()
        _ = try await engine.addRoot(url: T.temporaryDirectory(self))
        await engine.waitUntilIdle()
        await controller.stop()
        XCTAssertNil(controller.engine)
        XCTAssertEqual(engine.watcher.activeStreamCount, 0)
        XCTAssertTrue(self.scope.openCounts.isEmpty)
    }

    func testPlaylistSharedUsesSharedBookmarkStore() {
        let store = Mirror(reflecting: PlaylistManager.shared).children.first { $0.label == "bookmarkStore" }?.value
        XCTAssertTrue((store as AnyObject?) === SecurityScopedBookmarkStore.shared)
    }
}

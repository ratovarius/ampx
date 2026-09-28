@testable import AmpX
import AppKit
import XCTest

/// Spec: "Live updates", "Scan scheduling" triggers — FSEvents per root, mount/unmount notifications.
final class LibraryWatcherTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [LibraryWatchEvent] = []
        private var waiters: [(LibraryWatchEvent, XCTestExpectation)] = []

        func record(_ event: LibraryWatchEvent) {
            let matched = self.lock.withLock { () -> [XCTestExpectation] in
                self.storage.append(event)
                return self.waiters.filter { $0.0 == event }.map(\.1)
            }
            matched.forEach { $0.fulfill() }
        }

        func expect(_ event: LibraryWatchEvent, _ expectation: XCTestExpectation) {
            let seen = self.lock.withLock { () -> Bool in
                self.waiters.append((event, expectation))
                return self.storage.contains(event)
            }
            if seen {
                expectation.fulfill()
            }
        }

        func clear() {
            self.lock.withLock { self.storage.removeAll() }
        }

        var events: [LibraryWatchEvent] {
            self.lock.withLock { self.storage }
        }
    }

    private var directory: URL!
    private var recorder: Recorder!
    private var watcher: LibraryWatcher!

    override func setUpWithError() throws {
        self.directory = try LibraryTestSupport.temporaryDirectory(self)
        self.recorder = Recorder()
        let recorder = self.recorder!
        self.watcher = LibraryWatcher(latency: 0.1) { recorder.record($0) }
    }

    override func tearDown() async throws {
        await self.watcher.stop()
    }

    func testRealFileWriteProducesChanged() async throws {
        let id = UUID()
        let root = try self.folder("DJ")
        self.watcher.bind(rootID: id, url: root)
        let changed = self.expectation(description: "changed")
        self.recorder.expect(.changed(id), changed)
        try Data([1]).write(to: root.appendingPathComponent("new.mp3"))
        await self.fulfillment(of: [changed], timeout: 5)
    }

    func testRenamingWatchedRootProducesRootChanged() async throws {
        let id = UUID()
        let root = try self.folder("DJ")
        self.watcher.bind(rootID: id, url: root)
        let rootChanged = self.expectation(description: "rootChanged")
        self.recorder.expect(.rootChanged(id), rootChanged)
        try FileManager.default.moveItem(at: root, to: self.directory.appendingPathComponent("Renamed"))
        await self.fulfillment(of: [rootChanged], timeout: 5)
    }

    func testRebindReleasesOldStreamOnce() throws {
        let id = UUID()
        try self.watcher.bind(rootID: id, url: self.folder("A"))
        try self.watcher.bind(rootID: id, url: self.folder("B"))
        XCTAssertEqual(self.watcher.activeStreamCount, 1)
        XCTAssertEqual(self.watcher.releasedStreamCount, 1)
    }

    func testStoppedBindingIgnoresLateCallbacks() async throws {
        let id = UUID()
        let root = try self.folder("DJ")
        self.watcher.bind(rootID: id, url: root)
        self.watcher.unbind(rootID: id)
        self.recorder.clear()
        let silent = self.expectation(description: "no event after unbind")
        silent.isInverted = true
        self.recorder.expect(.changed(id), silent)
        try Data([1]).write(to: root.appendingPathComponent("late.mp3"))
        await self.fulfillment(of: [silent], timeout: 1)
    }

    func testUnbindAndStopReleaseEverything() async throws {
        try self.watcher.bind(rootID: UUID(), url: self.folder("A"))
        try self.watcher.bind(rootID: UUID(), url: self.folder("B"))
        let third = UUID()
        try self.watcher.bind(rootID: third, url: self.folder("C"))
        self.watcher.unbind(rootID: third)
        XCTAssertEqual(self.watcher.activeStreamCount, 2)
        await self.watcher.stop()
        XCTAssertEqual(self.watcher.activeStreamCount, 0)
        XCTAssertEqual(self.watcher.releasedStreamCount, 3)
    }

    func testSimulatedEventsReachHandler() {
        let volume = URL(fileURLWithPath: "/Volumes/Crate")
        self.watcher.simulate(.mounted(volume))
        self.watcher.simulate(.unmounted(volume))
        XCTAssertEqual(self.recorder.events, [.mounted(volume), .unmounted(volume)])
    }

    @MainActor
    func testVolumeNotificationsStartAndStop() async {
        let volume = URL(fileURLWithPath: "/Volumes/Crate")
        await self.watcher.startVolumeObservation()
        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.didMountNotification, object: nil, userInfo: [NSWorkspace.volumeURLUserInfoKey: volume])
        center.post(name: NSWorkspace.didUnmountNotification, object: nil, userInfo: [NSWorkspace.volumeURLUserInfoKey: volume])
        XCTAssertEqual(self.recorder.events, [.mounted(volume), .unmounted(volume)])

        await self.watcher.stop()
        center.post(name: NSWorkspace.didMountNotification, object: nil, userInfo: [NSWorkspace.volumeURLUserInfoKey: volume])
        XCTAssertEqual(self.recorder.events.count, 2)
    }

    private func folder(_ name: String) throws -> URL {
        let url = self.directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

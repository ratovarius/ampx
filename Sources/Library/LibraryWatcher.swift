import AppKit
import CoreServices
import Foundation

enum LibraryWatchEvent: Sendable, Equatable {
    /// Any FSEvents batch under the root, including MustScanSubDirs / UserDropped / KernelDropped.
    case changed(UUID)
    /// The root itself was renamed, moved or deleted: re-resolve its bookmark.
    case rootChanged(UUID)
    case mounted(URL)
    case unmounted(URL)
}

/// Owns one FSEvents stream per root plus mount/unmount observers (spec: "Live updates"). All stream state lives
/// on `queue`, where FSEvents also delivers callbacks. The handler must not call back into the watcher
/// synchronously; the engine forwards events through a Task.
final class LibraryWatcher: @unchecked Sendable {
    /// Retained once by its stream; `isLive` drops callbacks already queued when the stream is torn down.
    private final class Box: @unchecked Sendable {
        let rootID: UUID
        let handler: @Sendable (LibraryWatchEvent) -> Void
        var isLive = true

        init(rootID: UUID, handler: @escaping @Sendable (LibraryWatchEvent) -> Void) {
            self.rootID = rootID
            self.handler = handler
        }
    }

    private struct Binding {
        let stream: FSEventStreamRef
        let box: Box
    }

    private let latency: TimeInterval
    private let handler: @Sendable (LibraryWatchEvent) -> Void
    private let queue = DispatchQueue(label: "com.ampx.library.watcher", qos: .utility)
    private var bindings: [UUID: Binding] = [:]
    private var released = 0
    private var observers: [NSObjectProtocol] = []

    init(latency: TimeInterval = 2, handler: @escaping @Sendable (LibraryWatchEvent) -> Void) {
        self.latency = latency
        self.handler = handler
    }

    var activeStreamCount: Int {
        self.queue.sync { self.bindings.count }
    }

    /// Test hook: streams torn down so far.
    var releasedStreamCount: Int {
        self.queue.sync { self.released }
    }

    /// Replaces any existing binding for `rootID`.
    func bind(rootID: UUID, url: URL) {
        self.queue.sync {
            self.teardown(rootID)
            let box = Box(rootID: rootID, handler: self.handler)
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passRetained(box).toOpaque(),
                retain: nil,
                release: { info in
                    guard let info else { return }
                    Unmanaged<Box>.fromOpaque(info).release()
                },
                copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, info, count, _, flags, _ in
                guard let info else { return }
                let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
                guard box.isLive else { return }
                let rootChanged = (0 ..< count).contains {
                    flags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
                }
                box.handler(rootChanged ? .rootChanged(box.rootID) : .changed(box.rootID))
            }
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                [url.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                self.latency,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
            ) else {
                Unmanaged<Box>.fromOpaque(context.info!).release()
                return
            }
            FSEventStreamSetDispatchQueue(stream, self.queue)
            FSEventStreamStart(stream)
            self.bindings[rootID] = Binding(stream: stream, box: box)
        }
    }

    func unbind(rootID: UUID) {
        self.queue.sync { self.teardown(rootID) }
    }

    /// Observes volume mount/unmount on the main actor, where NSWorkspace posts them.
    func startVolumeObservation() async {
        await MainActor.run {
            guard self.observers.isEmpty else { return }
            let center = NSWorkspace.shared.notificationCenter
            let handler = self.handler
            self.observers = [
                center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: nil) { note in
                    if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                        handler(.mounted(url))
                    }
                },
                center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: nil) { note in
                    if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                        handler(.unmounted(url))
                    }
                },
            ]
        }
    }

    /// Releases every stream and observer.
    func stop() async {
        self.queue.sync {
            for rootID in Array(self.bindings.keys) {
                self.teardown(rootID)
            }
        }
        await MainActor.run {
            self.observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
            self.observers.removeAll()
        }
    }

    /// Test injection through the same handler real callbacks use.
    func simulate(_ event: LibraryWatchEvent) {
        self.handler(event)
    }

    /// Must run on `queue`.
    private func teardown(_ rootID: UUID) {
        guard let binding = self.bindings.removeValue(forKey: rootID) else { return }
        binding.box.isLive = false
        FSEventStreamStop(binding.stream)
        FSEventStreamInvalidate(binding.stream)
        FSEventStreamRelease(binding.stream) // releases the box's retain
        self.released += 1
    }
}

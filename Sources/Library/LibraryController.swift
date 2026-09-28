import Combine
import Foundation

/// Owns the library engine for the app (Library Module spec § Start-up and app wiring): opens it at launch
/// only when the start-up flag says roots exist, or on the first Add Folder; stops it at quit. Closing the
/// Library window never stops it.
@MainActor
final class LibraryController: ObservableObject {
    enum State: Equatable {
        case notConfigured
        case opening
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .notConfigured
    private(set) var engine: LibraryEngine?

    private let configuration: LibraryEngineConfiguration
    private var opening: Task<LibraryEngine?, Error>?

    init(configuration: LibraryEngineConfiguration) {
        self.configuration = configuration
    }

    var bookmarkStore: SecurityScopedBookmarkStore {
        self.configuration.bookmarkStore
    }

    /// Launch: flag off → `.notConfigured` with no container opened.
    func startIfConfigured() async {
        guard self.engine == nil, self.opening == nil else { return }
        guard self.configuration.startupFlag.hasRoots else {
            self.state = .notConfigured
            return
        }
        let configuration = self.configuration
        _ = try? await self.open { try await LibraryEngine.openIfConfigured(configuration) }
    }

    /// The first Add Folder: opens the engine if needed. Concurrent callers share one open.
    func ensureEngine() async throws -> LibraryEngine {
        if let engine = self.engine {
            return engine
        }
        if let opening = self.opening, let engine = try await opening.value {
            return engine
        }
        let configuration = self.configuration
        guard let engine = try await self.open({ try await LibraryEngine.open(configuration) }) else {
            throw LibraryStoreError.unknownRoot
        }
        return engine
    }

    func makeBrowserModel(playlist: PlaylistManager) -> LibraryBrowserModel? {
        guard let engine = self.engine else { return nil }
        return LibraryBrowserModel(services: .live(engine), playlist: playlist, bookmarkStore: self.bookmarkStore)
    }

    func stop() async {
        _ = try? await self.opening?.value
        let engine = self.engine
        self.engine = nil
        await engine?.stop()
    }

    private func open(_ make: @escaping @Sendable () async throws -> LibraryEngine?) async throws -> LibraryEngine? {
        let task = Task { try await make() }
        self.opening = task
        self.state = .opening
        defer { self.opening = nil }
        do {
            let engine = try await task.value
            self.engine = engine
            self.state = engine == nil ? .notConfigured : .ready
            return engine
        } catch {
            self.state = .failed(Self.message(for: error))
            throw error
        }
    }

    static func message(for error: Error) -> String {
        if case LibraryContainerError.newerSchema = error {
            return "This library was saved by a newer version of AmpX and was left untouched."
        }
        return "The library could not be opened: \(error.localizedDescription)"
    }
}

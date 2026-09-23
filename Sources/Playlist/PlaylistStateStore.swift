import Foundation

struct PersistedPlaylistState: Codable, Equatable {
    var trackPaths: [String]
    var currentIndex: Int
    var shuffleEnabled: Bool
    var repeatEnabled: Bool

    static let empty = PersistedPlaylistState(
        trackPaths: [],
        currentIndex: -1,
        shuffleEnabled: false,
        repeatEnabled: false
    )
}

final class PlaylistStateStore {
    private let stateKey: String
    private let userDefaults: UserDefaults

    init(
        userDefaults: UserDefaults? = nil,
        stateKey: String = "AmpXPlaylistState"
    ) {
        self.userDefaults = userDefaults ?? Self.defaultUserDefaults
        self.stateKey = stateKey
    }

    /// Tests run hosted in the app, so the default store must not share the user's real saved playlist.
    /// `UserDefaults` is documented thread-safe.
    private nonisolated(unsafe) static let defaultUserDefaults: UserDefaults = {
        let isRunningUnderTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        guard isRunningUnderTest else { return .standard }
        let suiteName = "com.ampx.macos.tests.playlist-state"
        UserDefaults().removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName) ?? .standard
    }()

    func loadState() -> PersistedPlaylistState? {
        guard let data = userDefaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(PersistedPlaylistState.self, from: data)
        else {
            return nil
        }
        return state
    }

    func saveState(_ state: PersistedPlaylistState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        self.userDefaults.set(data, forKey: self.stateKey)
    }

    func clearState() {
        self.userDefaults.removeObject(forKey: self.stateKey)
    }
}

import Combine
import Foundation

/// Where a transition's mix points come from (DJ mode spec Revision 2 § Mix points).
enum MixPointMethod: String, Codable, CaseIterable, Sendable {
    case lastPhrase, introOutro
}

enum TransitionStyle: String, Codable, CaseIterable, Sendable {
    case crossfade, bassSwap
}

/// Where the continuation pick comes from when the Playlist runs out.
enum PickPool: String, Codable, CaseIterable, Sendable {
    case wholeLibrary, currentView
}

/// Automix's user-facing settings (DJ mode spec Revision 2 § User-facing settings).
struct AutomixSettings: Codable, Equatable, Sendable {
    static let lastPhraseBlendChoices = [8, 16, 32]
    static let longestBlendChoices = [16, 32, 64]
    static let glideSpeedChoices = [0.05, 0.1, 0.2]

    var enabled = false
    var mixPoints = MixPointMethod.introOutro
    var transition = TransitionStyle.crossfade
    /// Last Phrase blend, in bars.
    var lastPhraseBlendBars = 16
    /// Intro / Outro's longest blend, in bars.
    var longestBlendBars = 32
    var glideBack = false
    /// BPM per 4 bars.
    var glideSpeed = 0.1
    var continueWithMixesWell = true
    var pickFrom = PickPool.currentView
}

/// The settings in `UserDefaults`, plus the Library window's filter as last set, which the continuation pick uses for
/// Current view even while the window is closed.
@MainActor
final class AutomixSettingsStore: ObservableObject {
    static let settingsKey = "AmpX.automixSettings"
    static let pickFilterKey = "AmpX.automixPickFilter"

    private let defaults: UserDefaults

    @Published var settings: AutomixSettings {
        didSet {
            guard self.settings != oldValue else { return }
            self.defaults.set(try? JSONEncoder().encode(self.settings), forKey: Self.settingsKey)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.settings = defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(AutomixSettings.self, from: $0) } ?? AutomixSettings()
    }

    var pickFilter: LibraryQuery? {
        get { self.defaults.data(forKey: Self.pickFilterKey).flatMap { try? JSONDecoder().decode(LibraryQuery.self, from: $0) } }
        set { self.defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.pickFilterKey) }
    }
}

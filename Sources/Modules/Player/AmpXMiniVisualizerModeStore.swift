import Foundation

/// Persists the mini visualizer mode under the key the retired SwiftUI player used, so a choice
/// made in an earlier build carries over.
struct AmpXMiniVisualizerModeStore {
    static let key = "visualizationMode"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> VisualizationMode {
        VisualizationMode.from(storageValue: self.defaults.integer(forKey: Self.key))
    }

    func save(_ mode: VisualizationMode) {
        self.defaults.set(mode.storageValue, forKey: Self.key)
    }
}

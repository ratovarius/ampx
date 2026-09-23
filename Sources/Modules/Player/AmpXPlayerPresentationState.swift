import Combine
import Foundation

/// Discrete presentation choices shared by both retained Player presentations.
@MainActor
final class AmpXPlayerPresentationState: ObservableObject {
    @Published private(set) var visualizerSettings: AmpXMiniVisualizerSettings
    @Published private(set) var showRemainingTime = false
    private let store: AmpXMiniVisualizerSettingsStore

    init(store: AmpXMiniVisualizerSettingsStore = .init()) {
        self.store = store
        self.visualizerSettings = store.load()
    }

    func setVisualizerSettings(_ value: AmpXMiniVisualizerSettings) {
        guard value != self.visualizerSettings else { return }
        self.visualizerSettings = value
        self.store.save(value)
    }

    func setRemainingTime(_ value: Bool) {
        guard value != self.showRemainingTime else { return }
        self.showRemainingTime = value
    }

    func toggleTimeMode() {
        self.setRemainingTime(!self.showRemainingTime)
    }
}

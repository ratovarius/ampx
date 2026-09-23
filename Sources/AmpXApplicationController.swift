import AppKit
import Foundation

@MainActor
final class AmpXApplicationController: NSObject, NSMenuItemValidation {
    let audioPlayer: AudioPlayer
    let playlistManager: PlaylistManager
    let hosts: AmpXHostCoordinator

    private let playsStartupSound: Bool
    private var playbackCoordinationBound = false

    init(
        audioPlayer: AudioPlayer,
        playlistManager: PlaylistManager,
        hosts: AmpXHostCoordinator,
        playsStartupSound: Bool? = nil
    ) {
        self.audioPlayer = audioPlayer
        self.playlistManager = playlistManager
        self.hosts = hosts
        self.playsStartupSound = playsStartupSound ?? !Self.isRunningUnderTest
        super.init()
    }

    func start() {
        self.bindPlaybackCoordinationIfNeeded()
        self.loadStartupSoundIfNeeded()
        self.wirePlayerMenuButton()
        self.hosts.showStack()
    }

    func terminate() {
        self.hosts.flushLayoutPersistence()
        self.hosts.theaterController.handleApplicationTermination()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(self.savePlaylist(_:)):
            return !self.playlistManager.tracks.isEmpty
        case #selector(self.toggleShuffle(_:)):
            menuItem.state = self.playlistManager.shuffleEnabled ? .on : .off
            return true
        case #selector(self.toggleRepeat(_:)):
            menuItem.state = self.playlistManager.repeatEnabled ? .on : .off
            return true
        case #selector(self.toggleEqualizer(_:)):
            menuItem.state = self.hosts.state.closed.contains(.equalizer) ? .off : .on
            return true
        case #selector(self.togglePlaylist(_:)):
            menuItem.state = self.hosts.state.closed.contains(.playlist) ? .off : .on
            return true
        case #selector(self.toggleVisualizer(_:)):
            menuItem.state = self.hosts.state.closed.contains(.enthea) ? .off : .on
            return self.hosts.isEntheaEnabled
        case #selector(self.moveModuleUp(_:)), #selector(self.moveModuleDown(_:)):
            return self.hosts.focusedModuleID != .player
        case #selector(self.toggleDetachModule(_:)):
            return self.hosts.focusedModuleID != .player
        case #selector(self.toggleCollapseModule(_:)):
            return true
        case #selector(self.closeStack(_:)):
            return self.hosts.isStackVisible
        default:
            return true
        }
    }

    // MARK: - File

    @objc func addFiles(_: Any?) {
        self.playlistManager.showFilePicker()
    }

    @objc func addFolder(_: Any?) {
        self.playlistManager.showFolderPicker()
    }

    @objc func loadPlaylist(_: Any?) {
        self.playlistManager.showLoadM3UPicker()
    }

    @objc func savePlaylist(_: Any?) {
        self.playlistManager.saveM3UPlaylist()
    }

    // MARK: - Playback

    @objc func togglePlayPause(_: Any?) {
        self.audioPlayer.togglePlayPause()
    }

    @objc func play(_: Any?) {
        self.audioPlayer.playOrRestart()
    }

    @objc func pause(_: Any?) {
        self.audioPlayer.pause()
    }

    @objc func stopPlayback(_: Any?) {
        self.audioPlayer.stop()
    }

    @objc func previousTrack(_: Any?) {
        self.playlistManager.previous()
    }

    @objc func nextTrack(_: Any?) {
        self.playlistManager.next()
    }

    @objc func toggleShuffle(_: Any?) {
        self.playlistManager.shuffleEnabled.toggle()
    }

    @objc func toggleRepeat(_: Any?) {
        self.playlistManager.repeatEnabled.toggle()
    }

    // MARK: - View

    @objc func toggleEqualizer(_: Any?) {
        self.toggleModule(.equalizer)
    }

    @objc func togglePlaylist(_: Any?) {
        self.toggleModule(.playlist)
    }

    @objc func toggleVisualizer(_: Any?) {
        self.toggleModule(.enthea)
    }

    // MARK: - Window

    @objc func showAmpX(_: Any?) {
        self.hosts.showStack()
    }

    @objc func moveModuleUp(_: Any?) {
        self.hosts.performModuleCommand(.moveUp)
    }

    @objc func moveModuleDown(_: Any?) {
        self.hosts.performModuleCommand(.moveDown)
    }

    @objc func toggleDetachModule(_: Any?) {
        self.hosts.performModuleCommand(.toggleDetach)
    }

    @objc func toggleCollapseModule(_: Any?) {
        self.hosts.performModuleCommand(.toggleCollapse)
    }

    @objc func closeStack(_: Any?) {
        self.hosts.closeStack()
    }

    @objc func popUpPlayerMenu(from sender: Any?) {
        guard let button = sender as? NSView else { return }
        let menu = AmpXMenuBuilder.makePlayerMenu(application: self)
        let point = NSPoint(x: 0, y: button.bounds.height)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    private func bindPlaybackCoordinationIfNeeded() {
        guard !self.playbackCoordinationBound else { return }
        self.playbackCoordinationBound = true

        self.audioPlayer.onTrackFinished = { [weak playlistManager] in
            playlistManager?.advanceAfterTrackFinished()
        }
        self.audioPlayer.onNextTrackRequested = { [weak playlistManager] in
            playlistManager?.next()
        }
        self.audioPlayer.onPreviousTrackRequested = { [weak playlistManager] in
            playlistManager?.previous()
        }
    }

    private func loadStartupSoundIfNeeded() {
        guard self.playsStartupSound else { return }
        guard self.playlistManager.shouldPlayStartupSoundOnLaunch else { return }
        guard let startupURL = Bundle.main.url(forResource: "startup", withExtension: "mp3") else {
            return
        }

        Task { @MainActor in
            let startupTrack = await Track.load(from: startupURL)
            try? await Task.sleep(nanoseconds: 200_000_000)
            self.audioPlayer.loadTrack(startupTrack) { success in
                if success {
                    self.audioPlayer.play()
                }
            }
        }
    }

    private func wirePlayerMenuButton() {
        guard let playerContent = hosts.moduleView(for: .player)?.content as? PlayerModuleContent else {
            return
        }
        playerContent.menuAction = { [weak self] button in
            self?.popUpPlayerMenu(from: button)
        }
    }

    private func toggleModule(_ id: AmpXModuleID) {
        if self.hosts.state.closed.contains(id) {
            self.hosts.reopenModule(id)
        } else {
            self.hosts.closeModule(id)
        }
    }

    private static var isRunningUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}

#if DEBUG
extension AmpXApplicationController {
    var isPlaybackCoordinationBound: Bool {
        self.playbackCoordinationBound
    }
}
#endif

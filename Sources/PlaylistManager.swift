import AppKit
import Combine
import Foundation
import os

private let playlistLogger = Logger(subsystem: "com.ampx.macos", category: "Playlist")

@MainActor
class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()

    @Published var tracks: [Track] = []
    @Published var currentIndex: Int = -1
    @Published var shuffleEnabled: Bool = false {
        didSet {
            if self.shuffleEnabled {
                self.generateShuffledIndices()
            } else {
                self.shuffledIndices.removeAll()
                self.shuffleCurrentIndex = 0
            }
            if !self.isRestoringState {
                self.persistState()
            }
        }
    }

    @Published var repeatEnabled: Bool = false {
        didSet {
            if !self.isRestoringState {
                self.persistState()
            }
        }
    }

    @Published private(set) var lastSaveErrorMessage: String?

    private var playRequestGeneration = 0
    private var isRestoringState = false

    // Shuffle management
    private var shuffledIndices: [Int] = []
    private var shuffleCurrentIndex: Int = 0

    private let audioPlayer: AudioPlaybackControlling
    private let bookmarkStore: SecurityScopedBookmarkStore
    private let fileService: PlaylistFileService
    private let stateStore: PlaylistStateStore
    private let alertPresenter: PlaylistAlertPresenting

    init(
        audioPlayer: AudioPlaybackControlling = AudioPlayer.shared,
        restoreBookmarks: Bool = true,
        restorePlaylist: Bool = true,
        bookmarkStore: SecurityScopedBookmarkStore? = nil,
        stateStore: PlaylistStateStore? = nil,
        alertPresenter: PlaylistAlertPresenting? = nil
    ) {
        self.audioPlayer = audioPlayer
        let store = bookmarkStore ?? SecurityScopedBookmarkStore()
        self.bookmarkStore = store
        self.fileService = PlaylistFileService(bookmarkStore: store)
        self.stateStore = stateStore ?? PlaylistStateStore()
        self.alertPresenter = alertPresenter ?? AppKitPlaylistAlertPresenter()
        if restoreBookmarks {
            store.restore()
        }
        if restorePlaylist {
            self.restorePersistedState()
        }
    }

    deinit {
        bookmarkStore.releaseAll()
    }

    var currentTrack: Track? {
        guard self.currentIndex >= 0, self.currentIndex < self.tracks.count else { return nil }
        return self.tracks[self.currentIndex]
    }

    /// Startup chime plays only on a fresh launch with no restored playlist.
    var shouldPlayStartupSoundOnLaunch: Bool {
        self.tracks.isEmpty
    }

    func addTrack(_ track: Track) {
        self.tracks.append(track)
        self.persistState()
    }

    func addTracks(_ newTracks: [Track]) {
        self.tracks.append(contentsOf: newTracks)
        self.persistState()

        if self.shuffleEnabled {
            self.generateShuffledIndices()
        }
    }

    func removeTrack(at index: Int) {
        guard index >= 0, index < self.tracks.count else { return }
        self.tracks.remove(at: index)

        // Regenerate shuffle order if shuffle is enabled
        if self.shuffleEnabled {
            self.generateShuffledIndices()
        }

        if self.tracks.isEmpty {
            self.currentIndex = -1
            self.audioPlayer.stop()
        } else if index == self.currentIndex {
            // Removed current track — play what is now at this index (former next track)
            self.currentIndex = min(index, self.tracks.count - 1)
            self.playTrack(at: self.currentIndex)
        } else if index < self.currentIndex {
            self.currentIndex -= 1
        }
        self.persistState()
    }

    func presentTrackInfo(at index: Int) {
        guard index >= 0, index < self.tracks.count else { return }
        let track = self.tracks[index]
        guard let url = track.url else { return }

        _ = self.bookmarkStore.ensureAccess(for: url)

        let alert = NSAlert()
        alert.messageText = "\(track.artist) — \(track.title)"
        alert.informativeText = TrackInfoFormatter.summary(for: track)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @discardableResult
    func removeTrackFromDisk(at index: Int, confirm: ((URL) -> Bool)? = nil) -> Bool {
        guard index >= 0, index < self.tracks.count else { return false }
        let track = self.tracks[index]
        guard let url = track.url else { return false }

        guard self.bookmarkStore.ensureAccess(for: url) else {
            self.showFileActionError(
                title: "Cannot Remove File",
                message: "AmpX does not have permission to modify this file. Re-add it from its folder to grant access."
            )
            return false
        }

        let shouldTrash = confirm?(url) ?? Self.confirmTrash(for: url)
        guard shouldTrash else { return false }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            self.removeTrack(at: index)
            return true
        } catch {
            playlistLogger.error("Failed to trash \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            self.showFileActionError(
                title: "Could Not Move to Trash",
                message: error.localizedDescription
            )
            return false
        }
    }

    private static func confirmTrash(for url: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Move to Trash?"
        alert.informativeText = "“\(url.lastPathComponent)” will be moved to the Trash and removed from the playlist."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showFileActionError(title: String, message: String) {
        self.alertPresenter.presentError(title: title, message: message)
    }

    /// Empties the list but, like Winamp, lets the current track keep playing to its end.
    func clearPlaylist() {
        self.tracks.removeAll()
        self.currentIndex = -1
        self.shuffledIndices.removeAll()
        self.shuffleCurrentIndex = 0
        self.persistState()
    }

    func playTrack(at index: Int) {
        guard index >= 0, index < self.tracks.count else { return }

        self.playRequestGeneration += 1
        let requestId = self.playRequestGeneration
        let previousIndex = self.currentIndex
        self.currentIndex = index
        let track = self.tracks[index]
        self.persistState()

        self.audioPlayer.loadTrack(track) { [weak self] success in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard requestId == self.playRequestGeneration else { return }
                if success {
                    if self.shuffleEnabled {
                        if let shufflePos = self.shuffledIndices.firstIndex(of: index) {
                            self.shuffleCurrentIndex = shufflePos
                        } else {
                            self.generateShuffledIndices()
                        }
                    }
                    self.audioPlayer.play()
                } else {
                    self.currentIndex = previousIndex
                    self.persistState()
                }
            }
        }
    }

    func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < self.tracks.count,
              destinationIndex >= 0, destinationIndex < self.tracks.count
        else {
            return
        }

        let track = self.tracks.remove(at: sourceIndex)
        self.tracks.insert(track, at: destinationIndex)

        if self.currentIndex == sourceIndex {
            self.currentIndex = destinationIndex
        } else if sourceIndex < self.currentIndex, destinationIndex >= self.currentIndex {
            self.currentIndex -= 1
        } else if sourceIndex > self.currentIndex, destinationIndex <= self.currentIndex {
            self.currentIndex += 1
        }

        if self.shuffleEnabled {
            self.generateShuffledIndices()
        }
        self.persistState()
    }

    /// Remove multiple rows (highest-index-first safe). Remaps `currentIndex` by track id.
    func removeTracks(at indices: IndexSet) {
        guard !indices.isEmpty else { return }
        let currentID = self.currentTrack?.id
        let removingCurrent = self.currentIndex >= 0 && indices.contains(self.currentIndex)
        let fallbackIndex = indices.min() ?? 0

        self.tracks = self.tracks.enumerated().compactMap { indices.contains($0.offset) ? nil : $0.element }

        if self.shuffleEnabled {
            self.generateShuffledIndices()
        }

        if self.tracks.isEmpty {
            self.currentIndex = -1
            self.audioPlayer.stop()
        } else if let currentID, let idx = self.tracks.firstIndex(where: { $0.id == currentID }) {
            self.currentIndex = idx
        } else if removingCurrent {
            self.currentIndex = min(fallbackIndex, self.tracks.count - 1)
            self.playTrack(at: self.currentIndex)
            return
        } else {
            self.currentIndex = -1
        }
        self.persistState()
    }

    /// Keep only the given indices (AmpX crop).
    func cropToTracks(at indices: IndexSet) {
        guard !indices.isEmpty else { return }
        let remove = IndexSet(integersIn: 0 ..< self.tracks.count).subtracting(indices)
        self.removeTracks(at: remove)
    }

    /// Move all selected tracks as an ordered block by one row (`delta` = −1 or +1).
    func moveSelectedTracks(indices: IndexSet, by delta: Int) {
        guard delta == -1 || delta == 1, !indices.isEmpty else { return }
        let sorted = indices.sorted()
        let selectedTracks = sorted.map { self.tracks[$0] }
        let currentID = self.currentTrack?.id

        let remaining = self.tracks.enumerated().compactMap { indices.contains($0.offset) ? nil : $0.element }
        let nonSelectedBefore = self.tracks[..<sorted[0]].indices.filter { !indices.contains($0) }.count
        let insertAt = min(max(nonSelectedBefore + delta, 0), remaining.count)

        var rebuilt = remaining
        rebuilt.insert(contentsOf: selectedTracks, at: insertAt)
        self.tracks = rebuilt

        if let currentID {
            self.currentIndex = self.tracks.firstIndex(where: { $0.id == currentID }) ?? -1
        }
        if self.shuffleEnabled {
            self.generateShuffledIndices()
        }
        self.persistState()
    }

    enum TrackSortKey {
        case title
        case fileName
        case path
    }

    func sortTracks(by key: TrackSortKey) {
        let currentID = self.currentTrack?.id
        self.tracks.sort { lhs, rhs in
            let left: String
            let right: String
            switch key {
            case .title:
                left = "\(lhs.artist) - \(lhs.title)"
                right = "\(rhs.artist) - \(rhs.title)"
            case .fileName:
                left = lhs.url?.lastPathComponent ?? lhs.title
                right = rhs.url?.lastPathComponent ?? rhs.title
            case .path:
                left = lhs.url?.path ?? lhs.title
                right = rhs.url?.path ?? rhs.title
            }
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
        self.remapCurrentIndex(preserving: currentID)
    }

    func reverseTracks() {
        let currentID = self.currentTrack?.id
        self.tracks.reverse()
        self.remapCurrentIndex(preserving: currentID)
    }

    func randomizeTracks() {
        let currentID = self.currentTrack?.id
        self.tracks.shuffle()
        self.remapCurrentIndex(preserving: currentID)
    }

    private func remapCurrentIndex(preserving currentID: UUID?) {
        if let currentID, let idx = self.tracks.firstIndex(where: { $0.id == currentID }) {
            self.currentIndex = idx
        } else if self.tracks.isEmpty {
            self.currentIndex = -1
        }
        if self.shuffleEnabled {
            self.generateShuffledIndices()
        }
        self.persistState()
    }

    /// User-requested next track. Like Winamp, a manual skip past the end wraps to the
    /// start (or a fresh shuffle order) instead of stopping; only auto-advance honors repeat.
    func next() {
        self.advance(forward: true, wrap: true)
    }

    func previous() {
        self.advance(forward: false, wrap: self.repeatEnabled)
    }

    /// Auto-advance when the current track plays to the end; stops after the last track
    /// unless repeat is on.
    func advanceAfterTrackFinished() {
        self.advance(forward: true, wrap: self.repeatEnabled)
    }

    private func advance(forward: Bool, wrap: Bool) {
        guard !self.tracks.isEmpty else { return }

        if self.shuffleEnabled {
            self.advanceShuffle(forward: forward, wrap: wrap)
        } else {
            self.advanceSequential(forward: forward, wrap: wrap)
        }
    }

    private func advanceShuffle(forward: Bool, wrap: Bool) {
        if self.shuffledIndices.isEmpty {
            self.generateShuffledIndices()
            self.shuffleCurrentIndex = 0
        }

        if forward {
            self.shuffleCurrentIndex += 1

            if self.shuffleCurrentIndex >= self.shuffledIndices.count {
                if wrap {
                    self.generateShuffledIndices()
                    self.shuffleCurrentIndex = 1

                    if self.shuffledIndices.count <= 1 {
                        self.shuffleCurrentIndex = 0
                    }
                } else {
                    self.audioPlayer.stop()
                    return
                }
            }
        } else {
            self.shuffleCurrentIndex -= 1

            if self.shuffleCurrentIndex < 0 {
                if wrap {
                    self.shuffleCurrentIndex = self.shuffledIndices.count - 1
                } else {
                    self.shuffleCurrentIndex = 0
                    return
                }
            }
        }

        let targetIndex = self.shuffledIndices[self.shuffleCurrentIndex]
        self.playTrack(at: targetIndex)
    }

    private func advanceSequential(forward: Bool, wrap: Bool) {
        if forward {
            let nextIndex = self.currentIndex + 1

            if nextIndex >= self.tracks.count {
                if wrap {
                    self.playTrack(at: 0)
                } else {
                    self.audioPlayer.stop()
                }
            } else {
                self.playTrack(at: nextIndex)
            }
        } else {
            let prevIndex = self.currentIndex > 0 ? self.currentIndex - 1 : (wrap ? self.tracks.count - 1 : 0)
            self.playTrack(at: prevIndex)
        }
    }

    private func generateShuffledIndices() {
        // Generate a shuffled list of indices, ensuring current track is first
        var indices = Array(0 ..< self.tracks.count)

        // Remove current index from the list
        if self.currentIndex >= 0, self.currentIndex < indices.count {
            indices.remove(at: self.currentIndex)
        }

        // Shuffle the remaining indices
        indices.shuffle()

        // Put current index at the beginning
        if self.currentIndex >= 0, self.currentIndex < self.tracks.count {
            self.shuffledIndices = [self.currentIndex] + indices
        } else {
            self.shuffledIndices = indices
        }

        // Don't reset shuffleCurrentIndex here - let the caller manage it
        // This allows us to set it appropriately when regenerating for repeat
    }

    func test_setShuffledIndices(_ indices: [Int], position: Int) {
        self.shuffledIndices = indices
        self.shuffleCurrentIndex = position
    }

    var test_shuffledIndices: [Int] {
        self.shuffledIndices
    }

    var test_shuffleCurrentIndex: Int {
        self.shuffleCurrentIndex
    }

    var test_playRequestGeneration: Int {
        self.playRequestGeneration
    }

    var test_bookmarkStore: SecurityScopedBookmarkStore {
        self.bookmarkStore
    }

    var test_stateStore: PlaylistStateStore {
        self.stateStore
    }

    func persistStateForTests() {
        self.persistState()
    }

    private func persistState() {
        let paths = self.tracks.compactMap { $0.url?.standardizedFileURL.path }
        self.stateStore.saveState(
            PersistedPlaylistState(
                trackPaths: paths,
                currentIndex: self.currentIndex,
                shuffleEnabled: self.shuffleEnabled,
                repeatEnabled: self.repeatEnabled
            )
        )
    }

    private func restorePersistedState() {
        guard let state = self.stateStore.loadState(), !state.trackPaths.isEmpty else { return }

        self.isRestoringState = true
        let paths = state.trackPaths
        let savedIndex = state.currentIndex
        let savedShuffle = state.shuffleEnabled
        let savedRepeat = state.repeatEnabled

        Task.detached(priority: .userInitiated) { [bookmarkStore] in
            var restoredTracks: [Track] = []
            var accessDeniedPaths: [String] = []
            var missingPaths: [String] = []

            for path in paths {
                let url = URL(fileURLWithPath: path)
                guard bookmarkStore.ensureAccess(for: url) else {
                    accessDeniedPaths.append(path)
                    playlistLogger.warning("Skipped restore (no access): \(path, privacy: .public)")
                    continue
                }
                guard FileManager.default.fileExists(atPath: url.path) else {
                    missingPaths.append(path)
                    playlistLogger.warning("Skipped restore (missing file): \(path, privacy: .public)")
                    continue
                }
                await restoredTracks.append(Track.load(from: url))
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                defer { self.isRestoringState = false }

                if restoredTracks.isEmpty {
                    // Do not persist an empty playlist — a transient permission failure would
                    // otherwise wipe the saved track list on the next launch.
                    self.currentIndex = -1
                    if !accessDeniedPaths.isEmpty {
                        playlistLogger.error(
                            "Playlist restore loaded 0/\(paths.count) tracks (\(accessDeniedPaths.count) permission, \(missingPaths.count) missing)"
                        )
                    }
                    return
                }

                self.tracks = restoredTracks
                self.repeatEnabled = savedRepeat
                self.currentIndex = min(max(savedIndex, 0), restoredTracks.count - 1)
                self.shuffleEnabled = savedShuffle

                // Keep paths that only failed permission so a later launch can retry; drop
                // confirmed-missing files from the saved list.
                if !accessDeniedPaths.isEmpty {
                    let loadedPaths = restoredTracks.compactMap { $0.url?.standardizedFileURL.path }
                    self.stateStore.saveState(
                        PersistedPlaylistState(
                            trackPaths: loadedPaths + accessDeniedPaths,
                            currentIndex: self.currentIndex,
                            shuffleEnabled: self.shuffleEnabled,
                            repeatEnabled: self.repeatEnabled
                        )
                    )
                } else {
                    self.persistState()
                }

                let track = restoredTracks[self.currentIndex]
                self.audioPlayer.loadTrack(track, completion: nil)
            }
        }
    }

    func acknowledgeSaveError() {
        self.lastSaveErrorMessage = nil
    }

    private func m3uPlaylistContent(relativeTo playlistFile: URL) -> String {
        var content = "#EXTM3U\n"
        for track in self.tracks {
            if let trackUrl = track.url {
                content += self.m3uEntry(for: trackUrl, relativeTo: playlistFile) + "\n"
            }
        }
        return content
    }

    private func m3uEntry(for trackURL: URL, relativeTo playlistFile: URL) -> String {
        let playlistDirectory = playlistFile.deletingLastPathComponent().standardizedFileURL
        let normalizedTrack = trackURL.standardizedFileURL
        let directoryPrefix = playlistDirectory.path + "/"
        let trackPath = normalizedTrack.path
        if trackPath.hasPrefix(directoryPrefix) {
            return String(trackPath.dropFirst(directoryPrefix.count))
        }
        return trackPath
    }

    private func saveM3UPlaylist(to url: URL) {
        do {
            try self.m3uPlaylistContent(relativeTo: url).write(to: url, atomically: true, encoding: .utf8)
            self.lastSaveErrorMessage = nil
        } catch {
            playlistLogger.error("Failed to save M3U playlist: \(error.localizedDescription, privacy: .public)")
            let message = "Could not save playlist. Check the folder permissions and try again."
            self.lastSaveErrorMessage = message
            self.showFileActionError(title: "Could Not Save Playlist", message: message)
        }
    }

    func testing_saveM3UPlaylist(to url: URL) {
        self.saveM3UPlaylist(to: url)
    }

    func testing_m3uEntry(for trackURL: URL, relativeTo playlistFile: URL) -> String {
        self.m3uEntry(for: trackURL, relativeTo: playlistFile)
    }

    func importDroppedURL(_ url: URL) {
        let ext = url.pathExtension

        if M3UParser.isM3UExtension(ext) {
            self.fileService.bookmarkM3UResources(for: url)
            self.importTracksInBackground { [fileService] in
                await fileService.loadM3UPlaylist(from: url)
            }
            return
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            self.bookmarkStore.saveBookmark(for: url)
            self.addTracksFromFolder(url)
            return
        }

        guard M3UParser.isSupportedAudioExtension(ext) else { return }
        self.bookmarkStore.saveBookmark(for: url)
        self.addTrackFromURL(url)
    }

    private func addTrackFromURL(_ url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let track = await Track.load(from: url)
            await MainActor.run {
                self?.addTrack(track)
            }
        }
    }

    func showFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.mp3, .wav, .init(filenameExtension: "flac"), .init(filenameExtension: "m3u")].compactMap { $0 }

        panel.begin { [weak self] response in
            guard let self, response == .OK else { return }
            self.importPickedURLs(panel.urls)
        }
    }

    private func importPickedURLs(_ urls: [URL]) {
        for url in urls {
            if M3UParser.isM3UExtension(url.pathExtension) {
                self.fileService.bookmarkM3UResources(for: url)
            } else {
                self.bookmarkStore.saveBookmark(for: url)
            }
        }

        let fileService = self.fileService
        Task.detached(priority: .userInitiated) { [weak self] in
            var newTracks: [Track] = []
            for url in urls {
                if M3UParser.isM3UExtension(url.pathExtension) {
                    if let m3uTracks = await fileService.loadM3UPlaylist(from: url) {
                        newTracks.append(contentsOf: m3uTracks)
                    }
                } else {
                    await newTracks.append(Track.load(from: url))
                }
            }
            await MainActor.run {
                self?.addTracks(newTracks)
            }
        }
    }

    func loadM3UPlaylist(from url: URL) async -> [Track]? {
        await self.fileService.loadM3UPlaylist(from: url)
    }

    func saveM3UPlaylist() {
        guard !self.tracks.isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")].compactMap { $0 }
        panel.nameFieldStringValue = "playlist.m3u"
        panel.title = "Save Playlist As"
        panel.message = "Choose a name and location for your playlist"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.showsTagField = false

        let response = panel.runModal()

        if response == .OK, let url = panel.url {
            self.saveM3UPlaylist(to: url)
        }
    }

    func showLoadM3UPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")].compactMap { $0 }
        panel.title = "Load Playlist"
        panel.message = "Choose an M3U playlist to load"

        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self.replacePlaylist(fromM3U: url)
            }
        }
    }

    func replacePlaylist(fromM3U url: URL) async {
        self.fileService.bookmarkM3UResources(for: url)
        let loaded = await self.fileService.loadM3UPlaylist(from: url) ?? []
        self.clearPlaylist()
        if !loaded.isEmpty {
            self.addTracks(loaded)
        }
    }

    func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.bookmarkStore.saveBookmark(for: url)
                self?.addTracksFromFolder(url)
            }
        }
    }

    private func addTracksFromFolder(_ folder: URL) {
        self.importTracksInBackground { [fileService] in
            let fileURLs = fileService.collectAudioFiles(in: folder)
            var tracks: [Track] = []
            for url in fileURLs {
                await tracks.append(Track.load(from: url))
            }
            return tracks
        }
    }

    private func importTracksInBackground(_ loadTracks: @escaping @Sendable () async -> [Track]?) {
        Task.detached(priority: .userInitiated) {
            guard let tracks = await loadTracks(), !tracks.isEmpty else { return }
            await MainActor.run { [weak self] in
                self?.addTracks(tracks)
            }
        }
    }
}

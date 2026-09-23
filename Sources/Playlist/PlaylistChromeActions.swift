import AppKit
import Foundation

/// Classic pledit chrome menu commands (ADD/REM/SEL/MISC/LIST) shared by the UI.
@MainActor
enum PlaylistChromeActions {
    static func selectedIndices(tracks: [Track], selection: PlaylistSelectionModel) -> IndexSet {
        var indices = IndexSet()
        for (index, track) in tracks.enumerated() where selection.selectedIDs.contains(track.id) {
            indices.insert(index)
        }
        return indices
    }

    static func removeSelected(manager: PlaylistManager, selection: inout PlaylistSelectionModel) {
        let indices = self.selectedIndices(tracks: manager.tracks, selection: selection)
        guard !indices.isEmpty else { return }
        manager.removeTracks(at: indices)
        selection.prune(toValidIDs: Set(manager.tracks.map(\.id)))
    }

    static func cropToSelected(manager: PlaylistManager, selection: inout PlaylistSelectionModel) {
        let indices = self.selectedIndices(tracks: manager.tracks, selection: selection)
        guard !indices.isEmpty else { return }
        manager.cropToTracks(at: indices)
        selection.prune(toValidIDs: Set(manager.tracks.map(\.id)))
    }

    static func clearList(manager: PlaylistManager, selection: inout PlaylistSelectionModel) {
        manager.clearPlaylist()
        selection = PlaylistSelectionModel()
    }

    static func selectAll(tracks: [Track], selection: inout PlaylistSelectionModel) {
        selection.selectAll(orderedIDs: tracks.map(\.id))
    }

    static func selectNone(selection: inout PlaylistSelectionModel) {
        selection = PlaylistSelectionModel()
    }

    static func invertSelection(tracks: [Track], selection: inout PlaylistSelectionModel) {
        selection.invert(orderedIDs: tracks.map(\.id))
    }

    static func fileInfoIndex(
        tracks: [Track],
        selection: PlaylistSelectionModel,
        currentIndex: Int
    ) -> Int? {
        if let index = tracks.indices.first(where: { selection.selectedIDs.contains(tracks[$0].id) }) {
            return index
        }
        guard currentIndex >= 0, currentIndex < tracks.count else { return nil }
        return currentIndex
    }

    static func presentFileInfo(manager: PlaylistManager, selection: PlaylistSelectionModel) {
        guard let index = self.fileInfoIndex(
            tracks: manager.tracks,
            selection: selection,
            currentIndex: manager.currentIndex
        ) else { return }
        manager.presentTrackInfo(at: index)
    }
}

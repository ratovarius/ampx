import Foundation

@MainActor
final class PlaylistKeyboardAdapter: AmpXPlaylistKeyboard.Handling {
    private let manager: PlaylistManager

    var selection = PlaylistSelectionModel()
    var onSelectionChanged: (() -> Void)?
    var onRevealCursor: (() -> Void)?

    init(manager: PlaylistManager) {
        self.manager = manager
    }

    func moveSelection(by offset: Int, extend: Bool) {
        let ordered = self.orderedIDs()
        guard !ordered.isEmpty else { return }
        self.selection.moveCursor(by: offset, extend: extend, orderedIDs: ordered)
        self.notifySelectionChanged(revealCursor: true)
    }

    func jumpToStart(extend: Bool) {
        let ordered = self.orderedIDs()
        guard !ordered.isEmpty else { return }
        self.selection.jumpToStart(extend: extend, orderedIDs: ordered)
        self.notifySelectionChanged(revealCursor: true)
    }

    func jumpToEnd(extend: Bool) {
        let ordered = self.orderedIDs()
        guard !ordered.isEmpty else { return }
        self.selection.jumpToEnd(extend: extend, orderedIDs: ordered)
        self.notifySelectionChanged(revealCursor: true)
    }

    func pageSelection(direction: Int, extend: Bool) {
        let ordered = self.orderedIDs()
        guard !ordered.isEmpty else { return }
        let step = PlaylistSelectionModel.pageStep(count: ordered.count) * (direction >= 0 ? 1 : -1)
        self.moveSelection(by: step, extend: extend)
    }

    func playSelectedTrack() {
        let playID = self.selection.cursorID ?? self.selection.selectedIDs.first
        guard let playID,
              let index = manager.tracks.firstIndex(where: { $0.id == playID })
        else { return }
        self.manager.playTrack(at: index)
    }

    func removeSelectedTracks() {
        PlaylistChromeActions.removeSelected(manager: self.manager, selection: &self.selection)
        self.notifySelectionChanged()
    }

    func cropToSelection() {
        PlaylistChromeActions.cropToSelected(manager: self.manager, selection: &self.selection)
        self.notifySelectionChanged()
    }

    func clearSelection() {
        self.selection = PlaylistSelectionModel()
        self.notifySelectionChanged()
    }

    func selectAll() {
        self.selection.selectAll(orderedIDs: self.orderedIDs())
        self.notifySelectionChanged()
    }

    func invertSelection() {
        self.selection.invert(orderedIDs: self.orderedIDs())
        self.notifySelectionChanged()
    }

    func moveSelectedTracks(by delta: Int) {
        let indices = self.selectedIndices()
        guard !indices.isEmpty else { return }
        let selectedIDs = self.selection.selectedIDs
        let cursorID = self.selection.cursorID
        let anchorID = self.selection.anchorID
        self.manager.moveSelectedTracks(indices: indices, by: delta)
        self.selection = PlaylistSelectionModel()
        self.selection.selectedIDs = selectedIDs
        self.selection.cursorID = cursorID
        self.selection.anchorID = anchorID
        self.notifySelectionChanged(revealCursor: true)
    }

    func presentFileInfo() {
        PlaylistChromeActions.presentFileInfo(manager: self.manager, selection: self.selection)
    }

    private func orderedIDs() -> [UUID] {
        self.manager.tracks.map(\.id)
    }

    private func selectedIndices() -> IndexSet {
        PlaylistChromeActions.selectedIndices(tracks: self.manager.tracks, selection: self.selection)
    }

    private func notifySelectionChanged(revealCursor: Bool = false) {
        self.onSelectionChanged?()
        if revealCursor {
            self.onRevealCursor?()
        }
    }
}

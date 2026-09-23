import Foundation

/// Routes playlist keyboard commands from `AmpXKeyRouter` into the visible playlist panel.
@MainActor
enum AmpXPlaylistKeyboard {
    private weak static var handler: Handling?

    static func register(_ handler: Handling) {
        self.handler = handler
    }

    static func unregister(_ handler: Handling) {
        if let current = self.handler as AnyObject?, let removing = handler as AnyObject?, current === removing {
            self.handler = nil
        }
    }

    static var isActive: Bool {
        self.handler != nil
    }

    static func moveSelection(by offset: Int, extend: Bool = false) {
        self.handler?.moveSelection(by: offset, extend: extend)
    }

    static func jumpToStart(extend: Bool = false) {
        self.handler?.jumpToStart(extend: extend)
    }

    static func jumpToEnd(extend: Bool = false) {
        self.handler?.jumpToEnd(extend: extend)
    }

    static func pageSelection(direction: Int, extend: Bool = false) {
        self.handler?.pageSelection(direction: direction, extend: extend)
    }

    static func playSelectedTrack() {
        self.handler?.playSelectedTrack()
    }

    static func removeSelectedTracks() {
        self.handler?.removeSelectedTracks()
    }

    static func cropToSelection() {
        self.handler?.cropToSelection()
    }

    static func clearSelection() {
        self.handler?.clearSelection()
    }

    static func selectAll() {
        self.handler?.selectAll()
    }

    static func invertSelection() {
        self.handler?.invertSelection()
    }

    static func moveSelectedTracks(by delta: Int) {
        self.handler?.moveSelectedTracks(by: delta)
    }

    static func presentFileInfo() {
        self.handler?.presentFileInfo()
    }
}

extension AmpXPlaylistKeyboard {
    @MainActor
    protocol Handling: AnyObject {
        func moveSelection(by offset: Int, extend: Bool)
        func jumpToStart(extend: Bool)
        func jumpToEnd(extend: Bool)
        func pageSelection(direction: Int, extend: Bool)
        func playSelectedTrack()
        func removeSelectedTracks()
        func cropToSelection()
        func clearSelection()
        func selectAll()
        func invertSelection()
        func moveSelectedTracks(by delta: Int)
        func presentFileInfo()
    }
}

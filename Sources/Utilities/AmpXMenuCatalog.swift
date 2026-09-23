import Foundation

/// Canonical labels and shortcut policy for the macOS menu bar.
///
/// Kept as plain data so tests can lock the structure without spinning up SwiftUI `Commands`.
enum AmpXMenuCatalog {
    enum FileItem: String, CaseIterable {
        case addFiles = "Add Files…"
        case addFolder = "Add Folder…"
        case loadPlaylist = "Load Playlist…"
        case savePlaylist = "Save Playlist…"
    }

    enum PlaybackItem: String, CaseIterable {
        case play = "Play"
        case pause = "Pause"
        case stop = "Stop"
        case previous = "Previous Track"
        case next = "Next Track"
        case shuffle = "Shuffle"
        case `repeat` = "Repeat"
    }

    enum ViewPanel: String, CaseIterable {
        case equalizer = "Equalizer"
        case playlist = "Playlist"
        case visualizer = "Visualizer"
    }

    /// Submenu under View — not a top-level "Zoom" (that collides with Window → Zoom).
    static let uiScaleMenuTitle = "UI Scale"

    /// File hotkeys: bare `L` / `⇧L` (no Command), matching `AmpXKeyRouter`.
    enum FileShortcut {
        static let addFilesKey = "l"
        static let addFilesUsesCommand = false
        static let addFilesUsesShift = false
        static let addFolderUsesCommand = false
        static let addFolderUsesShift = true
    }
}

import Foundation

/// Canonical labels and shortcut policy for the macOS menu bar.
///
/// Kept as plain data so tests can lock the structure without spinning up SwiftUI `Commands`.
enum AmpXMenuCatalog {
    enum FileItem: String, CaseIterable {
        case addFiles = "Add Files…"
        case addFolder = "Add Folder…"
        case addLibraryFolder = "Add Library Folder…"
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
        case automix = "Automix"
        case automixOptions = "Automix Options"
    }

    /// Playback ▸ Automix Options (DJ mode spec Revision 2 § User-facing settings); values as the spec names them.
    enum AutomixOption {
        /// Radio groups, in menu order, each under a section header.
        enum Group: String, CaseIterable {
            case mixPoints = "Mix Points"
            case transition = "Transition"
            case lastPhraseBlend = "Blend (Last Phrase)"
            case longestBlend = "Longest Blend (Intro / Outro)"
            case glideSpeed = "Glide Speed"
            case pickFrom = "Pick From"
        }

        enum Toggle: String {
            case glideBack = "Glide Back to Original Tempo"
            case continuation = "Continue with MIXES WELL When the Playlist Ends"
        }

        static func title(_ method: MixPointMethod) -> String {
            switch method {
            case .lastPhrase: "Last Phrase"
            case .introOutro: "Intro / Outro"
            }
        }

        static func title(_ transition: TransitionStyle) -> String {
            switch transition {
            case .crossfade: "Crossfade"
            case .bassSwap: "Bass Swap"
            }
        }

        static func title(_ pool: PickPool) -> String {
            switch pool {
            case .wholeLibrary: "Whole library"
            case .currentView: "Current view"
            }
        }

        static func bars(_ count: Int) -> String {
            "\(count) Bars"
        }

        static func glideSpeed(_ speed: Double) -> String {
            "\(speed) BPM per 4 Bars"
        }
    }

    enum ViewPanel: String, CaseIterable {
        case equalizer = "Equalizer"
        case playlist = "Playlist"
        case visualizer = "Visualizer"
        /// Its own window, listed under Window (⌘L) rather than View.
        case library = "Library"
    }

    /// File hotkeys: bare `L` / `⇧L` (no Command), matching `AmpXKeyRouter`.
    enum FileShortcut {
        static let addFilesKey = "l"
        static let addFilesUsesCommand = false
        static let addFilesUsesShift = false
        static let addFolderUsesCommand = false
        static let addFolderUsesShift = true
    }
}

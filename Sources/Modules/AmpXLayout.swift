import CoreGraphics

/// Per-module window sizes and the Winamp default arrangement. Each module is its own window, so
/// there is no composition to lay out — only how big each window is and where it starts.
enum AmpXLayout {
    /// Gap between the default Player top edge and the top of the screen's visible frame.
    static let defaultTopInset: CGFloat = 20

    static func adjustedPlaylistViewportHeight(preferred: CGFloat, heightDelta: CGFloat) -> CGFloat {
        max(AmpXMetrics.minimumPlaylistViewportHeight, preferred + heightDelta)
    }

    /// Module width: the Playlist (spec Revision 9) and the Library vary, never below their minimums.
    static func moduleWidth(
        _ moduleID: AmpXModuleID,
        playlistWidth: CGFloat,
        librarySize: CGSize = AmpXMetrics.defaultLibrarySize
    ) -> CGFloat {
        switch moduleID {
        case .playlist: max(AmpXMetrics.minimumPlaylistWidth, playlistWidth)
        case .library: max(AmpXMetrics.minimumLibrarySize.width, librarySize.width)
        default: AmpXMetrics.compositionWidth
        }
    }

    /// Size of a module's window; collapsed modules use their compact (windowshade) height.
    /// Rounded to whole points: AppKit rounds borderless window sizes anyway, and docked windows
    /// only stay flush when every edge lands on the same grid.
    static func moduleSize(
        _ moduleID: AmpXModuleID,
        state: AmpXModuleState,
        playlistViewportHeight: CGFloat,
        playlistWidth: CGFloat,
        librarySize: CGSize = AmpXMetrics.defaultLibrarySize
    ) -> CGSize {
        CGSize(
            width: self.moduleWidth(moduleID, playlistWidth: playlistWidth, librarySize: librarySize).rounded(),
            height: self.moduleHeight(moduleID, state: state, playlistViewportHeight: playlistViewportHeight, librarySize: librarySize)
                .rounded()
        )
    }

    /// Winamp's default arrangement with the Player's top-left at `anchorTopLeft`: Equalizer flush
    /// below the Player, Playlist flush below the Equalizer, ENTHEA flush right of the Player.
    /// Closed modules get a frame too, so reopening one has somewhere to go. The Library goes below the
    /// stack when `visibleFrame` has room, else right of the stack, else centred (never over the screen edge).
    static func defaultFrames(
        state: AmpXModuleState,
        playlistViewportHeight: CGFloat,
        playlistWidth: CGFloat,
        librarySize: CGSize = AmpXMetrics.defaultLibrarySize,
        anchorTopLeft: CGPoint,
        visibleFrame: CGRect? = nil
    ) -> [AmpXModuleID: CGRect] {
        func size(_ id: AmpXModuleID) -> CGSize {
            self.moduleSize(
                id, state: state, playlistViewportHeight: playlistViewportHeight, playlistWidth: playlistWidth, librarySize: librarySize
            )
        }

        var frames: [AmpXModuleID: CGRect] = [:]
        var top = anchorTopLeft.y
        for id in [AmpXModuleID.player, .equalizer, .playlist] {
            let size = size(id)
            frames[id] = CGRect(x: anchorTopLeft.x, y: top - size.height, width: size.width, height: size.height)
            top -= size.height
        }
        let entheaSize = size(.enthea)
        frames[.enthea] = CGRect(
            x: anchorTopLeft.x + size(.player).width,
            y: anchorTopLeft.y - entheaSize.height,
            width: entheaSize.width,
            height: entheaSize.height
        )
        frames[.library] = self.defaultLibraryFrame(
            size: size(.library),
            stack: [.player, .equalizer, .playlist].compactMap { frames[$0] },
            visibleFrame: visibleFrame
        )
        return frames
    }

    static func defaultLibraryFrame(size: CGSize, stack: [CGRect], visibleFrame: CGRect?) -> CGRect {
        let bounds = stack.reduce(CGRect.null) { $0.union($1) }
        let below = CGRect(x: bounds.minX, y: bounds.minY - size.height, width: size.width, height: size.height)
        guard let visible = visibleFrame else { return below }
        if visible.contains(below) {
            return below
        }
        let right = CGRect(x: bounds.maxX, y: bounds.maxY - size.height, width: size.width, height: size.height)
        if visible.contains(right) {
            return right
        }
        return CGRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded(),
            width: min(size.width, visible.width),
            height: min(size.height, visible.height)
        )
    }

    /// Player top-left for the default layout: centred horizontally, just below the visible top.
    static func defaultAnchor(visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: (visibleFrame.midX - AmpXMetrics.compositionWidth / 2).rounded(),
            y: (visibleFrame.maxY - self.defaultTopInset).rounded()
        )
    }

    private static func moduleHeight(
        _ moduleID: AmpXModuleID,
        state: AmpXModuleState,
        playlistViewportHeight: CGFloat,
        librarySize: CGSize
    ) -> CGFloat {
        if state.collapsed.contains(moduleID) {
            switch moduleID {
            case .player: return AmpXCompactMetrics.playerHeight
            case .equalizer: return AmpXCompactMetrics.equalizerHeight
            case .playlist: return AmpXCompactMetrics.playlistHeight
            case .enthea, .library: return AmpXMetrics.headerHeight
            }
        }

        switch moduleID {
        case .player:
            return AmpXMetrics.playerHeight
        case .equalizer:
            return AmpXMetrics.equalizerHeight
        case .playlist:
            return AmpXMetrics.headerHeight + AmpXMetrics.playlistNonRowChrome + playlistViewportHeight
        case .enthea:
            return AmpXMetrics.entheaHeight
        case .library:
            return max(AmpXMetrics.minimumLibrarySize.height, librarySize.height)
        }
    }
}

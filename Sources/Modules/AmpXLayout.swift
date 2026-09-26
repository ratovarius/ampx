import CoreGraphics

/// Per-module window sizes and the Winamp default arrangement. Each module is its own window, so
/// there is no composition to lay out — only how big each window is and where it starts.
enum AmpXLayout {
    /// Gap between the default Player top edge and the top of the screen's visible frame.
    static let defaultTopInset: CGFloat = 20

    static func adjustedPlaylistViewportHeight(preferred: CGFloat, heightDelta: CGFloat) -> CGFloat {
        max(AmpXMetrics.minimumPlaylistViewportHeight, preferred + heightDelta)
    }

    /// Module width: only the Playlist varies (spec Revision 9), never below its minimum.
    static func moduleWidth(_ moduleID: AmpXModuleID, playlistWidth: CGFloat) -> CGFloat {
        moduleID == .playlist
            ? max(AmpXMetrics.minimumPlaylistWidth, playlistWidth)
            : AmpXMetrics.compositionWidth
    }

    /// Size of a module's window; collapsed modules use their compact (windowshade) height.
    /// Rounded to whole points: AppKit rounds borderless window sizes anyway, and docked windows
    /// only stay flush when every edge lands on the same grid.
    static func moduleSize(
        _ moduleID: AmpXModuleID,
        state: AmpXModuleState,
        playlistViewportHeight: CGFloat,
        playlistWidth: CGFloat
    ) -> CGSize {
        CGSize(
            width: self.moduleWidth(moduleID, playlistWidth: playlistWidth).rounded(),
            height: self.moduleHeight(moduleID, state: state, playlistViewportHeight: playlistViewportHeight).rounded()
        )
    }

    /// Winamp's default arrangement with the Player's top-left at `anchorTopLeft`: Equalizer flush
    /// below the Player, Playlist flush below the Equalizer, ENTHEA flush right of the Player.
    /// Closed modules get a frame too, so reopening one has somewhere to go.
    static func defaultFrames(
        state: AmpXModuleState,
        playlistViewportHeight: CGFloat,
        playlistWidth: CGFloat,
        anchorTopLeft: CGPoint
    ) -> [AmpXModuleID: CGRect] {
        func size(_ id: AmpXModuleID) -> CGSize {
            self.moduleSize(id, state: state, playlistViewportHeight: playlistViewportHeight, playlistWidth: playlistWidth)
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
        return frames
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
        playlistViewportHeight: CGFloat
    ) -> CGFloat {
        if state.collapsed.contains(moduleID) {
            switch moduleID {
            case .player: return AmpXCompactMetrics.playerHeight
            case .equalizer: return AmpXCompactMetrics.equalizerHeight
            case .playlist: return AmpXCompactMetrics.playlistHeight
            case .enthea: return AmpXMetrics.headerHeight
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
        }
    }
}

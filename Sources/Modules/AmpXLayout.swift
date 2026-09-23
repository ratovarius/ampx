import CoreGraphics

struct AmpXLayoutResult: Equatable {
    var scale: CGFloat
    var frames: [AmpXModuleID: CGRect]
    var contentWidth: CGFloat {
        self.frames.values.map(\.maxX).max() ?? AmpXMetrics.compositionWidth
    }

    /// Host height is the taller of the left stack and right visualizer.
    var contentHeight: CGFloat
    /// Effective Playlist viewport after fitting the stack into the available height.
    var playlistViewportHeight: CGFloat
}

enum AmpXLayout {
    static func scale(width: CGFloat) -> CGFloat {
        let raw = width / AmpXMetrics.compositionWidth
        return min(1.35, max(0.85, raw))
    }

    static func adjustedPlaylistViewportHeight(
        preferred: CGFloat,
        heightDelta: CGFloat,
        scale: CGFloat
    ) -> CGFloat {
        guard scale > 0 else { return preferred }
        let adjusted = preferred + heightDelta / scale
        return max(AmpXMetrics.minimumPlaylistViewportHeight, adjusted)
    }

    /// Module width: only the Playlist varies (spec Revision 9), never below the fixed Equalizer width.
    static func moduleWidth(_ moduleID: AmpXModuleID, playlistWidth: CGFloat) -> CGFloat {
        moduleID == .playlist
            ? max(AmpXMetrics.minimumPlaylistWidth, playlistWidth)
            : AmpXMetrics.compositionWidth
    }

    /// Left modules stack edge-to-edge top-down; ENTHEA docks at the top right, clear of the widest left module.
    /// When taller than `availableHeight`, only the expanded Playlist viewport shrinks, by the excess,
    /// down to its three-row minimum.
    static func calculate(
        state: AmpXModuleOrder,
        width _: CGFloat,
        playlistViewportHeight: CGFloat,
        availableHeight: CGFloat,
        playlistWidth: CGFloat = AmpXMetrics.defaultPlaylistWidth
    ) -> AmpXLayoutResult {
        let layoutScale: CGFloat = 1
        let compositionWidth = AmpXMetrics.compositionWidth * layoutScale
        let originX: CGFloat = 0
        let visibleModules = self.stackModules(in: state).filter { $0 != .enthea }

        var effectivePlaylistViewport = playlistViewportHeight
        let preferredHeight = self.totalContentHeight(
            state: state,
            modules: visibleModules,
            scale: layoutScale,
            playlistViewportHeight: playlistViewportHeight
        )
        if preferredHeight > availableHeight,
           self.shouldShrinkPlaylist(state: state, modules: visibleModules)
        {
            let excess = (preferredHeight - availableHeight) / layoutScale
            effectivePlaylistViewport = max(
                AmpXMetrics.minimumPlaylistViewportHeight,
                playlistViewportHeight - excess
            )
        }

        let leftHeight = self.totalContentHeight(
            state: state,
            modules: visibleModules,
            scale: layoutScale,
            playlistViewportHeight: effectivePlaylistViewport
        )
        var frames = self.layoutFrames(
            modules: visibleModules,
            state: state,
            originX: originX,
            scale: layoutScale,
            playlistViewportHeight: effectivePlaylistViewport,
            playlistWidth: playlistWidth
        )

        var contentHeight = leftHeight
        if self.stackModules(in: state).contains(.enthea) {
            let height = self.moduleHeight(moduleID: .enthea, state: state, playlistViewportHeight: effectivePlaylistViewport)
            // The right column clears the widest left module, so a wide Playlist never overlaps it.
            let leftWidth = frames.values.map(\.maxX).max() ?? compositionWidth
            frames[.enthea] = CGRect(x: leftWidth + AmpXMetrics.moduleGap, y: 0, width: compositionWidth, height: height)
            contentHeight = max(contentHeight, height)
        }

        return AmpXLayoutResult(
            scale: layoutScale,
            frames: frames,
            contentHeight: contentHeight,
            playlistViewportHeight: effectivePlaylistViewport
        )
    }

    private static func stackModules(in state: AmpXModuleOrder) -> [AmpXModuleID] {
        state.order.filter { moduleID in
            !state.closed.contains(moduleID) && !state.detached.contains(moduleID)
        }
    }

    private static func shouldShrinkPlaylist(
        state: AmpXModuleOrder,
        modules: [AmpXModuleID]
    ) -> Bool {
        modules.contains(.playlist)
            && !state.collapsed.contains(.playlist)
    }

    private static func moduleHeight(
        moduleID: AmpXModuleID,
        state: AmpXModuleOrder,
        playlistViewportHeight: CGFloat
    ) -> CGFloat {
        if state.collapsed.contains(moduleID) {
            switch moduleID {
            case .player: return AmpXCompactMetrics.playerHeight
            case .equalizer: return AmpXCompactMetrics.equalizerHeight
            case .playlist: return AmpXCompactMetrics.playlistHeight
            default: return AmpXMetrics.headerHeight
            }
        }

        switch moduleID {
        case .player:
            return AmpXMetrics.playerHeight
        case .equalizer:
            return AmpXMetrics.equalizerHeight
        case .playlist:
            return AmpXMetrics.headerHeight
                + AmpXMetrics.playlistNonRowChrome
                + playlistViewportHeight
        case .enthea:
            return AmpXMetrics.entheaHeight
        }
    }

    private static func totalContentHeight(
        state: AmpXModuleOrder,
        modules: [AmpXModuleID],
        scale: CGFloat,
        playlistViewportHeight: CGFloat
    ) -> CGFloat {
        guard !modules.isEmpty else { return 0 }

        var total: CGFloat = 0
        for moduleID in modules {
            total += self.moduleHeight(
                moduleID: moduleID,
                state: state,
                playlistViewportHeight: playlistViewportHeight
            )
        }
        return total * scale
    }

    private static func layoutFrames(
        modules: [AmpXModuleID],
        state: AmpXModuleOrder,
        originX: CGFloat,
        scale: CGFloat,
        playlistViewportHeight: CGFloat,
        playlistWidth: CGFloat
    ) -> [AmpXModuleID: CGRect] {
        var frames: [AmpXModuleID: CGRect] = [:]
        var y: CGFloat = 0

        for moduleID in modules {
            let height = self.moduleHeight(
                moduleID: moduleID,
                state: state,
                playlistViewportHeight: playlistViewportHeight
            ) * scale
            let width = self.moduleWidth(moduleID, playlistWidth: playlistWidth) * scale
            frames[moduleID] = CGRect(x: originX, y: y, width: width, height: height)

            y += height
        }

        return frames
    }
}

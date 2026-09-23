import AppKit

struct AmpXPresentationVisibility: Equatable {
    var expanded: Bool
    var compact: Bool
}

struct AmpXVisibilityInputs {
    var collapsed: Bool
    var closed: Bool
    var windowVisible: Bool
    var miniaturized: Bool
    var occluded: Bool
    var intersectsViewport: Bool

    func presentationVisibility(hasCompactPresentation: Bool) -> AmpXPresentationVisibility {
        AmpXPresentationVisibility(expanded: self.isVisible, compact: self.hostVisible && self.collapsed && hasCompactPresentation)
    }

    var hostVisible: Bool {
        !self.closed && self.windowVisible && !self.miniaturized && !self.occluded && self.intersectsViewport
    }

    var isVisible: Bool {
        self.hostVisible && !self.collapsed
    }
}

enum AmpXEffectiveVisibility {
    static func stackInputs(
        collapsed: Bool,
        closed: Bool,
        window: NSWindow?,
        moduleFrame: CGRect,
        visibleContentRect: CGRect
    ) -> AmpXVisibilityInputs {
        let windowInputs = self.windowState(from: window)
        return AmpXVisibilityInputs(
            collapsed: collapsed,
            closed: closed,
            windowVisible: windowInputs.isVisible,
            miniaturized: windowInputs.isMiniaturized,
            occluded: windowInputs.isOccluded,
            intersectsViewport: moduleFrame.intersects(visibleContentRect)
        )
    }

    static func detachedInputs(
        collapsed: Bool,
        closed: Bool,
        window: NSWindow?
    ) -> AmpXVisibilityInputs {
        let windowInputs = self.windowState(from: window)
        return AmpXVisibilityInputs(
            collapsed: collapsed,
            closed: closed,
            windowVisible: windowInputs.isVisible,
            miniaturized: windowInputs.isMiniaturized,
            occluded: windowInputs.isOccluded,
            intersectsViewport: true
        )
    }

    static func theaterInputs(
        collapsed: Bool,
        closed: Bool,
        window: NSWindow?
    ) -> AmpXVisibilityInputs {
        self.detachedInputs(collapsed: collapsed, closed: closed, window: window)
    }

    private static func windowState(from window: NSWindow?) -> (isVisible: Bool, isMiniaturized: Bool, isOccluded: Bool) {
        guard let window else {
            return (false, false, true)
        }
        return (
            window.isVisible,
            window.isMiniaturized,
            !window.occlusionState.contains(.visible)
        )
    }
}

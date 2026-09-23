import AppKit

@MainActor
enum AmpXWindowChrome {
    static func apply(to window: NSWindow, minimumHeaderHeight: CGFloat) {
        guard !(window is NSPanel) else { return }

        window.styleMask = [.borderless, .resizable, .miniaturizable]
        window.collectionBehavior = []
        window.toolbar = nil

        self.hideNativeButtons(in: window)

        window.isOpaque = true
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.contentMinSize = NSSize(width: 490 * 0.85, height: minimumHeaderHeight)
    }

    private static func hideNativeButtons(in window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

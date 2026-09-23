import AppKit

/// Fixed-geometry screen for layout tests, so results don't depend on the host display.
/// CI runners have a small virtual display (~1024×768) that clamps frames a developer Mac never would.
final class AmpXTestScreen: NSScreen {
    static var standard: NSScreen {
        AmpXTestScreen()
    }

    override var frame: NSRect {
        NSRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    override var visibleFrame: NSRect {
        NSRect(x: 0, y: 0, width: 1920, height: 1055)
    }

    override var backingScaleFactor: CGFloat {
        2
    }
}

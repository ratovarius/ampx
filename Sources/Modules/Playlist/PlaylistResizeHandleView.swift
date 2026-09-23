import AppKit

/// Playlist resize affordance (spec Revisions 8 and 9): bottom and right edge strips plus a corner grip.
/// Only those rectangles hit-test and show a resize cursor; the rest of the view passes through.
final class PlaylistResizeHandleView: NSView {
    enum Edge {
        /// Height only.
        case bottom
        /// Width only.
        case right
        /// Both axes.
        case corner
    }

    enum Phase: Equatable {
        case began
        /// Accumulated size change since `began`; dragging right and down is positive.
        case changed(CGSize)
        case ended
    }

    static func cursor(for edge: Edge) -> NSCursor {
        switch edge {
        case .bottom: NSCursor.frameResize(position: .bottom, directions: .all)
        case .right: NSCursor.frameResize(position: .right, directions: .all)
        case .corner: NSCursor.frameResize(position: .bottomRight, directions: .all)
        }
    }

    static var resizeCursor: NSCursor {
        self.cursor(for: .bottom)
    }

    var onResize: ((Phase) -> Void)?

    private let skin: any AmpXSkin
    private var dragStart: (point: CGPoint, edge: Edge)?
    private var trackingArea: NSTrackingArea?

    init(skin: any AmpXSkin) {
        self.skin = skin
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    // MARK: - Geometry

    func hitRect(for edge: Edge) -> CGRect {
        let strip = AmpXMetrics.playlistResizeStripHeight
        switch edge {
        case .bottom:
            return CGRect(x: 0, y: bounds.maxY - strip, width: max(0, bounds.width - strip), height: strip)
        case .right:
            return CGRect(x: bounds.maxX - strip, y: 0, width: strip, height: max(0, bounds.height - strip))
        case .corner:
            return AmpXMetrics.playlistResizeGrip.offsetBy(dx: bounds.maxX, dy: bounds.maxY)
        }
    }

    var stripRect: CGRect {
        self.hitRect(for: .bottom)
    }

    var gripRect: CGRect {
        self.hitRect(for: .corner)
    }

    /// Corner first: it overlaps the ends of both strips.
    private func edge(at point: CGPoint) -> Edge? {
        for edge in [Edge.corner, .right, .bottom] where self.hitRect(for: edge).contains(point) {
            return edge
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview else { return nil }
        return self.edge(at: convert(point, from: superview)) != nil ? self : nil
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        for edge in [Edge.bottom, .right, .corner] {
            addCursorRect(self.hitRect(for: edge), cursor: Self.cursor(for: edge))
        }
    }

    /// Cursor rects need a key window; tracking keeps the cursor correct over inactive hosts too.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        self.updateCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        self.updateCursor(for: event)
    }

    override func mouseExited(with _: NSEvent) {
        guard self.dragStart == nil else { return }
        NSCursor.arrow.set()
    }

    private func updateCursor(for event: NSEvent) {
        guard self.dragStart == nil else { return }
        if let edge = edge(at: convert(event.locationInWindow, from: nil)) {
            Self.cursor(for: edge).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let edge = edge(at: point) else { return }
        self.dragStart = (self.screenPoint(of: event), edge)
        Self.cursor(for: edge).set()
        self.onResize?(.began)
    }

    func cancelInteraction() {
        guard self.dragStart != nil else { return }
        self.dragStart = nil
        self.onResize?(.ended)
        self.window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        Self.cursor(for: start.edge).set()
        let current = self.screenPoint(of: event)
        // Screen Y grows upward, so dragging down grows the Playlist.
        let delta = CGSize(width: current.x - start.point.x, height: start.point.y - current.y)
        switch start.edge {
        case .bottom:
            self.onResize?(.changed(CGSize(width: 0, height: delta.height)))
        case .right:
            self.onResize?(.changed(CGSize(width: delta.width, height: 0)))
        case .corner:
            self.onResize?(.changed(delta))
        }
    }

    override func mouseUp(with _: NSEvent) {
        guard self.dragStart != nil else { return }
        self.dragStart = nil
        self.onResize?(.ended)
        window?.invalidateCursorRects(for: self)
    }

    /// Screen coordinates stay stable while the host window's frame changes under the drag.
    private func screenPoint(of event: NSEvent) -> CGPoint {
        guard let window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let grip = self.gripRect
        // Three diagonal ridges toward the bottom-right corner, each a highlight over a shadow line.
        context.setLineWidth(1)
        context.setLineCap(.square)
        for index in 0 ..< 3 {
            let inset = CGFloat(index) * 3.5 + 1
            let start = CGPoint(x: grip.maxX - inset, y: grip.maxY - 1)
            let end = CGPoint(x: grip.maxX - 1, y: grip.maxY - inset)
            context.setStrokeColor(self.skin.borderDark.cgColor)
            context.strokeLineSegments(between: [
                start.applying(.init(translationX: 1, y: 1)),
                end.applying(.init(translationX: 1, y: 1)),
            ])
            context.setStrokeColor(self.skin.borderHighlight.cgColor)
            context.strokeLineSegments(between: [start, end])
        }
    }
}

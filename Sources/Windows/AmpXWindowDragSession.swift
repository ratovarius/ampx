import AppKit

/// A Winamp title-bar drag (Webamp `WindowManager`): dragging the Player moves every window docked
/// to it, dragging any other window moves it alone — which is how a window undocks. Edges within
/// `AmpXSnapGeometry.snapDistance` of another window or the screen's visible frame stick.
///
/// For the drag, the other moving windows become child windows of the dragged one, so AppKit moves
/// the whole group atomically with a single `setFrameOrigin` (no per-window frame lag). The links
/// are removed on release; docking is always re-derived from frames.
@MainActor
final class AmpXWindowDragSession {
    private weak var coordinator: AmpXHostCoordinator?
    private let screenBounds: (CGPoint) -> CGRect?

    private var lead: AmpXModuleID?
    private var startPoint: CGPoint = .zero
    private var startFrames: [AmpXModuleID: CGRect] = [:]
    private var stationary: [CGRect] = []

    init(coordinator: AmpXHostCoordinator, screenBounds: @escaping (CGPoint) -> CGRect?) {
        self.coordinator = coordinator
        self.screenBounds = screenBounds
    }

    var isDragging: Bool {
        self.lead != nil
    }

    func begin(_ id: AmpXModuleID, at screenPoint: CGPoint) {
        self.cancel()
        guard let coordinator, let leadWindow = coordinator.window(for: id) else { return }
        let frames = coordinator.openFrames()
        guard frames[id] != nil else { return }

        let moving = id == .player ? AmpXSnapGeometry.connected(from: .player, frames: frames) : [id]
        self.lead = id
        self.startPoint = screenPoint
        self.startFrames = frames.filter { moving.contains($0.key) }
        self.stationary = frames.filter { !moving.contains($0.key) }.map(\.value)

        for other in moving where other != id {
            guard let window = coordinator.window(for: other) else { continue }
            window.parent?.removeChildWindow(window)
            leadWindow.addChildWindow(window, ordered: .above)
        }
    }

    func move(to screenPoint: CGPoint) {
        guard let lead, let leadStart = self.startFrames[lead], let leadWindow = self.coordinator?.window(for: lead) else { return }
        let delta = self.snappedDelta(to: screenPoint)
        leadWindow.setFrameOrigin(CGPoint(x: leadStart.minX + delta.dx, y: leadStart.minY + delta.dy))
    }

    func end(at screenPoint: CGPoint) {
        guard self.isDragging else { return }
        self.move(to: screenPoint)
        self.finish()
    }

    /// Stops a drag in place (e.g. a windowshade toggle mid-drag) without further movement.
    func cancel() {
        guard self.isDragging else { return }
        self.finish()
    }

    /// Cursor delta plus the magnetic correction, applied rigidly to the whole moving group.
    private func snappedDelta(to screenPoint: CGPoint) -> CGVector {
        let proposed = CGVector(dx: screenPoint.x - self.startPoint.x, dy: screenPoint.y - self.startPoint.y)
        let moving = self.startFrames.values.map { $0.offsetBy(dx: proposed.dx, dy: proposed.dy) }

        var correction = AmpXSnapGeometry.snapCorrection(moving: moving, stationary: self.stationary)
        if let bounds = self.screenBounds(screenPoint) {
            let screen = AmpXSnapGeometry.screenCorrection(moving: moving, bounds: bounds)
            if correction.dx == 0 {
                correction.dx = screen.dx
            }
            if correction.dy == 0 {
                correction.dy = screen.dy
            }
        }
        return CGVector(dx: proposed.dx + correction.dx, dy: proposed.dy + correction.dy)
    }

    private func finish() {
        guard let lead, let coordinator else {
            self.reset()
            return
        }
        let leadWindow = coordinator.window(for: lead)
        let leadStart = self.startFrames[lead] ?? .zero
        let delta = leadWindow.map { CGVector(dx: $0.frame.minX - leadStart.minX, dy: $0.frame.minY - leadStart.minY) } ?? .zero

        for id in self.startFrames.keys where id != lead {
            guard let window = coordinator.window(for: id) else { continue }
            leadWindow?.removeChildWindow(window)
        }
        // Apply the group's final frames explicitly, so they are exact whatever AppKit's
        // child-window tracking did, and persist them.
        coordinator.applyFrames(self.startFrames.mapValues { $0.offsetBy(dx: delta.dx, dy: delta.dy) })
        self.reset()
    }

    private func reset() {
        self.lead = nil
        self.startFrames = [:]
        self.stationary = []
    }
}

import AppKit

struct AmpXDropGeometry {
    var bounds: CGRect
    var orderedFrames: [(AmpXModuleID, CGRect)]
}

enum AmpXModuleDragController {
    static let tearOffThreshold: CGFloat = 40
    static let settleDuration: TimeInterval = 0.175
    static let insertionMarkerHeight: CGFloat = 2

    static func dropIndex(geometry: AmpXDropGeometry, point: CGPoint) -> Int? {
        guard geometry.bounds.contains(point) else { return nil }
        guard !geometry.orderedFrames.isEmpty else { return 0 }

        for (index, frame) in geometry.orderedFrames.enumerated() {
            if point.y < frame.1.midY {
                return index
            }
        }

        return geometry.orderedFrames.count
    }

    static func fullOrderIndex(
        forVisibleDropIndex dropIndex: Int,
        excluding draggedID: AmpXModuleID,
        in state: AmpXModuleOrder
    ) -> Int {
        let visible = state.order.filter {
            $0 != .enthea && !state.closed.contains($0) && !state.detached.contains($0) && $0 != draggedID
        }
        let clamped = max(0, min(dropIndex, visible.count))

        if clamped == 0 {
            return state.order.firstIndex(where: {
                $0 != .enthea && !state.closed.contains($0) && !state.detached.contains($0) && $0 != draggedID
            }) ?? 0
        }

        if clamped >= visible.count {
            if let last = visible.last, let lastIndex = state.order.firstIndex(of: last) {
                return lastIndex + 1
            }
            return state.order.count
        }

        let anchor = visible[clamped - 1]
        return (state.order.firstIndex(of: anchor) ?? state.order.count - 1) + 1
    }
}

@MainActor
final class AmpXModuleDragSession {
    private weak var coordinator: AmpXHostCoordinator?
    private weak var viewport: AmpXStackViewport?

    private(set) var isDragging = false
    private var draggedModuleID: AmpXModuleID?
    private var didTearOff = false
    private var pendingDropIndex: Int?
    private var gripOffset = CGPoint.zero

    func bind(coordinator: AmpXHostCoordinator, viewport: AmpXStackViewport? = nil) {
        self.coordinator = coordinator
        if let viewport {
            self.viewport = viewport
        }
    }

    func bind(viewport: AmpXStackViewport) {
        self.viewport = viewport
    }

    func beginGripDrag(moduleID: AmpXModuleID, event: NSEvent) {
        guard let window = event.window else { return }
        if let view = coordinator?.moduleView(for: moduleID), let host = view.window {
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let topLeft = host.convertPoint(toScreen: view.convert(.zero, to: nil))
            self.gripOffset = CGPoint(x: point.x - topLeft.x, y: topLeft.y - point.y)
        }
        self.isDragging = true
        self.draggedModuleID = moduleID
        self.didTearOff = self.coordinator?.state.detached.contains(moduleID) ?? false
        self.pendingDropIndex = nil
        self.updateDrag(screenPoint: window.convertPoint(toScreen: event.locationInWindow))
    }

    func updateDrag(event: NSEvent) {
        guard self.isDragging, let window = event.window else { return }
        self.updateDrag(screenPoint: window.convertPoint(toScreen: event.locationInWindow))
    }

    func endDrag(event: NSEvent) {
        defer { cancelDrag() }

        guard self.isDragging,
              let moduleID = draggedModuleID,
              let coordinator,
              let window = event.window
        else { return }

        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        self.updateDrag(screenPoint: screenPoint)
        let dropIndex = self.pendingDropIndex
        let overStack = self.isPointOverStack(screenPoint: screenPoint)

        if self.didTearOff {
            if overStack, let dropIndex {
                coordinator.redock(moduleID, at: dropIndex)
            } else {
                coordinator.updateDetachedFrame(
                    moduleID,
                    frame: self.detachedFrame(anchoredTo: screenPoint, moduleID: moduleID)
                )
            }
            self.settleLayout(on: coordinator)
            return
        }

        if overStack, let dropIndex {
            coordinator.reorder(moduleID, toVisibleDropIndex: dropIndex)
            self.settleLayout(on: coordinator)
        }
    }

    func cancelDrag() {
        self.viewport?.stackView.setInsertionMarker(at: nil, width: 0)
        self.isDragging = false
        self.draggedModuleID = nil
        self.didTearOff = false
        self.pendingDropIndex = nil
    }

    func cancelDragIfDragging(moduleID: AmpXModuleID) {
        guard self.isDragging, self.draggedModuleID == moduleID else { return }
        self.cancelDrag()
    }

    private func updateDrag(screenPoint: CGPoint) {
        guard let moduleID = draggedModuleID,
              let coordinator,
              let viewport
        else { return }

        if self.didTearOff {
            coordinator.updateDetachedFrame(
                moduleID,
                frame: self.detachedFrame(anchoredTo: screenPoint, moduleID: moduleID)
            )
        }

        if self.shouldTearOff(screenPoint: screenPoint), moduleID != .player, !self.didTearOff {
            let inheritedWidth = AmpXMetrics.compositionWidth
            coordinator.detach(
                moduleID,
                at: screenPoint,
                inheritedWidth: inheritedWidth
            )
            self.didTearOff = true
            coordinator.updateDetachedFrame(
                moduleID,
                frame: self.detachedFrame(anchoredTo: screenPoint, moduleID: moduleID)
            )
        }

        guard self.isPointOverStack(screenPoint: screenPoint) else {
            self.pendingDropIndex = nil
            viewport.stackView.setInsertionMarker(at: nil, width: 0)
            return
        }

        let contentPoint = viewport.stackContentPoint(fromScreenPoint: screenPoint)
        let geometry = coordinator.makeDropGeometry(excluding: moduleID)
        if moduleID == .enthea {
            // The visualizer always returns to its fixed right-hand slot.
            self.pendingDropIndex = coordinator.state.order.count
            viewport.stackView.setInsertionMarker(at: nil, width: 0)
            return
        }
        self.pendingDropIndex = AmpXModuleDragController.dropIndex(geometry: geometry, point: contentPoint)
        self.updateInsertionMarker(for: geometry, dropIndex: self.pendingDropIndex)
    }

    private func updateInsertionMarker(for geometry: AmpXDropGeometry, dropIndex: Int?) {
        guard let viewport, let dropIndex else {
            self.viewport?.stackView.setInsertionMarker(at: nil, width: 0)
            return
        }

        let markerY: CGFloat
        if dropIndex >= geometry.orderedFrames.count {
            if let last = geometry.orderedFrames.last {
                markerY = last.1.maxY
            } else {
                markerY = 0
            }
        } else if dropIndex == 0 {
            markerY = geometry.orderedFrames.first?.1.minY ?? 0
        } else {
            let previous = geometry.orderedFrames[dropIndex - 1].1
            let next = geometry.orderedFrames[dropIndex].1
            markerY = (previous.maxY + next.minY) / 2
        }

        viewport.stackView.setInsertionMarker(at: markerY, width: geometry.bounds.width)
    }

    private func shouldTearOff(screenPoint: CGPoint) -> Bool {
        guard let viewport else { return false }
        let viewportPoint = viewport.viewportPoint(fromScreenPoint: screenPoint)
        let expanded = viewport.bounds.insetBy(
            dx: -AmpXModuleDragController.tearOffThreshold,
            dy: -AmpXModuleDragController.tearOffThreshold
        )
        return !expanded.contains(viewportPoint)
    }

    private func isPointOverStack(screenPoint: NSPoint) -> Bool {
        self.viewport?.contains(screenPoint: screenPoint) ?? false
    }

    private func detachedFrame(anchoredTo screenPoint: CGPoint, moduleID: AmpXModuleID) -> CGRect {
        let width = self.coordinator?.detachedWindowFrame(for: moduleID)?.width ?? AmpXMetrics.compositionWidth
        let height = self.coordinator?.detachedWindowFrame(for: moduleID)?.height ?? 300
        return CGRect(
            x: screenPoint.x - self.gripOffset.x,
            y: screenPoint.y + self.gripOffset.y - height,
            width: width,
            height: height
        )
    }

    private func settleLayout(on coordinator: AmpXHostCoordinator) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AmpXModuleDragController.settleDuration
            coordinator.stackWindowController?.updateLayout()
        }
    }
}

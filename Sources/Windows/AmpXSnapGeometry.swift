import CoreGraphics

/// Pure Winamp 2.x window-docking geometry, ported from Webamp's `snapUtils.ts` and
/// `withWindowGraphIntegrity` (https://github.com/captbaritone/webamp).
///
/// Frames are macOS screen coordinates (y up). Nothing here touches AppKit, so the rules are unit
/// tested without live windows; `AmpXHostCoordinator` and `AmpXWindowDragSession` apply them.
enum AmpXSnapGeometry {
    /// Edge magnetism radius, Winamp's default.
    static let snapDistance: CGFloat = 10

    /// Tolerance for "flush" when deciding which windows a resize carries along.
    private static let flushTolerance: CGFloat = 1

    // MARK: - Docking

    /// Two windows are docked when an edge sits within `snapDistance` of the other's opposite edge
    /// and they overlap (within `snapDistance`) along the other axis (Webamp `abuts`).
    static func abuts(_ a: CGRect, _ b: CGRect) -> Bool {
        if self.overlapX(a, b), self.near(a.maxY, b.minY) || self.near(a.minY, b.maxY) {
            return true
        }
        if self.overlapY(a, b), self.near(a.minX, b.maxX) || self.near(a.maxX, b.minX) {
            return true
        }
        return false
    }

    /// Every window reachable from `start` through docked neighbours, including `start`
    /// (Webamp `traceConnection`).
    static func connected<Key: Hashable>(from start: Key, frames: [Key: CGRect]) -> Set<Key> {
        guard frames[start] != nil else { return [] }
        var found: Set<Key> = [start]
        var queue = [start]
        while let key = queue.popLast() {
            guard let frame = frames[key] else { continue }
            for (other, otherFrame) in frames where !found.contains(other) && self.abuts(frame, otherFrame) {
                found.insert(other)
                queue.append(other)
            }
        }
        return found
    }

    // MARK: - Drag snapping

    /// The per-axis nudge (at most `snapDistance`) that makes any moving window flush with, or
    /// aligned to, any stationary window (Webamp `snapDiffManyToMany`). Zero on an axis with no
    /// edge in range. Applied to the whole moving group so a dragged cluster stays rigid.
    static func snapCorrection(moving: [CGRect], stationary: [CGRect]) -> CGVector {
        var dx: CGFloat?
        var dy: CGFloat?
        for box in moving {
            for other in stationary {
                if dx == nil || dx == 0, self.overlapY(box, other), let snapped = self.snappedX(box, other) {
                    dx = snapped - box.minX
                }
                if dy == nil || dy == 0, self.overlapX(box, other), let snapped = self.snappedY(box, other) {
                    dy = snapped - box.minY
                }
                if let dx, let dy, dx != 0, dy != 0 {
                    return CGVector(dx: dx, dy: dy)
                }
            }
        }
        return CGVector(dx: dx ?? 0, dy: dy ?? 0)
    }

    /// The nudge that makes the moving group's bounding box stick to an edge of `bounds`, e.g. the
    /// visible frame of the screen under the cursor (Webamp `snapWithinDiff`).
    static func screenCorrection(moving: [CGRect], bounds: CGRect) -> CGVector {
        guard let box = moving.dropFirst().reduce(moving.first, { $0?.union($1) }) else { return .zero }

        var dx: CGFloat = 0
        if self.near(box.minX, bounds.minX) {
            dx = bounds.minX - box.minX
        } else if self.near(box.maxX, bounds.maxX) {
            dx = bounds.maxX - box.maxX
        }

        var dy: CGFloat = 0
        if self.near(box.maxY, bounds.maxY) {
            dy = bounds.maxY - box.maxY
        } else if self.near(box.minY, bounds.minY) {
            dy = bounds.minY - box.minY
        }
        return CGVector(dx: dx, dy: dy)
    }

    // MARK: - Resize

    /// Frames after some windows change size, keeping attached windows attached (Webamp
    /// `withWindowGraphIntegrity`). Every window keeps its top-left corner relative to its parent:
    /// a window flush **below** another follows that window's bottom edge, one flush to its
    /// **right** follows its right edge, and shifts propagate down the chain. Windows that are not
    /// flush with a resized window (or its followers) keep their frames.
    ///
    /// - Parameters:
    ///   - before: frames before the size change.
    ///   - sizes: sizes after it. Keys missing from either input are ignored.
    /// - Returns: the new frame of every key present in both inputs.
    static func reflow<Key: Hashable>(before: [Key: CGRect], sizes: [Key: CGSize]) -> [Key: CGRect] {
        self.reflow(before: before, keys: before.keys.filter { sizes[$0] != nil }) { key, old, shift in
            let size = sizes[key]!
            return CGRect(x: old.minX + shift.dx, y: old.maxY + shift.dy - size.height, width: size.width, height: size.height)
        }
    }

    /// Like `reflow(before:sizes:)`, but the resized windows take the exact frames given — for a
    /// live edge-resize, where AppKit may move the top or left edge. Attached windows follow the
    /// edge they touch: a window below follows the bottom edge, one to the right the right edge.
    static func reflow<Key: Hashable>(before: [Key: CGRect], resized: [Key: CGRect]) -> [Key: CGRect] {
        self.reflow(before: before, keys: Array(before.keys)) { key, old, shift in
            resized[key] ?? old.offsetBy(dx: shift.dx, dy: shift.dy)
        }
    }

    /// Shared attachment walk: `newFrame` maps a window (its old frame and the shift inherited from
    /// its parent) to its new frame; a child's shift is how far the parent edge it touches moved.
    private static func reflow<Key: Hashable>(
        before: [Key: CGRect],
        keys unsorted: [Key],
        newFrame: (Key, CGRect, CGVector) -> CGRect
    ) -> [Key: CGRect] {
        let keys = unsorted.sorted { lhs, rhs in
            let a = before[lhs]!, b = before[rhs]!
            return a.maxY != b.maxY ? a.maxY > b.maxY : a.minX < b.minX
        }

        var incoming: [Key: [(parent: Key, isBelow: Bool)]] = [:]
        var outgoing: [Key: [Key]] = [:]
        for parent in keys {
            for child in keys where child != parent {
                let p = before[parent]!, c = before[child]!
                let isBelow = abs(p.minY - c.maxY) <= self.flushTolerance && self.overlaps(p.minX, p.maxX, c.minX, c.maxX)
                let isRight = abs(p.maxX - c.minX) <= self.flushTolerance && self.overlaps(p.minY, p.maxY, c.minY, c.maxY)
                guard isBelow || isRight else { continue }
                incoming[child, default: []].append((parent, isBelow))
                outgoing[parent, default: []].append(child)
            }
        }

        // Kahn order so a parent's new frame is known before its children read it. Nodes left in a
        // degenerate cycle are appended and use only already-resolved parents.
        var pending = Dictionary(uniqueKeysWithValues: keys.map { ($0, incoming[$0]?.count ?? 0) })
        var queue = keys.filter { pending[$0] == 0 }
        var ordered: [Key] = []
        while !queue.isEmpty {
            let node = queue.removeFirst()
            ordered.append(node)
            for child in outgoing[node] ?? [] {
                pending[child]! -= 1
                if pending[child] == 0 {
                    queue.append(child)
                }
            }
        }
        let placed = Set(ordered)
        ordered += keys.filter { !placed.contains($0) }

        var result: [Key: CGRect] = [:]
        for node in ordered {
            var shift = CGVector.zero
            if let edge = incoming[node]?.first(where: { result[$0.parent] != nil }) {
                let old = before[edge.parent]!, new = result[edge.parent]!
                shift = edge.isBelow
                    ? CGVector(dx: new.minX - old.minX, dy: new.minY - old.minY)
                    : CGVector(dx: new.maxX - old.maxX, dy: new.maxY - old.maxY)
            }
            result[node] = newFrame(node, before[node]!, shift)
        }
        return result
    }

    // MARK: - Private

    private static func near(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) <= self.snapDistance
    }

    private static func overlapX(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX <= b.maxX + self.snapDistance && b.minX <= a.maxX + self.snapDistance
    }

    private static func overlapY(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minY <= b.maxY + self.snapDistance && b.minY <= a.maxY + self.snapDistance
    }

    private static func overlaps(_ aMin: CGFloat, _ aMax: CGFloat, _ bMin: CGFloat, _ bMax: CGFloat) -> Bool {
        aMin < bMax - 0.5 && bMin < aMax - 0.5
    }

    /// New `minX` for `box` against `other`: touching edges first, then aligned edges.
    private static func snappedX(_ box: CGRect, _ other: CGRect) -> CGFloat? {
        if self.near(box.minX, other.maxX) {
            return other.maxX
        }
        if self.near(box.maxX, other.minX) {
            return other.minX - box.width
        }
        if self.near(box.minX, other.minX) {
            return other.minX
        }
        if self.near(box.maxX, other.maxX) {
            return other.maxX - box.width
        }
        return nil
    }

    /// New `minY` for `box` against `other`: touching edges first, then aligned edges.
    private static func snappedY(_ box: CGRect, _ other: CGRect) -> CGFloat? {
        if self.near(box.maxY, other.minY) {
            return other.minY - box.height
        }
        if self.near(box.minY, other.maxY) {
            return other.maxY
        }
        if self.near(box.maxY, other.maxY) {
            return other.maxY - box.height
        }
        if self.near(box.minY, other.minY) {
            return other.minY
        }
        return nil
    }
}

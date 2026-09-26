import CoreGraphics

/// A node in the docking graph: either the root main player or a managed panel.
enum AmpXDockNode: Hashable {
    case main
    case panel(AmpXPanelID)
}

/// Pure, geometry-primary docking resolution.
///
/// In the geometry-primary model the window *positions* are the source of truth and the dock
/// structure is **derived** from them — there is no stored order or tree. This reconstructs the
/// parent/child spanning tree (rooted at the main window) from the current frames, so the manager
/// can mirror it onto AppKit `addChildWindow` links and so panels not connected to the main cluster
/// are reported as floating.
///
/// Free of AppKit so it is unit-testable without live windows (the manager passes frames in). The
/// adjacency test is the existing 2D Webamp port `AmpXWindowSnap.abuts`, so left/right docking
/// works exactly like top/bottom.
enum AmpXDockGraph {
    /// BFS spanning tree from `.main`: each window adopts as parent the first abutting window
    /// discovered closer to the root. `order` makes the traversal deterministic when a panel abuts
    /// more than one window (earlier-ordered neighbors win), matching the registry's preference.
    ///
    /// - Returns: each docked panel mapped to its parent node. Panels absent from the result are
    ///   not connected to the main cluster (i.e. floating).
    static func parents(
        frames: [AmpXDockNode: CGRect],
        order: [AmpXPanelID]
    ) -> [AmpXPanelID: AmpXDockNode] {
        let traversal: [AmpXDockNode] = [.main] + order.map(AmpXDockNode.panel)

        var parents: [AmpXPanelID: AmpXDockNode] = [:]
        var visited: Set<AmpXDockNode> = [.main]
        var queue: [AmpXDockNode] = [.main]

        while !queue.isEmpty {
            let node = queue.removeFirst()
            guard let nodeFrame = frames[node] else { continue }
            let nodeBox = AmpXWindowSnap.Box(frame: nodeFrame)

            for candidate in traversal where !visited.contains(candidate) {
                guard case let .panel(id) = candidate, let frame = frames[candidate] else { continue }
                if AmpXWindowSnap.abuts(nodeBox, AmpXWindowSnap.Box(frame: frame)) {
                    parents[id] = node
                    visited.insert(candidate)
                    queue.append(candidate)
                }
            }
        }

        return parents
    }

    /// Frames after some windows change size, keeping every attached window attached (Webamp's
    /// `withWindowGraphIntegrity`). Each window keeps its top-left corner; a window flush **below**
    /// another follows that window's bottom edge, and one flush to its **right** follows its right
    /// edge. Shifts propagate down the attachment chain, so shading the main player pulls the EQ and
    /// the playlist beneath it up, while a window docked beside a growing playlist stays put.
    ///
    /// - Parameters:
    ///   - before: frames before the size change (macOS coordinates, y up).
    ///   - sizes: sizes after the change. Keys missing from either input are ignored.
    /// - Returns: the new frame of every key present in both inputs.
    static func reflow<Key: Hashable>(before: [Key: CGRect], sizes: [Key: CGSize]) -> [Key: CGRect] {
        let keys = before.keys
            .filter { sizes[$0] != nil }
            .sorted { lhs, rhs in
                let a = before[lhs]!, b = before[rhs]!
                return a.maxY != b.maxY ? a.maxY > b.maxY : a.minX < b.minX
            }

        // Attachment edges from the pre-change geometry: parent → child, child below or right.
        var incoming: [Key: [(parent: Key, isBelow: Bool)]] = [:]
        var outgoing: [Key: [Key]] = [:]
        for parent in keys {
            for child in keys where child != parent {
                let p = before[parent]!, c = before[child]!
                let isBelow = self.touches(p.minY, c.maxY) && self.overlaps(p.minX, p.maxX, c.minX, c.maxX)
                let isRight = self.touches(p.maxX, c.minX) && self.overlaps(p.minY, p.maxY, c.minY, c.maxY)
                guard isBelow || isRight else { continue }
                incoming[child, default: []].append((parent, isBelow))
                outgoing[parent, default: []].append(child)
            }
        }

        // Kahn topological order so a parent's shift is known before its children read it. Any
        // node left in a (degenerate) cycle is appended and only uses already-resolved parents.
        var remaining = Dictionary(uniqueKeysWithValues: keys.map { ($0, incoming[$0]?.count ?? 0) })
        var queue = keys.filter { remaining[$0] == 0 }
        var ordered: [Key] = []
        while !queue.isEmpty {
            let node = queue.removeFirst()
            ordered.append(node)
            for child in outgoing[node] ?? [] {
                remaining[child]! -= 1
                if remaining[child] == 0 { queue.append(child) }
            }
        }
        ordered += keys.filter { !ordered.contains($0) }

        // Shift of each window's top-left corner.
        var shifts: [Key: CGVector] = [:]
        for node in ordered {
            var shift = CGVector.zero
            if let edge = incoming[node]?.first(where: { shifts[$0.parent] != nil }) {
                let parentShift = shifts[edge.parent]!
                let old = before[edge.parent]!.size, new = sizes[edge.parent]!
                shift = edge.isBelow
                    ? CGVector(dx: parentShift.dx, dy: parentShift.dy - (new.height - old.height))
                    : CGVector(dx: parentShift.dx + (new.width - old.width), dy: parentShift.dy)
            }
            shifts[node] = shift
        }

        var result: [Key: CGRect] = [:]
        for key in keys {
            let old = before[key]!, size = sizes[key]!, shift = shifts[key] ?? .zero
            result[key] = CGRect(
                x: old.minX + shift.dx,
                y: old.maxY + shift.dy - size.height,
                width: size.width,
                height: size.height
            )
        }
        return result
    }

    private static func touches(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) <= 1
    }

    private static func overlaps(_ aMin: CGFloat, _ aMax: CGFloat, _ bMin: CGFloat, _ bMax: CGFloat) -> Bool {
        aMin < bMax - 0.5 && bMin < aMax - 0.5
    }

    /// Panels in `order` that are not connected to the main cluster, given the derived parents.
    static func floating(
        order: [AmpXPanelID],
        parents: [AmpXPanelID: AmpXDockNode]
    ) -> Set<AmpXPanelID> {
        Set(order.filter { parents[$0] == nil })
    }

    /// Panels whose dock ancestry includes `ancestor` (the panel itself is not returned).
    static func descendants(
        of ancestor: AmpXPanelID,
        parents: [AmpXPanelID: AmpXDockNode]
    ) -> [AmpXPanelID] {
        parents.keys.filter { id in
            self.isDescendant(id, of: ancestor, parents: parents)
        }
    }

    private static func isDescendant(
        _ id: AmpXPanelID,
        of ancestor: AmpXPanelID,
        parents: [AmpXPanelID: AmpXDockNode]
    ) -> Bool {
        var current: AmpXPanelID? = id
        var steps = 0
        while let node = current, steps < parents.count + 1 {
            switch parents[node] {
            case let .panel(parent) where parent == ancestor:
                return true
            case let .panel(parent):
                current = parent
                steps += 1
            case .main, nil:
                return false
            }
        }
        return false
    }
}

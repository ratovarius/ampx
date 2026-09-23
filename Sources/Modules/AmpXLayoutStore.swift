import AppKit
import CoreGraphics
import Foundation

struct AmpXSavedLayout: Equatable {
    var state: AmpXModuleOrder
    var stackFrame: CGRect
    var detachedFrames: [AmpXModuleID: CGRect]
    var playlistViewportHeight: CGFloat
    var playlistWidth: CGFloat = AmpXMetrics.defaultPlaylistWidth
}

@MainActor
final class AmpXLayoutStore {
    static let storageKey = "AmpXModuleLayoutV1"

    private let defaults: UserDefaults
    private let screen: NSScreen

    init(defaults: UserDefaults, screen: NSScreen? = nil) {
        self.defaults = defaults
        self.screen = screen ?? NSScreen.main ?? NSScreen.screens.first!
    }

    func load() -> AmpXSavedLayout {
        self.load(screen: self.screen)
    }

    func load(screen: NSScreen) -> AmpXSavedLayout {
        guard let data = defaults.data(forKey: Self.storageKey),
              let dto = try? JSONDecoder().decode(AmpXLayoutV1DTO.self, from: data)
        else {
            return Self.defaultLayout(for: screen)
        }

        guard dto.version == 1 else {
            return Self.defaultLayout(for: screen)
        }

        return Self.normalizedLayout(from: dto, screen: screen)
    }

    /// Launch intentionally docks every module (product choice: cold start always stacked).
    /// Detached *frames* are preserved so a later re-detach can reuse them; only the
    /// detached membership set is cleared. In-session detach/redock still restores layout.
    func loadForLaunch() -> AmpXSavedLayout {
        var layout = self.load()
        layout.state.detached.removeAll()
        return layout
    }

    func save(_ layout: AmpXSavedLayout) {
        let dto = AmpXLayoutV1DTO(layout: layout)
        guard let data = try? JSONEncoder().encode(dto) else { return }
        self.defaults.set(data, forKey: Self.storageKey)
    }

    static func defaultLayout(for screen: NSScreen) -> AmpXSavedLayout {
        AmpXSavedLayout(
            state: AmpXModuleOrder(),
            stackFrame: self.defaultStackFrame(for: screen),
            detachedFrames: [:],
            playlistViewportHeight: AmpXMetrics.defaultPlaylistViewportHeight,
            playlistWidth: AmpXMetrics.defaultPlaylistWidth
        )
    }

    static func defaultStackFrame(for screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let width = AmpXMetrics.compositionWidth
        // The window height always follows the composition; start with the default stack's height.
        let height = AmpXLayout.calculate(
            state: AmpXModuleOrder(),
            width: width,
            playlistViewportHeight: AmpXMetrics.defaultPlaylistViewportHeight,
            availableHeight: max(visible.height - 20, 1)
        ).contentHeight
        return CGRect(
            x: visible.midX - width / 2,
            y: visible.maxY - height - 20,
            width: width,
            height: height
        )
    }

    fileprivate static func normalizedLayout(from dto: AmpXLayoutV1DTO, screen: NSScreen) -> AmpXSavedLayout {
        var state = AmpXModuleOrder()
        state.order = self.normalizedOrder(dto.order)
        state.collapsed = self.normalizedIDSet(dto.collapsed)
        state.detached = self.normalizedIDSet(dto.detached)
        state.closed = self.normalizedIDSet(dto.closed)

        self.enforcePlayerRules(on: &state)

        let stackFrame = self.validatedFrame(dto.stackFrame?.cgRect, fallback: self.defaultStackFrame(for: screen), screen: screen)
        let detachedFrames = self.normalizedDetachedFrames(dto.detachedFrames, screen: screen)
        let playlistViewportHeight = self.validatedPlaylistViewportHeight(dto.playlistViewportHeight)

        return AmpXSavedLayout(
            state: state,
            stackFrame: stackFrame,
            detachedFrames: detachedFrames,
            playlistViewportHeight: playlistViewportHeight,
            playlistWidth: self.validatedPlaylistWidth(dto.playlistWidth)
        )
    }

    private static func normalizedOrder(_ rawIDs: [String]) -> [AmpXModuleID] {
        var seen = Set<AmpXModuleID>()
        var order: [AmpXModuleID] = []

        for rawID in rawIDs {
            guard let id = AmpXModuleID(rawValue: rawID), !seen.contains(id) else { continue }
            seen.insert(id)
            order.append(id)
        }

        if !order.contains(.player) {
            order.insert(.player, at: 0)
        }

        for id in AmpXModuleID.allCases where !seen.contains(id) {
            order.append(id)
            seen.insert(id)
        }

        return order
    }

    private static func normalizedIDSet(_ rawIDs: [String]) -> Set<AmpXModuleID> {
        var result = Set<AmpXModuleID>()
        for rawID in rawIDs {
            guard let id = AmpXModuleID(rawValue: rawID) else { continue }
            result.insert(id)
        }
        return result
    }

    private static func enforcePlayerRules(on state: inout AmpXModuleOrder) {
        state.closed.remove(.player)
        state.detached.remove(.player)

        if !state.order.contains(.player) {
            state.order.insert(.player, at: 0)
        }
    }

    private static func validatedFrame(_ frame: CGRect?, fallback: CGRect, screen: NSScreen) -> CGRect {
        guard let frame, isValidFrame(frame) else { return fallback }
        return self.clampedToVisibleFrame(frame, screen: screen)
    }

    private static func normalizedDetachedFrames(
        _ rawFrames: [String: AmpXFrameDTO]?,
        screen: NSScreen
    ) -> [AmpXModuleID: CGRect] {
        guard let rawFrames else { return [:] }

        var frames: [AmpXModuleID: CGRect] = [:]
        for (rawID, dto) in rawFrames {
            guard let id = AmpXModuleID(rawValue: rawID),
                  let frame = dto.cgRect,
                  isValidFrame(frame)
            else { continue }
            frames[id] = self.clampedToVisibleFrame(frame, screen: screen)
        }
        return frames
    }

    private static func validatedPlaylistViewportHeight(_ rawValue: Double?) -> CGFloat {
        guard let rawValue, rawValue.isFinite, rawValue > 0 else {
            return AmpXMetrics.defaultPlaylistViewportHeight
        }
        return max(rawValue, AmpXMetrics.minimumPlaylistViewportHeight)
    }

    /// Missing or too-small stored widths fall back to the minimum (spec Revision 9).
    private static func validatedPlaylistWidth(_ rawValue: Double?) -> CGFloat {
        guard let rawValue, rawValue.isFinite else {
            return AmpXMetrics.defaultPlaylistWidth
        }
        return max(rawValue, AmpXMetrics.minimumPlaylistWidth)
    }

    static func isValidFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
            && frame.size.width > 0
            && frame.size.height > 0
    }

    static func clampedToVisibleFrame(_ frame: CGRect, screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        var clamped = frame

        if clamped.width > visible.width {
            clamped.size.width = visible.width
        }
        if clamped.height > visible.height {
            clamped.size.height = visible.height
        }

        if clamped.maxX > visible.maxX {
            clamped.origin.x = visible.maxX - clamped.width
        }
        if clamped.minX < visible.minX {
            clamped.origin.x = visible.minX
        }
        if clamped.maxY > visible.maxY {
            clamped.origin.y = visible.maxY - clamped.height
        }
        if clamped.minY < visible.minY {
            clamped.origin.y = visible.minY
        }

        return clamped
    }
}

private struct AmpXLayoutV1DTO: Codable {
    let version: Int
    let order: [String]
    let collapsed: [String]
    let detached: [String]
    let closed: [String]
    let stackFrame: AmpXFrameDTO?
    let detachedFrames: [String: AmpXFrameDTO]?
    let playlistViewportHeight: Double?
    let playlistWidth: Double?

    init(layout: AmpXSavedLayout) {
        self.version = 1
        self.order = layout.state.order.map(\.rawValue)
        self.collapsed = layout.state.collapsed.map(\.rawValue).sorted()
        self.detached = layout.state.detached.map(\.rawValue).sorted()
        self.closed = layout.state.closed.map(\.rawValue).sorted()
        self.stackFrame = AmpXFrameDTO(layout.stackFrame)
        self.detachedFrames = Dictionary(
            uniqueKeysWithValues: layout.detachedFrames.map { ($0.key.rawValue, AmpXFrameDTO($0.value)) }
        )
        self.playlistViewportHeight = Double(layout.playlistViewportHeight)
        self.playlistWidth = Double(layout.playlistWidth)
    }
}

private struct AmpXFrameDTO: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    var cgRect: CGRect? {
        guard self.x.isFinite, self.y.isFinite, self.width.isFinite, self.height.isFinite, self.width > 0, self.height > 0 else {
            return nil
        }
        return CGRect(x: self.x, y: self.y, width: self.width, height: self.height)
    }
}

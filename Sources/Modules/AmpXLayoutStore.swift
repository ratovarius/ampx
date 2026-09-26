import AppKit
import CoreGraphics
import Foundation

struct AmpXSavedLayout: Equatable {
    var state: AmpXModuleState
    /// Window frame of every module, closed ones included, so reopening restores its spot.
    var frames: [AmpXModuleID: CGRect]
    var playlistViewportHeight: CGFloat
    var playlistWidth: CGFloat = AmpXMetrics.defaultPlaylistWidth
}

@MainActor
final class AmpXLayoutStore {
    static let storageKey = "AmpXModuleLayoutV2"
    /// The single-window stack layout; read once to migrate collapsed/closed state and sizes.
    static let legacyStorageKey = "AmpXModuleLayoutV1"

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
        if let data = defaults.data(forKey: Self.storageKey) {
            guard let dto = try? JSONDecoder().decode(AmpXLayoutV2DTO.self, from: data), dto.version == 2 else {
                return Self.defaultLayout(for: screen)
            }
            return Self.normalizedLayout(from: dto, screen: screen)
        }
        if let data = defaults.data(forKey: Self.legacyStorageKey),
           let legacy = try? JSONDecoder().decode(AmpXLayoutV1DTO.self, from: data),
           legacy.version == 1
        {
            return Self.migratedLayout(from: legacy, screen: screen)
        }
        return Self.defaultLayout(for: screen)
    }

    func save(_ layout: AmpXSavedLayout) {
        guard let data = try? JSONEncoder().encode(AmpXLayoutV2DTO(layout: layout)) else { return }
        self.defaults.set(data, forKey: Self.storageKey)
    }

    static func defaultLayout(for screen: NSScreen) -> AmpXSavedLayout {
        let state = AmpXModuleState()
        return AmpXSavedLayout(
            state: state,
            frames: AmpXLayout.defaultFrames(
                state: state,
                playlistViewportHeight: AmpXMetrics.defaultPlaylistViewportHeight,
                playlistWidth: AmpXMetrics.defaultPlaylistWidth,
                anchorTopLeft: AmpXLayout.defaultAnchor(visibleFrame: screen.visibleFrame)
            ),
            playlistViewportHeight: AmpXMetrics.defaultPlaylistViewportHeight,
            playlistWidth: AmpXMetrics.defaultPlaylistWidth
        )
    }

    fileprivate static func normalizedLayout(from dto: AmpXLayoutV2DTO, screen: NSScreen) -> AmpXSavedLayout {
        let state = self.normalizedState(collapsed: dto.collapsed, closed: dto.closed)
        let viewport = self.validatedPlaylistViewportHeight(dto.playlistViewportHeight)
        let width = self.validatedPlaylistWidth(dto.playlistWidth)

        var saved: [AmpXModuleID: CGRect] = [:]
        for (rawID, frameDTO) in dto.frames ?? [:] {
            guard let id = AmpXModuleID(rawValue: rawID), let frame = frameDTO.cgRect, self.isValidFrame(frame) else { continue }
            saved[id] = frame
        }
        // Modules without a saved frame fall back to the default arrangement around the Player.
        let anchor = saved[.player].map { CGPoint(x: $0.minX, y: $0.maxY) }
            ?? AmpXLayout.defaultAnchor(visibleFrame: screen.visibleFrame)
        let fallback = AmpXLayout.defaultFrames(
            state: state,
            playlistViewportHeight: viewport,
            playlistWidth: width,
            anchorTopLeft: anchor
        )
        let frames = fallback.merging(saved) { _, stored in stored }
            .mapValues { self.clampedToVisibleFrame($0, screen: screen) }

        return AmpXSavedLayout(state: state, frames: frames, playlistViewportHeight: viewport, playlistWidth: width)
    }

    /// V1 kept one stack window; its frames can't map onto separate windows, so the default
    /// arrangement is anchored at the old stack's top-left instead.
    fileprivate static func migratedLayout(from dto: AmpXLayoutV1DTO, screen: NSScreen) -> AmpXSavedLayout {
        let state = self.normalizedState(collapsed: dto.collapsed, closed: dto.closed)
        let viewport = self.validatedPlaylistViewportHeight(dto.playlistViewportHeight)
        let width = self.validatedPlaylistWidth(dto.playlistWidth)
        let anchor = dto.stackFrame?.cgRect.flatMap { self.isValidFrame($0) ? CGPoint(x: $0.minX, y: $0.maxY) : nil }
            ?? AmpXLayout.defaultAnchor(visibleFrame: screen.visibleFrame)
        let frames = AmpXLayout.defaultFrames(
            state: state,
            playlistViewportHeight: viewport,
            playlistWidth: width,
            anchorTopLeft: anchor
        ).mapValues { self.clampedToVisibleFrame($0, screen: screen) }
        return AmpXSavedLayout(state: state, frames: frames, playlistViewportHeight: viewport, playlistWidth: width)
    }

    private static func normalizedState(collapsed: [String], closed: [String]) -> AmpXModuleState {
        var state = AmpXModuleState()
        state.collapsed = self.normalizedIDSet(collapsed)
        state.closed = self.normalizedIDSet(closed)
        state.closed.remove(.player)
        return state
    }

    private static func normalizedIDSet(_ rawIDs: [String]) -> Set<AmpXModuleID> {
        Set(rawIDs.compactMap(AmpXModuleID.init(rawValue:)))
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

private struct AmpXLayoutV2DTO: Codable {
    let version: Int
    let collapsed: [String]
    let closed: [String]
    let frames: [String: AmpXFrameDTO]?
    let playlistViewportHeight: Double?
    let playlistWidth: Double?

    init(layout: AmpXSavedLayout) {
        self.version = 2
        self.collapsed = layout.state.collapsed.map(\.rawValue).sorted()
        self.closed = layout.state.closed.map(\.rawValue).sorted()
        self.frames = Dictionary(uniqueKeysWithValues: layout.frames.map { ($0.key.rawValue, AmpXFrameDTO($0.value)) })
        self.playlistViewportHeight = Double(layout.playlistViewportHeight)
        self.playlistWidth = Double(layout.playlistWidth)
    }
}

/// Decode-only view of the retired single-stack layout, kept for migration.
private struct AmpXLayoutV1DTO: Decodable {
    let version: Int
    let collapsed: [String]
    let closed: [String]
    let stackFrame: AmpXFrameDTO?
    let playlistViewportHeight: Double?
    let playlistWidth: Double?
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

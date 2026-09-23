import AppKit

/// Source coordinates from shrunk-modules/reference/measurements.json, uniformly normalized.
enum AmpXCompactMetrics {
    static let factor: CGFloat = 490 / 1361
    static let playerHeight: CGFloat = 84 * factor
    static let equalizerHeight: CGFloat = 84 * factor
    static let playlistHeight: CGFloat = 76 * factor

    struct Chrome {
        let grip: CGRect
        let brand: CGRect
        let separators: [CGRect]
        let minimize: CGRect?
        let expand: CGRect
        let close: CGRect
    }

    struct PlayerLayout {
        let chrome: Chrome
        let well: CGRect
        let visualizer: CGRect
        let timer: CGRect
        let transport: [CGRect]
        let transportGlyphs: [CGRect]
    }

    struct EqualizerLayout {
        let chrome: Chrome
        let volume: CGRect
        let balance: CGRect
        let volumeTrack: CGRect
        let balanceTrack: CGRect
        let volumeThumbSize: CGSize
        let balanceThumbSize: CGSize
        let separator: CGRect
    }

    struct PlaylistLayout {
        let chrome: Chrome
        let well: CGRect
        let listOptions: CGRect
    }

    static func playlistLayout(width: CGFloat) -> PlaylistLayout {
        let extra = max(0, width - 490)
        let referenceWell = self.source(262, 846 - 556, 923, 49)
        return PlaylistLayout(
            chrome: self.chrome(moduleID: .playlist, width: width),
            well: CGRect(
                x: referenceWell.minX,
                y: referenceWell.minY,
                width: referenceWell.width + extra,
                height: referenceWell.height
            ),
            listOptions: self.source(1197, 845 - 556, 51, 49).offsetBy(dx: extra, dy: 0)
        )
    }

    static func equalizerLayout() -> EqualizerLayout {
        let volume = self.source(285, 591 - 281, 422, 22)
        let balance = self.source(757, 591 - 281, 465, 22)
        return EqualizerLayout(
            chrome: self.chrome(moduleID: .equalizer),
            volume: volume.insetBy(dx: 0, dy: -5),
            balance: balance.insetBy(dx: 0, dy: -5),
            volumeTrack: volume,
            balanceTrack: balance,
            volumeThumbSize: CGSize(width: 45 * self.factor, height: 42 * self.factor),
            balanceThumbSize: CGSize(width: 50 * self.factor, height: 42 * self.factor),
            separator: self.source(728, 582 - 281, 7, 38)
        )
    }

    static func source(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: (x - 28) * self.factor, y: (y - 276) * self.factor, width: width * self.factor, height: height * self.factor)
    }

    static func chrome(moduleID: AmpXModuleID, width: CGFloat = 490) -> Chrome {
        let offset = max(490, width) - 490
        let isPlayer = moduleID == .player
        let dy: CGFloat = moduleID == .playlist ? -4 * self.factor : 0
        let trailingSeparator: CGFloat = isPlayer ? 1175 : (moduleID == .playlist ? 1250 : 1238)
        return Chrome(
            grip: self.source(45, 293, 60, 54).offsetBy(dx: 0, dy: dy),
            brand: self.source(123, 306, 97, 35).offsetBy(dx: 0, dy: dy),
            separators: [
                self.source(254, 302, 6, 38).offsetBy(dx: 0, dy: dy),
                self.source(trailingSeparator, 285, 7, moduleID == .playlist ? 61 : 69).offsetBy(dx: offset, dy: 0),
            ],
            minimize: isPlayer ? self.source(1200, 294, 50, 51) : nil,
            expand: self.source(1263, 294, 51, 51).offsetBy(dx: offset, dy: dy),
            close: self.source(1325, 294, 50, 51).offsetBy(dx: offset, dy: dy)
        )
    }

    static func playerLayout() -> PlayerLayout {
        PlayerLayout(
            chrome: self.chrome(moduleID: .player),
            well: self.source(276, 292, 512, 56),
            visualizer: self.source(292, 302, 279, 38),
            timer: self.source(617, 298, 150, 46),
            transport: [
                self.source(814, 291, 64, 58),
                self.source(885, 291, 63, 58),
                self.source(956, 291, 62, 58),
                self.source(1026, 291, 63, 58),
                self.source(1097, 291, 64, 58),
            ],
            transportGlyphs: [
                self.source(834, 308, 23, 25),
                self.source(907, 308, 22, 25),
                self.source(978, 310, 19, 22),
                self.source(1047, 311, 20, 20),
                self.source(1117, 308, 24, 25),
            ]
        )
    }
}

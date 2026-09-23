import AppKit
import CoreGraphics

enum PlaylistRowLayout {
    static let rowHeight: CGFloat = AmpXMetrics.playlistRowHeight
    static let durationColumnWidth: CGFloat = AmpXMetrics.playlistDurationColumnWidth

    /// Positioned text for one row: number, clipped title and right-aligned duration.
    struct RowText {
        var numberRect: CGRect
        /// Clip rect for the title; the title is drawn from `minX`.
        var titleRect: CGRect
        var durationRect: CGRect
        var baseline: CGFloat
    }

    static func visibleRange(offset: CGFloat, viewport: CGFloat, count: Int) -> Range<Int> {
        guard count > 0 else { return 0 ..< 0 }
        let first = max(0, Int(floor(offset / self.rowHeight)))
        let last = min(count, Int(ceil((offset + viewport) / self.rowHeight)))
        return first ..< last
    }

    /// Winamp PLEDIT colors: the playing track is white; selection only fills the row behind the text.
    static func textColor(isSelected _: Bool, isCurrent: Bool, skin: any AmpXSkin) -> NSColor {
        isCurrent ? skin.text : skin.green
    }

    /// Offset that centers `row` when it is not fully visible, clamped to the playlist; `nil` when it already is.
    static func revealOffset(forRow row: Int, offset: CGFloat, viewport: CGFloat, count: Int) -> CGFloat? {
        guard row >= 0, row < count, viewport > 0 else { return nil }
        let top = CGFloat(row) * self.rowHeight
        if top >= offset, top + self.rowHeight <= offset + viewport {
            return nil
        }
        return AmpXControlMath.clampedScrollOffset(
            top - (viewport - self.rowHeight) / 2,
            contentLength: CGFloat(count) * self.rowHeight,
            viewportLength: viewport
        )
    }

    static func rowRect(index: Int, width: CGFloat) -> CGRect {
        CGRect(
            x: 0,
            y: CGFloat(index) * self.rowHeight,
            width: width,
            height: self.rowHeight
        )
    }

    static func titleRect(in row: CGRect) -> CGRect {
        let minX = row.minX + AmpXMetrics.playlistRowTitleX
        return CGRect(
            x: minX,
            y: row.minY,
            width: max(0, self.durationRect(in: row).minX - 4 - minX),
            height: row.height
        )
    }

    static func durationRect(in row: CGRect) -> CGRect {
        CGRect(
            x: row.maxX - AmpXMetrics.playlistDurationTrailingInset - self.durationColumnWidth,
            y: row.minY,
            width: self.durationColumnWidth,
            height: row.height
        )
    }

    static func font(skin: any AmpXSkin) -> NSFont {
        skin.font(size: AmpXMetrics.playlistRowFontSize, weight: .regular)
    }

    /// Numbers right-align to a fixed column; wide numbers push the title right instead of overlapping it.
    static func textLayout(
        number: Int,
        title _: String,
        duration: String,
        in row: CGRect,
        skin: any AmpXSkin = ClassicModernSkin()
    ) -> RowText {
        func width(_ text: String) -> CGFloat {
            AmpXLabel(text: text, color: skin.text, fontSize: AmpXMetrics.playlistRowFontSize, weight: .regular)
                .measuredSize(skin: skin).width
        }
        let font = font(skin: skin)
        let baseline = row.midY + font.capHeight / 2
        let numberWidth = width("\(number).")
        let numberX = max(row.minX, row.minX + AmpXMetrics.playlistRowNumberMaxX - numberWidth)
        let numberRect = CGRect(x: numberX, y: row.minY, width: numberWidth, height: row.height)

        let column = self.durationRect(in: row)
        let durationWidth = min(width(duration), column.width)
        let durationBox = CGRect(x: column.maxX - durationWidth, y: row.minY, width: durationWidth, height: row.height)

        var titleBox = self.titleRect(in: row)
        let minimumTitleX = numberRect.maxX + font.maximumAdvancement.width / 2
        if titleBox.minX < minimumTitleX {
            titleBox = CGRect(
                x: minimumTitleX,
                y: row.minY,
                width: max(0, titleBox.maxX - minimumTitleX),
                height: row.height
            )
        }
        return RowText(numberRect: numberRect, titleRect: titleBox, durationRect: durationBox, baseline: baseline)
    }
}

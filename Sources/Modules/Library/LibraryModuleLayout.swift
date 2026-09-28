import CoreGraphics

/// Content-local pane frames of the Library window (Library Module spec § Layout): toolbar on top, footer at
/// the bottom, and between them GENRE over ARTIST (230 pt), the track table, and the MIXES WELL sidebar.
enum LibraryModuleLayout {
    struct Frames {
        var toolbar: CGRect
        var genre: CGRect
        var artist: CGRect
        var table: CGRect
        var sidebar: CGRect
        var footer: CGRect
    }

    static let facetColumnWidth: CGFloat = 230
    static let gutter: CGFloat = 6
    static let insets = (top: CGFloat(8), left: CGFloat(10), bottom: CGFloat(8), right: CGFloat(10))

    static func frames(size: CGSize) -> Frames {
        let inner = CGRect(
            x: self.insets.left,
            y: self.insets.top,
            width: max(0, size.width - self.insets.left - self.insets.right),
            height: max(0, size.height - self.insets.top - self.insets.bottom)
        )
        let toolbar = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: LibraryToolbarView.height)
        let footer = CGRect(x: inner.minX, y: inner.maxY - LibraryFooterView.height, width: inner.width, height: LibraryFooterView.height)
        let bodyTop = toolbar.maxY + self.gutter
        let bodyHeight = max(0, footer.minY - self.gutter - bodyTop)

        let facetHeight = max(0, (bodyHeight - self.gutter) / 2)
        let genre = CGRect(x: inner.minX, y: bodyTop, width: self.facetColumnWidth, height: facetHeight)
        let artist = CGRect(x: inner.minX, y: genre.maxY + self.gutter, width: self.facetColumnWidth, height: facetHeight)
        let sidebar = CGRect(
            x: inner.maxX - LibraryMixesSidebarView.width, y: bodyTop, width: LibraryMixesSidebarView.width, height: bodyHeight
        )
        let tableX = genre.maxX + self.gutter
        let table = CGRect(x: tableX, y: bodyTop, width: max(0, sidebar.minX - self.gutter - tableX), height: bodyHeight)
        return Frames(toolbar: toolbar, genre: genre, artist: artist, table: table, sidebar: sidebar, footer: footer)
    }
}

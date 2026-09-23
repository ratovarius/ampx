@testable import AmpX
import XCTest

/// Winamp PLEDIT behavior: the playing track is white, selection only fills the row, and the
/// list follows the playing track.
@MainActor
final class PlaylistNowPlayingTests: XCTestCase {
    private let skin = ClassicModernSkin()
    private let rowHeight = PlaylistRowLayout.rowHeight

    func testPlayingRowTextIsWhiteWhetherOrNotSelected() {
        XCTAssertEqual(PlaylistRowLayout.textColor(isSelected: false, isCurrent: true, skin: self.skin), self.skin.text)
        XCTAssertEqual(PlaylistRowLayout.textColor(isSelected: true, isCurrent: true, skin: self.skin), self.skin.text)
    }

    func testSelectedRowKeepsGreenTextWhenNotPlaying() {
        XCTAssertEqual(PlaylistRowLayout.textColor(isSelected: true, isCurrent: false, skin: self.skin), self.skin.green)
        XCTAssertEqual(PlaylistRowLayout.textColor(isSelected: false, isCurrent: false, skin: self.skin), self.skin.green)
    }

    func testRevealOffsetIsNilWhenRowIsFullyVisible() {
        XCTAssertNil(PlaylistRowLayout.revealOffset(forRow: 3, offset: 2 * self.rowHeight, viewport: 5 * self.rowHeight, count: 30))
    }

    func testRevealOffsetCentersRowBelowViewport() {
        XCTAssertEqual(
            PlaylistRowLayout.revealOffset(forRow: 20, offset: 0, viewport: 5 * self.rowHeight, count: 30),
            18 * self.rowHeight
        )
    }

    func testRevealOffsetCentersPartiallyVisibleRow() {
        XCTAssertEqual(
            PlaylistRowLayout.revealOffset(forRow: 5, offset: 0.5 * self.rowHeight, viewport: 5 * self.rowHeight, count: 30),
            3 * self.rowHeight
        )
    }

    func testRevealOffsetClampsToPlaylistEdges() {
        XCTAssertEqual(
            PlaylistRowLayout.revealOffset(forRow: 1, offset: 20 * self.rowHeight, viewport: 5 * self.rowHeight, count: 30),
            0
        )
        XCTAssertEqual(
            PlaylistRowLayout.revealOffset(forRow: 29, offset: 0, viewport: 5 * self.rowHeight, count: 30),
            25 * self.rowHeight
        )
    }

    func testPlayingTrackChangeScrollsRowIntoViewOnlyWhenHidden() {
        let (manager, content) = self.makePlaylist(trackCount: 30)
        let viewport = AmpXMetrics.minimumPlaylistViewportHeight
        XCTAssertEqual(content.scrollOffset, 0)

        self.waitForDelivery(of: manager.$currentIndex, where: { $0 == 20 }) {
            manager.currentIndex = 20
        }
        let centered = 20 * self.rowHeight - (viewport - self.rowHeight) / 2
        XCTAssertEqual(content.scrollOffset, centered, accuracy: 0.001)

        let visibleRow = 20 + Int(floor((viewport - self.rowHeight) / 2 / self.rowHeight))
        self.waitForDelivery(of: manager.$currentIndex, where: { $0 == visibleRow }) {
            manager.currentIndex = visibleRow
        }
        XCTAssertEqual(content.scrollOffset, centered, accuracy: 0.001)
    }

    private func makePlaylist(trackCount: Int) -> (PlaylistManager, PlaylistModuleContent) {
        let manager = PlaylistManager(
            audioPlayer: MockAudioPlayer(),
            restoreBookmarks: false,
            restorePlaylist: false,
            alertPresenter: SilentPlaylistAlertPresenter()
        )
        let content = PlaylistModuleContent(
            skin: self.skin,
            manager: manager,
            audioPlayer: AudioPlayer(installRemoteCommands: false)
        )
        content.setRowViewportHeight(AmpXMetrics.minimumPlaylistViewportHeight)
        self.waitForDelivery(of: manager.$tracks, where: { $0.count == trackCount }) {
            manager.addTracks((0 ..< trackCount).map { index in
                Track(title: "Track \(index)", artist: "Artist", url: URL(fileURLWithPath: "/tmp/\(index).mp3"))
            })
        }
        return (manager, content)
    }

    /// Performs `change`, then waits until a main-queue subscriber sees a matching value. The module subscribed
    /// first, so its main-queue handler has already run; no fixed delay, so a busy main queue can't race it.
    private func waitForDelivery<Value>(
        of publisher: Published<Value>.Publisher,
        where matches: @escaping (Value) -> Bool,
        after change: () -> Void
    ) {
        let delivered = expectation(description: "published value delivered on main queue")
        let subscription = publisher
            .receive(on: DispatchQueue.main)
            .sink { value in
                if matches(value) {
                    delivered.fulfill()
                }
            }
        change()
        wait(for: [delivered], timeout: 10)
        subscription.cancel()
    }
}

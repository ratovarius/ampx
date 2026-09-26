@testable import AmpX
import XCTest

/// The pure Winamp/Webamp docking core: abut test, drag snap corrections, connected clusters and
/// the attachment reflow that keeps docked windows together across a resize.
final class AmpXSnapGeometryTests: XCTestCase {
    private let player = CGRect(x: 100, y: 800, width: 275, height: 116)

    private func below(_ anchor: CGRect, height: CGFloat = 116, dx: CGFloat = 0, gap: CGFloat = 0) -> CGRect {
        CGRect(x: anchor.minX + dx, y: anchor.minY - gap - height, width: anchor.width, height: height)
    }

    private func rightOf(_ anchor: CGRect, width: CGFloat = 275, height: CGFloat = 116, gap: CGFloat = 0) -> CGRect {
        CGRect(x: anchor.maxX + gap, y: anchor.maxY - height, width: width, height: height)
    }

    // MARK: - abuts

    func testAbutsFlushVertical() {
        XCTAssertTrue(AmpXSnapGeometry.abuts(self.player, self.below(self.player)))
    }

    func testAbutsWithinDistance() {
        XCTAssertTrue(AmpXSnapGeometry.abuts(self.player, self.below(self.player, gap: 9)))
    }

    func testDoesNotAbutBeyondDistance() {
        XCTAssertFalse(AmpXSnapGeometry.abuts(self.player, self.below(self.player, gap: 11)))
    }

    func testCornerContactIsNotDocked() {
        let corner = CGRect(x: self.player.maxX + 11, y: self.player.minY - 50, width: 275, height: 50)
        XCTAssertFalse(AmpXSnapGeometry.abuts(self.player, corner))

        let result = AmpXSnapGeometry.reflow(
            before: ["player": self.player, "corner": corner],
            sizes: ["player": CGSize(width: 275, height: 14), "corner": corner.size]
        )
        XCTAssertEqual(result["corner"], corner)
    }

    // MARK: - Drag snapping

    func testSnapCorrectionPullsFlushBelow() {
        let moving = self.below(self.player, gap: 6)
        let correction = AmpXSnapGeometry.snapCorrection(moving: [moving], stationary: [self.player])
        XCTAssertEqual(correction.dx, 0)
        XCTAssertEqual(correction.dy, 6)
    }

    func testSnapCorrectionAlignsLeftEdges() {
        let moving = self.below(self.player, dx: 7)
        let correction = AmpXSnapGeometry.snapCorrection(moving: [moving], stationary: [self.player])
        XCTAssertEqual(correction.dx, -7)
        XCTAssertEqual(correction.dy, 0)
    }

    func testScreenCorrectionSticksToVisibleFrame() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        let nearEdges = CGRect(x: 8, y: 1050 - 116, width: 275, height: 116)
        let correction = AmpXSnapGeometry.screenCorrection(moving: [nearEdges], bounds: bounds)
        XCTAssertEqual(correction.dx, -8)
        XCTAssertEqual(correction.dy, 5)

        let far = CGRect(x: 500, y: 400, width: 275, height: 116)
        XCTAssertEqual(AmpXSnapGeometry.screenCorrection(moving: [far], bounds: bounds), .zero)
    }

    // MARK: - Clusters

    func testConnectedIsTransitive() {
        let equalizer = self.below(self.player)
        let playlist = self.below(equalizer, height: 232)
        let floating = CGRect(x: 1200, y: 100, width: 275, height: 116)
        let connected = AmpXSnapGeometry.connected(
            from: "player",
            frames: ["player": self.player, "eq": equalizer, "pl": playlist, "far": floating]
        )
        XCTAssertEqual(connected, ["player", "eq", "pl"])
    }

    // MARK: - Reflow

    func testReflowShadePullsChainUp() {
        let equalizer = self.below(self.player)
        let playlist = self.below(equalizer, height: 232)
        let result = AmpXSnapGeometry.reflow(
            before: ["player": self.player, "eq": equalizer, "pl": playlist],
            sizes: ["player": CGSize(width: 275, height: 14), "eq": equalizer.size, "pl": playlist.size]
        )
        XCTAssertEqual(result["player"]?.maxY, self.player.maxY)
        XCTAssertEqual(result["eq"]?.maxY, result["player"]?.minY)
        XCTAssertEqual(result["pl"]?.maxY, result["eq"]?.minY)
    }

    func testReflowGrowingPlaylistMovesBelowNotBeside() {
        let playlist = self.below(self.player, height: 232)
        let beside = self.rightOf(playlist, height: 232)
        let under = self.below(playlist)
        let result = AmpXSnapGeometry.reflow(
            before: ["player": self.player, "pl": playlist, "beside": beside, "under": under],
            sizes: [
                "player": self.player.size,
                "pl": CGSize(width: 275, height: 300),
                "beside": beside.size,
                "under": under.size,
            ]
        )
        XCTAssertEqual(result["beside"], beside)
        XCTAssertEqual(result["under"]?.maxY, result["pl"]?.minY)
        XCTAssertEqual(result["pl"]?.maxY, playlist.maxY)
    }

    func testReflowWideningMovesRightNeighbour() {
        let side = self.rightOf(self.player)
        let result = AmpXSnapGeometry.reflow(
            before: ["player": self.player, "side": side],
            sizes: ["player": CGSize(width: 550, height: 116), "side": side.size]
        )
        XCTAssertEqual(result["side"]?.minX, self.player.minX + 550)
        XCTAssertEqual(result["side"]?.maxY, side.maxY)
    }

    func testReflowRightChildInheritsParentVerticalShift() {
        let equalizer = self.below(self.player)
        let besideEqualizer = self.rightOf(equalizer)
        let result = AmpXSnapGeometry.reflow(
            before: ["player": self.player, "eq": equalizer, "side": besideEqualizer],
            sizes: ["player": CGSize(width: 275, height: 14), "eq": equalizer.size, "side": besideEqualizer.size]
        )
        let equalizerShift = (result["eq"]?.maxY ?? 0) - equalizer.maxY
        XCTAssertEqual(equalizerShift, 102)
        XCTAssertEqual((result["side"]?.maxY ?? 0) - besideEqualizer.maxY, equalizerShift)
    }
}

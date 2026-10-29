@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § Mix points: bars from each track's first downbeat.
final class MixGridTests: XCTestCase {
    private func beat(_ start: Double, _ bpm: Double, beat: Int = 1) -> RekordboxBeat {
        RekordboxBeat(start: start, bpm: bpm, meter: "4/4", beat: beat)
    }

    func testSteadyGrid() throws {
        let grid = try XCTUnwrap(MixGrid(segments: [self.beat(0.5, 120)], duration: 300))
        XCTAssertEqual(grid.time(ofBeat: 4), 2.5, accuracy: 1e-9)
        XCTAssertEqual(grid.firstDownbeat, 0)
        XCTAssertEqual(grid.time(ofBar: 1), 2.5, accuracy: 1e-9)
        XCTAssertEqual(grid.bar(at: 4.5), 2.0, accuracy: 1e-9)
        XCTAssertEqual(grid.beat(at: 2.5), 4.0, accuracy: 1e-9)
        XCTAssertEqual(grid.lastFullBar, 148)
    }

    func testFirstBeatMidBar() throws {
        let grid = try XCTUnwrap(MixGrid(segments: [self.beat(0, 120, beat: 3)], duration: 60))
        XCTAssertEqual(grid.firstDownbeat, 2)
        XCTAssertEqual(grid.time(ofBar: 0), 1.0, accuracy: 1e-9)
    }

    func testTwoSegments() throws {
        let grid = try XCTUnwrap(MixGrid(segments: [self.beat(0, 120), self.beat(10, 125)], duration: 120))
        XCTAssertEqual(grid.time(ofBeat: 20), 10.0, accuracy: 1e-9)
        XCTAssertEqual(grid.time(ofBeat: 21), 10.48, accuracy: 1e-9)
        XCTAssertEqual(grid.localBPM(at: 11), 125)
        XCTAssertEqual(grid.localBPM(at: 5), 120)
        XCTAssertEqual(grid.beat(at: 10.48), 21, accuracy: 1e-9)
    }

    func testPhraseBeatIsOneBased() throws {
        let grid = try XCTUnwrap(MixGrid(segments: [self.beat(0.2, 128)], duration: 200))
        XCTAssertEqual(grid.phraseBeatTime(1), grid.time(ofBeat: 0))
        XCTAssertEqual(grid.phraseBeatTime(65), grid.time(ofBar: 16), accuracy: 1e-9)
    }

    func testRejectsEmptyAndZeroBPM() {
        XCTAssertNil(MixGrid(segments: [], duration: 100))
        XCTAssertNil(MixGrid(segments: [self.beat(0, 0)], duration: 100))
        XCTAssertNil(MixGrid(segments: [self.beat(0, 120)], duration: 0))
    }
}

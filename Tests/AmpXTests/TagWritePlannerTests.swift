@testable import AmpX
import XCTest

/// DJ mode spec Revision 2 § Tag writing (rules).
final class TagWritePlannerTests: XCTestCase {
    private func row(
        bpm: Double? = 128,
        key: String? = "Am",
        label: String? = nil,
        remixer: String? = nil,
        hash: Data? = nil
    ) -> TagWriteRow {
        TagWriteRow(
            rowID: UUID(), rootID: UUID(), url: URL(fileURLWithPath: "/Music/DJ/a.mp3"),
            bpm: bpm, musicalKey: key, label: label, remixer: remixer, composer: nil, grouping: nil, tagsWrittenHash: hash
        )
    }

    func testDesiredRoundsBPMAndOmitsNil() {
        XCTAssertEqual(TagWritePlanner.desired(self.row(bpm: 127.6, key: "Am")), [.bpm: "128", .key: "Am"])
        XCTAssertEqual(TagWritePlanner.desired(self.row(bpm: nil, key: nil, label: "Drumcode")), [.label: "Drumcode"])
        XCTAssertEqual(TagWritePlanner.desired(self.row(bpm: 0, key: "", label: "  ")), [:], "empty values never become tags")
    }

    func testHalfDoubleGuard() {
        var decision = TagWritePlanner.decide(self.row(bpm: 174, key: "Fm"), file: [.bpm: "87", .key: "Fm"])
        XCTAssertTrue(decision.halfDouble)
        XCTAssertEqual(decision.changes, [:])

        decision = TagWritePlanner.decide(self.row(bpm: 87), file: [.bpm: "174"])
        XCTAssertTrue(decision.halfDouble)
        XCTAssertEqual(decision.changes, [.key: "Am"])

        decision = TagWritePlanner.decide(self.row(bpm: 128), file: [.bpm: "64.5", .key: "Am"]) // ratio 0.504
        XCTAssertTrue(decision.halfDouble)

        decision = TagWritePlanner.decide(self.row(bpm: 128), file: [.bpm: "66", .key: "Am"]) // ratio 0.516
        XCTAssertFalse(decision.halfDouble)
        XCTAssertEqual(decision.changes, [.bpm: "128"])
    }

    func testOddBPMTags() {
        var decision = TagWritePlanner.decide(self.row(), file: [.bpm: "12497", .key: "Am"])
        XCTAssertFalse(decision.halfDouble)
        XCTAssertEqual(decision.changes, [.bpm: "128"])

        decision = TagWritePlanner.decide(self.row(), file: [.bpm: "128.00", .key: "Am"])
        XCTAssertEqual(decision, TagWriteDecision(changes: [:], halfDouble: false))

        for odd in ["", "fast"] {
            decision = TagWritePlanner.decide(self.row(), file: [.bpm: odd, .key: "Am"])
            XCTAssertFalse(decision.halfDouble, odd)
            XCTAssertEqual(decision.changes, [.bpm: "128"], odd)
        }
    }

    func testOnlyDifferingFieldsChange() {
        let decision = TagWritePlanner.decide(self.row(label: "Drumcode"), file: [.bpm: "128", .key: " Am ", .label: "Kompakt"])
        XCTAssertEqual(decision.changes, [.label: "Drumcode"])
    }

    func testMissingDesiredNeverClearsTag() {
        let decision = TagWritePlanner.decide(self.row(bpm: nil, key: nil), file: [.bpm: "128", .remixer: "Someone"])
        XCTAssertEqual(decision.changes, [:])
    }

    func testHashStableAndOrderIndependent() {
        let one = TagWritePlanner.hash([.bpm: "128", .key: "Am", .label: "L"])
        let two = TagWritePlanner.hash([.label: "L", .key: "Am", .bpm: "128"])
        XCTAssertEqual(one, two)
        XCTAssertEqual(one.count, 32)
        XCTAssertNotEqual(one, TagWritePlanner.hash([.bpm: "128", .key: "Am", .label: "M"]))
    }

    func testIsDue() {
        XCTAssertTrue(TagWritePlanner.isDue(self.row()))
        let written = TagWritePlanner.hash(TagWritePlanner.desired(self.row()))
        XCTAssertFalse(TagWritePlanner.isDue(self.row(hash: written)))
        XCTAssertTrue(TagWritePlanner.isDue(self.row(label: "New", hash: written)))
    }
}

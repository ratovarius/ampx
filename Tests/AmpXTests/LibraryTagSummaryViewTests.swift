@testable import AmpX
import XCTest

/// The summary shown before tag writing (DJ mode spec Revision 2 § Tag writing).
@MainActor
final class LibraryTagSummaryViewTests: XCTestCase {
    func testLinesFromSummary() {
        let view = LibraryTagSummaryView(skin: ClassicModernSkin())
        view.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        view.show(TagWriteSummary(
            filesToUpdate: 1980, perField: [.bpm: 120, .key: 1900, .label: 1200],
            skippedReadOnly: ["/a.mp3"], unreadable: 2, halfDouble: ["/Music/DJ/DnB/Haggard.mp3", "/Music/DJ/x.mp3"]
        ))
        XCTAssertEqual(view.summaryLines, [
            "1,980 files to update",
            "BPM 120 · KEY 1,900 · LABEL 1,200 · REMIXER 0 · COMPOSER 0 · GROUPING 0",
            "Read-only, skipped: 1",
            "Not readable now: 2",
        ])
        XCTAssertEqual(view.entryLines, [
            "TEMPO HALF OR DOUBLE: CHECK IN REKORDBOX", "/Music/DJ/DnB/Haggard.mp3", "/Music/DJ/x.mp3",
        ])
        XCTAssertEqual(view.writeButton.label, "WRITE TAGS")
        XCTAssertEqual(view.cancelButton.label, "CANCEL")
    }

    func testButtonsAndEscape() {
        let view = LibraryTagSummaryView(skin: ClassicModernSkin())
        var events: [String] = []
        view.onWrite = { events.append("write") }
        view.onCancel = { events.append("cancel") }
        view.writeButton.action?()
        view.cancelButton.action?()
        let escape = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
        )!
        XCTAssertTrue(view.handleKey(escape))
        XCTAssertEqual(events, ["write", "cancel", "cancel"])
    }
}

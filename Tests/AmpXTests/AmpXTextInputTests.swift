@testable import AmpX
import XCTest

/// Custom text field (Library Module spec, UI amendment 4).
@MainActor
final class AmpXTextInputTests: XCTestCase {
    private var changes: [String] = []
    private var commits: [String] = []
    private var escapes = 0

    private func makeInput(mode: AmpXTextInput.Mode = .text) -> AmpXTextInput {
        let input = AmpXTextInput(skin: ClassicModernSkin(), mode: mode, placeholder: "SEARCH")
        input.frame = CGRect(x: 0, y: 0, width: 300, height: 26)
        input.pasteboard = NSPasteboard(name: NSPasteboard.Name("AmpXTextInputTests.\(UUID().uuidString)"))
        input.onChange = { [weak self] in self?.changes.append($0) }
        input.onCommit = { [weak self] in self?.commits.append($0) }
        input.onEscape = { [weak self] in self?.escapes += 1 }
        return input
    }

    private func type(_ text: String, into input: AmpXTextInput) {
        for character in text {
            input.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    func testInsertAndDelete() {
        let input = self.makeInput()
        self.type("techno", into: input)
        XCTAssertEqual(input.committedText, "techno")
        input.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(input.committedText, "techn")
        input.doCommand(by: #selector(NSResponder.moveToBeginningOfLine(_:)))
        input.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        XCTAssertEqual(input.committedText, "echn")
        XCTAssertEqual(self.changes.last, "echn")
        XCTAssertEqual(self.changes.count, 8)
    }

    func testWordMotionAndSelection() {
        let input = self.makeInput()
        self.type("deep organic house", into: input)
        input.doCommand(by: #selector(NSResponder.moveWordLeft(_:)))
        XCTAssertEqual(input.selectedRange(), NSRange(location: 13, length: 0))
        input.doCommand(by: #selector(NSResponder.moveWordLeftAndModifySelection(_:)))
        XCTAssertEqual(input.selectedRange(), NSRange(location: 5, length: 8))
        self.type("x", into: input)
        XCTAssertEqual(input.committedText, "deep xhouse")
        input.doCommand(by: #selector(NSResponder.selectAll(_:)))
        XCTAssertEqual(input.selectedRange(), NSRange(location: 0, length: 11))
    }

    func testMarkedTextDoesNotChangeCommittedValue() {
        let input = self.makeInput()
        self.type("caf", into: input)
        self.changes.removeAll()
        input.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(input.hasMarkedText())
        XCTAssertEqual(input.markedRange(), NSRange(location: 3, length: 1))
        XCTAssertEqual(input.committedText, "caf")
        XCTAssertTrue(self.changes.isEmpty, "marked text is not a committed change")

        input.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(input.hasMarkedText())
        XCTAssertEqual(input.committedText, "café")
        XCTAssertEqual(self.changes, ["café"])
    }

    func testUnmarkCommitsMarkedText() {
        let input = self.makeInput()
        input.setMarkedText(
            "にほん",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(input.committedText, "")
        input.unmarkText()
        XCTAssertEqual(input.committedText, "にほん")
        XCTAssertEqual(self.changes, ["にほん"])
    }

    func testPasteInsertsAtCaret() {
        let input = self.makeInput()
        self.type("ab", into: input)
        input.doCommand(by: #selector(NSResponder.moveLeft(_:)))
        input.pasteboard.clearContents()
        input.pasteboard.setString("XY\nZ", forType: .string)
        input.paste(nil)
        XCTAssertEqual(input.committedText, "aXY Zb", "newlines become spaces in a single-line field")
        input.doCommand(by: #selector(NSResponder.selectAll(_:)))
        input.copy(nil)
        XCTAssertEqual(input.pasteboard.string(forType: .string), "aXY Zb")
        input.cut(nil)
        XCTAssertEqual(input.committedText, "")
    }

    func testEscapeClearsThenResigns() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let input = self.makeInput()
        window.contentView?.addSubview(input)
        XCTAssertTrue(window.makeFirstResponder(input))
        self.type("acid", into: input)
        input.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(input.committedText, "")
        XCTAssertTrue(window.firstResponder === input)
        XCTAssertEqual(self.escapes, 0)
        input.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertFalse(window.firstResponder === input)
        XCTAssertEqual(self.escapes, 1)
    }

    func testClickTakesFocus() {
        let input = self.makeInput()
        XCTAssertTrue(input.acceptsFirstResponder, "a text field takes focus on click, unlike steel controls")
    }

    func testNumericModeRejectsLetters() {
        let input = self.makeInput(mode: .numeric)
        self.type("12a4.5.6", into: input)
        XCTAssertEqual(input.committedText, "124.56")
        XCTAssertEqual(input.numericValue, 124.56)
        input.committedText = ""
        XCTAssertNil(input.numericValue)
    }

    func testCommitOnEnterAndTab() {
        let input = self.makeInput()
        self.type("128", into: input)
        input.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        input.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(self.commits, ["128", "128"])
        XCTAssertEqual(input.committedText, "128", "Enter never inserts a newline")
    }

    func testSettingCommittedTextDoesNotReportChange() {
        let input = self.makeInput()
        input.committedText = "house"
        XCTAssertTrue(self.changes.isEmpty)
        XCTAssertEqual(input.selectedRange(), NSRange(location: 5, length: 0))
    }

    func testAccessibilityValue() {
        let input = self.makeInput()
        self.type("dub", into: input)
        XCTAssertEqual(input.accessibilityRole(), .textField)
        XCTAssertEqual(input.accessibilityValue() as? String, "dub")
        XCTAssertEqual(input.accessibilityPlaceholderValue(), "SEARCH")
    }
}

import AppKit

/// Single-line, custom-drawn text field (Library Module spec, UI amendment 4): an LCD well with green text,
/// a block caret, selection, and IME marked text through `NSTextInputClient`. `NSTextField` stays forbidden.
/// Ranges are UTF-16 offsets into the displayed text, which includes any marked text.
final class AmpXTextInput: AmpXControlView, @preconcurrency NSTextInputClient {
    enum Mode {
        case text
        /// Digits and at most one decimal point.
        case numeric
    }

    let mode: Mode
    let placeholder: String
    /// Committed text changed (typing, deleting, paste, IME commit, Escape clear). Never fired for marked text.
    var onChange: ((String) -> Void)?
    /// Enter or Tab, or losing focus after an edit.
    var onCommit: ((String) -> Void)?
    /// Escape on an empty field, after focus has been resigned.
    var onEscape: (() -> Void)?
    var pasteboard: NSPasteboard = .general
    var fontSize: CGFloat = 13 {
        didSet { needsDisplay = true }
    }

    private var text = ""
    private var markedRangeValue: NSRange?
    private var caret = 0
    private var anchor = 0
    private var scrollX: CGFloat = 0
    private var hasUncommittedEdit = false

    init(skin: any AmpXSkin, mode: Mode = .text, placeholder: String) {
        self.mode = mode
        self.placeholder = placeholder
        super.init(skin: skin)
        self.confinesHitTestingToBounds = true
        setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Value

    /// The text without any marked (composing) text. Setting it moves the caret to the end and reports nothing.
    var committedText: String {
        get { self.committed(from: self.text) }
        set {
            self.text = self.filtered(newValue)
            self.markedRangeValue = nil
            self.caret = self.length
            self.anchor = self.caret
            self.hasUncommittedEdit = false
            needsDisplay = true
        }
    }

    var numericValue: Double? {
        Double(self.committedText)
    }

    private var length: Int {
        (self.text as NSString).length
    }

    private func committed(from text: String) -> String {
        guard let marked = self.markedRangeValue else { return text }
        return (text as NSString).replacingCharacters(in: marked, with: "")
    }

    // MARK: - Focus

    /// Unlike steel controls, a text field takes focus on click.
    override var acceptsFirstResponder: Bool {
        isEnabled
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        needsDisplay = true
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            if self.hasMarkedText() {
                self.unmarkText()
            }
            if self.hasUncommittedEdit {
                self.commit()
            }
            needsDisplay = true
        }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let index = self.index(atX: point.x)
        self.caret = index
        if !event.modifierFlags.contains(.shift) {
            self.anchor = index
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        self.caret = self.index(atX: convert(event.locationInWindow, from: nil).x)
        needsDisplay = true
    }

    // MARK: - Editing core

    private func replace(_ range: NSRange, with string: String) {
        let before = self.committedText
        self.text = (self.text as NSString).replacingCharacters(in: range, with: string)
        self.markedRangeValue = nil
        self.caret = range.location + (string as NSString).length
        self.anchor = self.caret
        needsDisplay = true
        self.reportIfChanged(from: before)
    }

    private func reportIfChanged(from before: String) {
        let after = self.committedText
        guard after != before else { return }
        self.hasUncommittedEdit = true
        self.onChange?(after)
    }

    private var selection: NSRange {
        NSRange(location: min(self.caret, self.anchor), length: abs(self.caret - self.anchor))
    }

    private func filtered(_ string: String, replacing range: NSRange? = nil) -> String {
        let single = string.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard self.mode == .numeric else { return single }
        let remaining = range.map { (self.text as NSString).replacingCharacters(in: $0, with: "") } ?? ""
        var hasPoint = remaining.contains(".")
        return String(single.filter { character in
            if character.isASCII, character.isNumber {
                return true
            }
            if character == ".", !hasPoint {
                hasPoint = true
                return true
            }
            return false
        })
    }

    private func commit() {
        self.hasUncommittedEdit = false
        self.onCommit?(self.committedText)
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let raw = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        let target = replacementRange.location != NSNotFound ? replacementRange : (self.markedRangeValue ?? self.selection)
        let before = self.committedText
        let inserted = self.filtered(raw, replacing: target)
        self.text = (self.text as NSString).replacingCharacters(in: target, with: inserted)
        self.markedRangeValue = nil
        self.caret = target.location + (inserted as NSString).length
        self.anchor = self.caret
        needsDisplay = true
        self.reportIfChanged(from: before)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let raw = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        let target = replacementRange.location != NSNotFound ? replacementRange : (self.markedRangeValue ?? self.selection)
        self.text = (self.text as NSString).replacingCharacters(in: target, with: raw)
        let markedLength = (raw as NSString).length
        self.markedRangeValue = markedLength > 0 ? NSRange(location: target.location, length: markedLength) : nil
        self.anchor = target.location + min(selectedRange.location, markedLength)
        self.caret = self.anchor + min(selectedRange.length, markedLength - min(selectedRange.location, markedLength))
        needsDisplay = true
    }

    func unmarkText() {
        guard self.markedRangeValue != nil else { return }
        let before = self.committedText
        self.markedRangeValue = nil
        needsDisplay = true
        self.reportIfChanged(from: before)
    }

    func selectedRange() -> NSRange {
        self.selection
    }

    func markedRange() -> NSRange {
        self.markedRangeValue ?? NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        self.markedRangeValue != nil
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: self.length))
        actualRange?.pointee = clamped
        return NSAttributedString(string: (self.text as NSString).substring(with: clamped))
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        let x = self.xOffset(forIndex: min(range.location, self.length))
        let local = CGRect(x: x, y: 0, width: 1, height: bounds.height)
        guard let window else { return local }
        return window.convertToScreen(convert(local, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        guard let window else { return NSNotFound }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        return self.index(atX: local.x)
    }

    override func doCommand(by selector: Selector) {
        if responds(to: selector) {
            perform(selector, with: nil)
        }
    }

    // MARK: - Commands

    override func insertNewline(_: Any?) {
        self.commit()
    }

    override func insertTab(_: Any?) {
        self.commit()
        window?.selectNextKeyView(nil)
    }

    override func insertBacktab(_: Any?) {
        self.commit()
        window?.selectPreviousKeyView(nil)
    }

    override func cancelOperation(_: Any?) {
        if !self.committedText.isEmpty {
            self.replace(NSRange(location: 0, length: self.length), with: "")
            return
        }
        window?.makeFirstResponder(nil)
        self.onEscape?()
    }

    override func deleteBackward(_: Any?) {
        let range = self.selection
        if range.length > 0 {
            self.replace(range, with: "")
        } else if self.caret > 0 {
            self.replace((self.text as NSString).rangeOfComposedCharacterSequence(at: self.caret - 1), with: "")
        }
    }

    override func deleteForward(_: Any?) {
        let range = self.selection
        if range.length > 0 {
            self.replace(range, with: "")
        } else if self.caret < self.length {
            self.replace((self.text as NSString).rangeOfComposedCharacterSequence(at: self.caret), with: "")
        }
    }

    override func moveLeft(_: Any?) {
        self.move(to: self.selection.length > 0 ? self.selection.location : self.previousIndex(self.caret), extend: false)
    }

    override func moveRight(_: Any?) {
        self.move(to: self.selection.length > 0 ? NSMaxRange(self.selection) : self.nextIndex(self.caret), extend: false)
    }

    override func moveLeftAndModifySelection(_: Any?) {
        self.move(to: self.previousIndex(self.caret), extend: true)
    }

    override func moveRightAndModifySelection(_: Any?) {
        self.move(to: self.nextIndex(self.caret), extend: true)
    }

    override func moveWordLeft(_: Any?) {
        self.move(to: self.wordStart(before: self.caret), extend: false)
    }

    override func moveWordRight(_: Any?) {
        self.move(to: self.wordEnd(after: self.caret), extend: false)
    }

    override func moveWordLeftAndModifySelection(_: Any?) {
        self.move(to: self.wordStart(before: self.caret), extend: true)
    }

    override func moveWordRightAndModifySelection(_: Any?) {
        self.move(to: self.wordEnd(after: self.caret), extend: true)
    }

    override func moveToBeginningOfLine(_: Any?) {
        self.move(to: 0, extend: false)
    }

    override func moveToEndOfLine(_: Any?) {
        self.move(to: self.length, extend: false)
    }

    override func moveToBeginningOfLineAndModifySelection(_: Any?) {
        self.move(to: 0, extend: true)
    }

    override func moveToEndOfLineAndModifySelection(_: Any?) {
        self.move(to: self.length, extend: true)
    }

    override func moveUp(_: Any?) {
        self.move(to: 0, extend: false)
    }

    override func moveDown(_: Any?) {
        self.move(to: self.length, extend: false)
    }

    override func selectAll(_: Any?) {
        self.anchor = 0
        self.caret = self.length
        needsDisplay = true
    }

    @objc func copy(_: Any?) {
        guard self.selection.length > 0 else { return }
        self.pasteboard.clearContents()
        self.pasteboard.setString((self.text as NSString).substring(with: self.selection), forType: .string)
    }

    @objc func cut(_: Any?) {
        guard self.selection.length > 0 else { return }
        self.copy(nil)
        self.replace(self.selection, with: "")
    }

    @objc func paste(_: Any?) {
        guard let string = self.pasteboard.string(forType: .string) else { return }
        self.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func move(to index: Int, extend: Bool) {
        self.caret = max(0, min(index, self.length))
        if !extend {
            self.anchor = self.caret
        }
        needsDisplay = true
    }

    private func previousIndex(_ index: Int) -> Int {
        index > 0 ? (self.text as NSString).rangeOfComposedCharacterSequence(at: index - 1).location : 0
    }

    private func nextIndex(_ index: Int) -> Int {
        index < self.length ? NSMaxRange((self.text as NSString).rangeOfComposedCharacterSequence(at: index)) : self.length
    }

    private func wordStart(before index: Int) -> Int {
        let units = Array((self.text as NSString).substring(to: index).utf16)
        var position = units.count
        while position > 0, Self.isSpace(units[position - 1]) {
            position -= 1
        }
        while position > 0, !Self.isSpace(units[position - 1]) {
            position -= 1
        }
        return position
    }

    private func wordEnd(after index: Int) -> Int {
        let units = Array(self.text.utf16)
        var position = index
        while position < units.count, Self.isSpace(units[position]) {
            position += 1
        }
        while position < units.count, !Self.isSpace(units[position]) {
            position += 1
        }
        return position
    }

    private static func isSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09
    }

    // MARK: - Drawing

    private var inset: CGFloat {
        6
    }

    private var font: NSFont {
        skin.font(size: self.fontSize, weight: .regular)
    }

    private func width(of string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: self.font]).width
    }

    private func xOffset(forIndex index: Int) -> CGFloat {
        self.inset - self.scrollX + self.width(of: (self.text as NSString).substring(to: index))
    }

    private func index(atX x: CGFloat) -> Int {
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var index = 0
        while index <= self.length {
            let distance = abs(self.xOffset(forIndex: index) - x)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
            if index == self.length {
                break
            }
            index = self.nextIndex(index)
        }
        return best
    }

    private var caretWidth: CGFloat {
        max(2, self.width(of: "0"))
    }

    /// Keeps the caret inside the visible width by scrolling the text horizontally.
    private func updateScroll() {
        let caretX = self.width(of: (self.text as NSString).substring(to: self.caret))
        let visible = bounds.width - self.inset * 2 - self.caretWidth
        if caretX - self.scrollX > visible {
            self.scrollX = caretX - visible
        } else if caretX < self.scrollX {
            self.scrollX = caretX
        }
        self.scrollX = max(0, self.scrollX)
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        self.updateScroll()
        let well = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = CGPath(roundedRect: well, cornerWidth: 2, cornerHeight: 2, transform: nil)
        context.addPath(path)
        context.setFillColor(skin.display.cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(skin.borderDark.cgColor)
        context.setLineWidth(1)
        context.strokePath()

        context.saveGState()
        context.clip(to: bounds.insetBy(dx: 2, dy: 2))
        let focused = window?.firstResponder === self
        let baseline = bounds.midY + self.font.capHeight / 2
        if self.text.isEmpty {
            AmpXLabel(text: self.placeholder, color: skin.textDim, fontSize: self.fontSize - 2)
                .draw(x: self.inset, baseline: baseline - 1, context: context, skin: skin)
        }

        if focused, self.selection.length > 0 {
            let start = self.xOffset(forIndex: self.selection.location)
            let end = self.xOffset(forIndex: NSMaxRange(self.selection))
            context.setFillColor(skin.selection.cgColor)
            context.fill(CGRect(x: start, y: 4, width: end - start, height: bounds.height - 8))
        }

        AmpXLabel(text: self.text, color: skin.green, fontSize: self.fontSize)
            .draw(x: self.inset - self.scrollX, baseline: baseline, context: context, skin: skin)

        if let marked = self.markedRangeValue {
            let start = self.xOffset(forIndex: marked.location)
            let end = self.xOffset(forIndex: NSMaxRange(marked))
            context.setFillColor(skin.green.cgColor)
            context.fill(CGRect(x: start, y: baseline + 2, width: end - start, height: 1))
        }

        if focused, self.selection.length == 0 {
            let x = self.xOffset(forIndex: self.caret)
            context.setFillColor(skin.green.withAlphaComponent(0.85).cgColor)
            context.fill(CGRect(x: x, y: 5, width: self.caretWidth, height: bounds.height - 10))
        }
        context.restoreGState()
    }

    // MARK: - Accessibility

    override func accessibilityRole() -> NSAccessibility.Role? {
        .textField
    }

    override func accessibilityValue() -> Any? {
        self.committedText
    }

    override func accessibilityPlaceholderValue() -> String? {
        self.placeholder
    }

    override func setAccessibilityValue(_ accessibilityValue: Any?) {
        guard let string = accessibilityValue as? String else { return }
        let before = self.committedText
        self.committedText = string
        self.reportIfChanged(from: before)
    }
}

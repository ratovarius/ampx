import AppKit

/// Toolbar row (Library Module spec § Layout): search, BPM range (min – max, ✕) and CLEAR.
final class LibraryToolbarView: AmpXDrawingView {
    static let height: CGFloat = 32

    let search: AmpXTextInput
    let bpmMin: AmpXTextInput
    let bpmMax: AmpXTextInput
    let clearBpmButton: AmpXButton
    let clearButton: AmpXButton

    var onSearch: ((String) -> Void)?
    var onBpm: ((Double?, Double?) -> Void)?
    var onClear: (() -> Void)?

    private static let bpmFieldWidth: CGFloat = 54
    private static let bpmLabelWidth: CGFloat = 36
    private static let dashWidth: CGFloat = 14

    override init(skin: any AmpXSkin) {
        self.search = AmpXTextInput(skin: skin, placeholder: "SEARCH ARTIST, TITLE, ALBUM")
        self.bpmMin = AmpXTextInput(skin: skin, mode: .numeric, placeholder: "MIN")
        self.bpmMax = AmpXTextInput(skin: skin, mode: .numeric, placeholder: "MAX")
        self.clearBpmButton = AmpXButton(skin: skin)
        self.clearButton = AmpXButton(skin: skin)
        super.init(skin: skin)
        self.search.setAccessibilityLabel("Search library")
        self.bpmMin.setAccessibilityLabel("Minimum BPM")
        self.bpmMax.setAccessibilityLabel("Maximum BPM")
        self.clearBpmButton.label = "✕"
        self.clearBpmButton.accessibilityTitle = "Clear BPM range"
        self.clearButton.label = "CLEAR"
        self.clearButton.applyKeyLabelStyle()
        self.clearBpmButton.applyKeyLabelStyle()
        for view in [self.search, self.bpmMin, self.bpmMax, self.clearBpmButton, self.clearButton] as [NSView] {
            addSubview(view)
        }
        self.search.onChange = { [weak self] in self?.onSearch?($0) }
        self.bpmMin.onCommit = { [weak self] _ in self?.reportBpm() }
        self.bpmMax.onCommit = { [weak self] _ in self?.reportBpm() }
        self.clearBpmButton.action = { [weak self] in
            guard let self else { return }
            self.bpmMin.committedText = ""
            self.bpmMax.committedText = ""
            self.reportBpm()
        }
        self.clearButton.action = { [weak self] in self?.onClear?() }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func reportBpm() {
        self.onBpm?(self.bpmMin.numericValue, self.bpmMax.numericValue)
    }

    /// Shows `state` without reporting changes; fields keep their text when it already matches.
    func apply(_ state: LibraryFilterState) {
        if self.search.committedText != state.search {
            self.search.committedText = state.search
        }
        let minText = state.bpmMin.map(Self.bpmText) ?? ""
        if self.bpmMin.numericValue != state.bpmMin {
            self.bpmMin.committedText = minText
        }
        let maxText = state.bpmMax.map(Self.bpmText) ?? ""
        if self.bpmMax.numericValue != state.bpmMax {
            self.bpmMax.committedText = maxText
        }
    }

    private static func bpmText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        let fieldHeight: CGFloat = 26
        let y = (height - fieldHeight) / 2
        let clearWidth: CGFloat = 64
        let gap: CGFloat = 6
        var x = bounds.width - clearWidth
        self.clearButton.frame = CGRect(x: x, y: y, width: clearWidth, height: fieldHeight)
        x -= gap + fieldHeight
        self.clearBpmButton.frame = CGRect(x: x, y: y, width: fieldHeight, height: fieldHeight)
        x -= gap + Self.bpmFieldWidth
        self.bpmMax.frame = CGRect(x: x, y: y, width: Self.bpmFieldWidth, height: fieldHeight)
        x -= Self.dashWidth + Self.bpmFieldWidth
        self.bpmMin.frame = CGRect(x: x, y: y, width: Self.bpmFieldWidth, height: fieldHeight)
        x -= Self.bpmLabelWidth + gap
        self.search.frame = CGRect(x: 0, y: y, width: max(0, x), height: fieldHeight)
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let baseline = bounds.midY + 4
        AmpXLabel(text: "BPM", color: skin.text, fontSize: 12, weight: .medium)
            .draw(x: self.bpmMin.frame.minX - Self.bpmLabelWidth + 4, baseline: baseline, context: context, skin: skin)
        AmpXLabel(text: "–", color: skin.text, fontSize: 12)
            .draw(x: self.bpmMin.frame.maxX + 3, baseline: baseline, context: context, skin: skin)
    }
}

import AppKit

/// MIXES WELL sidebar (Library Module spec § MIXES WELL in L2): the PLAYING | SELECTED switch persists, the
/// reference card follows it, and the list is a placeholder until DJ mode fills it. + QUEUE stays disabled.
final class LibraryMixesSidebarView: AmpXDrawingView {
    static let width: CGFloat = 260
    let placeholderText = "Recommendations arrive with DJ mode (BPM & key analysis)."

    let playingButton: AmpXButton
    let selectedButton: AmpXButton
    let queueButton: AmpXButton
    var onModeChange: ((Bool) -> Void)?

    private(set) var referenceText = "No track"
    var followsSelection = false {
        didSet {
            self.playingButton.isActive = !self.followsSelection
            self.selectedButton.isActive = self.followsSelection
        }
    }

    private static let titleHeight: CGFloat = 26
    private static let cardHeight: CGFloat = 46

    override init(skin: any AmpXSkin) {
        self.playingButton = AmpXButton(skin: skin)
        self.selectedButton = AmpXButton(skin: skin)
        self.queueButton = AmpXButton(skin: skin)
        super.init(skin: skin)
        self.playingButton.label = "PLAYING"
        self.selectedButton.label = "SELECTED"
        self.queueButton.label = "+ QUEUE"
        self.queueButton.isEnabled = false
        for button in [self.playingButton, self.selectedButton, self.queueButton] {
            button.applyKeyLabelStyle()
            addSubview(button)
        }
        self.playingButton.isActive = true
        self.playingButton.action = { [weak self] in self?.setMode(followsSelection: false) }
        self.selectedButton.action = { [weak self] in self?.setMode(followsSelection: true) }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Mixes well")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setMode(followsSelection: Bool) {
        guard followsSelection != self.followsSelection else { return }
        self.followsSelection = followsSelection
        self.onModeChange?(followsSelection)
    }

    func updateReference(_ row: LibraryRow?) {
        guard let row else {
            self.referenceText = "No track"
            needsDisplay = true
            return
        }
        var parts = ["\(row.artist) – \(row.title)"]
        if let bpm = row.bpm {
            parts.append("\(Int(bpm.rounded())) BPM")
        }
        if let key = row.musicalKey {
            parts.append(key)
        }
        self.referenceText = parts.joined(separator: " · ")
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let buttonHeight: CGFloat = 22
        self.selectedButton.frame = CGRect(x: bounds.width - 86, y: 2, width: 84, height: buttonHeight)
        self.playingButton.frame = CGRect(x: bounds.width - 86 - 78, y: 2, width: 76, height: buttonHeight)
        self.queueButton.frame = CGRect(x: 6, y: bounds.height - 34, width: bounds.width - 12, height: 28)
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(skin.display.cgColor)
        context.fill(bounds)
        context.setFillColor(skin.panel.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: Self.titleHeight))
        AmpXLabel(text: "MIXES WELL", color: skin.text, fontSize: 12, weight: .medium)
            .draw(x: 6, baseline: Self.titleHeight / 2 + 4, context: context, skin: skin)

        let card = CGRect(x: 6, y: Self.titleHeight + 6, width: bounds.width - 12, height: Self.cardHeight)
        context.setStrokeColor(skin.borderDark.cgColor)
        context.stroke(card.insetBy(dx: 0.5, dy: 0.5))
        let reference = LibraryTrackTableView.fittedText(self.referenceText, width: card.width - 12, skin: skin)
        AmpXLabel(text: reference, color: skin.green, fontSize: 12)
            .draw(x: card.minX + 6, baseline: card.midY + 4, context: context, skin: skin)

        let message = CGRect(x: 12, y: card.maxY + 16, width: bounds.width - 24, height: 60)
        AmpXLabel(text: self.placeholderText, color: skin.textDim, fontSize: 11)
            .draw(in: message, context: context, skin: skin)
    }
}

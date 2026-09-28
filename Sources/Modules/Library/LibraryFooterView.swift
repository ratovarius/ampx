import AppKit

/// Footer row (Library Module spec § Layout): result summary LCD, scan status LED, n MISSING, ROOTS ▾, ENQUEUE.
final class LibraryFooterView: AmpXDrawingView {
    static let height: CGFloat = 34

    let missingButton: AmpXButton
    let rootsButton: AmpXButton
    let enqueueButton: AmpXButton
    /// rekordbox sync indicator; hidden unless a library folder has a rekordbox export.
    let rekordboxButton: AmpXButton
    var onToggleMissing: (() -> Void)?
    var onRekordboxClick: (() -> Void)?
    var onEnqueue: (() -> Void)?

    private(set) var summaryText = "0 TRACKS · 0:00:00"
    private(set) var statusText = "UP TO DATE"
    private var isScanning = false

    override init(skin: any AmpXSkin) {
        self.missingButton = AmpXButton(skin: skin)
        self.rootsButton = AmpXButton(skin: skin)
        self.enqueueButton = AmpXButton(skin: skin)
        self.rekordboxButton = AmpXButton(skin: skin)
        super.init(skin: skin)
        self.rekordboxButton.isHidden = true
        self.rootsButton.label = "ROOTS"
        self.rootsButton.style = .menu
        self.enqueueButton.label = "ENQUEUE"
        self.missingButton.showsActiveIndicator = true
        self.missingButton.isHidden = true
        for button in [self.missingButton, self.rekordboxButton, self.rootsButton, self.enqueueButton] {
            button.applyKeyLabelStyle()
            addSubview(button)
        }
        self.missingButton.action = { [weak self] in self?.onToggleMissing?() }
        self.enqueueButton.action = { [weak self] in self?.onEnqueue?() }
        self.rekordboxButton.action = { [weak self] in self?.onRekordboxClick?() }
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// nil hides the indicator: `.hidden` means no library folder has a rekordbox export.
    static func rekordboxText(_ status: RekordboxSyncStatus, now: Date = Date(), calendar: Calendar = .current) -> String? {
        switch status {
        case .hidden: nil
        case .syncing: "REKORDBOX SYNCING"
        case let .idle(lastSync):
            lastSync.map { "REKORDBOX " + LibraryFormatting.syncTime($0, now: now, calendar: calendar).uppercased() } ?? "REKORDBOX"
        }
    }

    func update(
        trackCount: Int,
        totalDuration: Double,
        progress: ScanProgress?,
        missing: Int,
        showingMissing: Bool,
        rekordbox: RekordboxSyncStatus = .hidden
    ) {
        let rekordboxText = Self.rekordboxText(rekordbox)
        self.rekordboxButton.isHidden = rekordboxText == nil
        self.rekordboxButton.label = rekordboxText ?? ""
        needsLayout = true
        let noun = trackCount == 1 ? "TRACK" : "TRACKS"
        self.summaryText = "\(LibraryFormatting.grouped(trackCount)) \(noun) · \(LibraryFormatting.longDuration(totalDuration))"
        if let progress {
            self.isScanning = true
            self.statusText = progress.total > 0
                ? "SCANNING \(LibraryFormatting.grouped(progress.done)) / \(LibraryFormatting.grouped(progress.total))"
                : "SCANNING…"
        } else {
            self.isScanning = false
            self.statusText = "UP TO DATE"
        }
        self.missingButton.isHidden = missing == 0
        self.missingButton.label = "\(LibraryFormatting.grouped(missing)) MISSING"
        self.missingButton.isActive = showingMissing
        needsDisplay = true
    }

    private var summaryRect: CGRect {
        CGRect(x: 0, y: 3, width: max(0, bounds.width * 0.32), height: bounds.height - 6)
    }

    override func layout() {
        super.layout()
        let height: CGFloat = 28
        let y = (bounds.height - height) / 2
        var x = bounds.width
        let buttons = [(self.enqueueButton, CGFloat(96)), (self.rootsButton, 96), (self.rekordboxButton, 150), (self.missingButton, 120)]
        for (button, width) in buttons where !button.isHidden {
            x -= width
            button.frame = CGRect(x: x, y: y, width: width, height: height)
            x -= 6
        }
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let well = self.summaryRect
        let path = CGPath(roundedRect: well, cornerWidth: 2, cornerHeight: 2, transform: nil)
        context.addPath(path)
        context.setFillColor(skin.display.cgColor)
        context.fillPath()
        let baseline = well.midY + 5
        AmpXLabel(text: self.summaryText, color: skin.green, fontSize: 14)
            .draw(x: well.minX + 10, baseline: baseline, context: context, skin: skin)

        let ledX = well.maxX + 16
        let led = CGRect(x: ledX, y: bounds.midY - 4, width: 8, height: 8)
        context.setFillColor((self.isScanning ? skin.orange : skin.green).cgColor)
        context.fill(led)
        // The status yields to the buttons at narrow widths (rekordbox indicator plus MISSING at 910 pt).
        let buttonsStart = [self.missingButton, self.rekordboxButton, self.rootsButton, self.enqueueButton]
            .filter { !$0.isHidden }.map(\.frame.minX).min() ?? bounds.width
        let status = LibraryTrackTableView.fittedText(self.statusText, width: max(0, buttonsStart - led.maxX - 16), skin: skin)
        AmpXLabel(text: status, color: skin.text, fontSize: 12, weight: .medium)
            .draw(x: led.maxX + 8, baseline: bounds.midY + 4, context: context, skin: skin)
    }
}

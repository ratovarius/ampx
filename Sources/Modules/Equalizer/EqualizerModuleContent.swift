import AppKit
import Combine
import CoreGraphics

/// Display-only EQ values for deterministic reference captures. Never written to audio or saved settings.
struct EqualizerReferencePresentation: Equatable {
    var bandDecibels: [Double]
    var preampDecibels: Double
    var isEnabled: Bool
    var isAutoEnabled: Bool
}

final class EqualizerModuleContent: AmpXModuleContent {
    private static let decibelRange: ClosedRange<Double> = -12 ... 12

    private let audioPlayer: AudioPlayer
    private let onToggle: AmpXButton
    private let autoToggle: AmpXButton
    private let presetsButton: AmpXButton
    private let preampSlider: AmpXSlider
    private let curveView: EQCurveView
    private var bandSliders: [AmpXSlider] = []
    private var cancellables = Set<AnyCancellable>()
    private let presetsMenuTarget = EQPresetsMenuTarget()

    /// When set, rendering uses these values instead of live EQ state.
    var referencePresentation: EqualizerReferencePresentation? {
        didSet { self.applyReferencePresentation() }
    }

    init(skin: any AmpXSkin, audioPlayer: AudioPlayer) {
        self.audioPlayer = audioPlayer
        self.onToggle = AmpXButton(skin: skin)
        self.autoToggle = AmpXButton(skin: skin)
        self.presetsButton = AmpXButton(skin: skin)
        self.preampSlider = AmpXSlider(skin: skin)
        self.curveView = EQCurveView(skin: skin)
        super.init(skin: skin)
        self.presetsMenuTarget.audioPlayer = audioPlayer
        self.configureControls()
        self.bindModels()
        self.refreshControlState(animated: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureControls() {
        self.configureToggle(self.onToggle, label: "ON", indicator: AmpXMetrics.eqOnIndicator, labelInk: AmpXMetrics.eqOnLabelInk)
        self.onToggle.accessibilityTitle = "Equalizer on"
        self.onToggle.action = { [weak audioPlayer] in
            guard let audioPlayer else { return }
            audioPlayer.setEQEnabled(!audioPlayer.eqEnabled)
        }

        self.configureToggle(self.autoToggle, label: "AUTO", indicator: AmpXMetrics.eqAutoIndicator, labelInk: AmpXMetrics.eqAutoLabelInk)
        self.autoToggle.accessibilityTitle = "Equalizer auto"
        self.autoToggle.action = { [weak audioPlayer] in
            guard let audioPlayer else { return }
            audioPlayer.setEQAutoEnabled(!audioPlayer.eqAutoEnabled)
        }

        self.presetsButton.label = "PRESETS"
        self.presetsButton.applyKeyLabelStyle()
        self.presetsButton.labelBaselineOrigin = Self.labelOrigin(
            "PRESETS", inkX: AmpXMetrics.eqPresetsLabelInk.x, baseline: AmpXMetrics.eqPresetsLabelInk.y, skin: skin
        )
        self.presetsButton.icon = .dropdown
        self.presetsButton.iconColor = skin.faceInk
        self.presetsButton.iconRect = AmpXMetrics.eqPresetsTriangle
        self.presetsButton.accessibilityTitle = "Equalizer presets"
        self.presetsButton.action = { [weak self] in
            self?.showPresetsMenu()
        }

        self.configureLevelSlider(self.preampSlider, title: "Preamp")
        self.preampSlider.onChange = { [weak audioPlayer] db in
            audioPlayer?.setEQPreamp(EQValueMapping.normalized(decibels: Float(db)))
        }

        for index in 0 ..< AmpXEQBands.bandCount {
            let slider = AmpXSlider(skin: skin)
            self.configureLevelSlider(slider, title: "\(AmpXEQBands.displayLabels[index]) band")
            slider.onChange = { [weak audioPlayer] db in
                audioPlayer?.setEQBand(index, gain: Float(db))
            }
            self.bandSliders.append(slider)
            addSubview(slider)
        }

        for control in [self.curveView, self.onToggle, self.autoToggle, self.presetsButton, self.preampSlider] {
            addSubview(control)
        }
        self.layoutControls()
    }

    private func configureToggle(_ button: AmpXButton, label: String, indicator: CGRect, labelInk: CGPoint) {
        button.label = label
        button.applyKeyLabelStyle()
        button.labelBaselineOrigin = Self.labelOrigin(label, inkX: labelInk.x, baseline: labelInk.y, skin: skin)
        button.showsActiveIndicator = true
        button.indicatorRect = indicator
    }

    private func configureLevelSlider(_ slider: AmpXSlider, title: String) {
        slider.isVertical = true
        slider.range = Self.decibelRange
        slider.step = 1
        slider.artwork = .level
        slider.trackSize = AmpXMetrics.eqSliderSlotSize
        slider.thumbSize = AmpXMetrics.eqSliderThumbSize
        slider.travelLength = AmpXMetrics.eqSliderTravel
        slider.accessibilityTitle = title
    }

    private static func labelOrigin(_ text: String, inkX: CGFloat, baseline: CGFloat, skin: any AmpXSkin) -> CGPoint {
        let ink = AmpXLabel(text: text, color: skin.text, fontSize: AmpXMetrics.keyLabelFontSize, weight: AmpXButton.keyLabelWeight)
            .inkBounds(skin: skin)
        return CGPoint(x: inkX - ink.minX, y: baseline)
    }

    private func bindModels() {
        self.audioPlayer.$eqEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.onToggle.isActive = enabled
            }
            .store(in: &self.cancellables)

        self.audioPlayer.$eqAutoEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.autoToggle.isActive = enabled
            }
            .store(in: &self.cancellables)

        self.audioPlayer.$eqBandValues
            .receive(on: DispatchQueue.main)
            .sink { [weak self] values in
                self?.updateBandSliders(from: values)
                self?.updateCurve(animated: true)
            }
            .store(in: &self.cancellables)

        self.audioPlayer.$eqPreampValue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] normalized in
                self?.updatePreampSlider(from: normalized)
                self?.updateCurve(animated: true)
            }
            .store(in: &self.cancellables)

        self.audioPlayer.$eqPresetsRevision
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.presetsMenuTarget.presets = self?.audioPlayer.eqPresets() ?? []
            }
            .store(in: &self.cancellables)
    }

    private func refreshControlState(animated: Bool) {
        self.onToggle.isActive = self.audioPlayer.eqEnabled
        self.autoToggle.isActive = self.audioPlayer.eqAutoEnabled
        self.updateBandSliders(from: self.audioPlayer.eqBandValues)
        self.updatePreampSlider(from: self.audioPlayer.eqPreampValue)
        self.presetsMenuTarget.presets = self.audioPlayer.eqPresets()
        self.updateCurve(animated: animated)
    }

    private func applyReferencePresentation() {
        let reference = self.referencePresentation
        self.onToggle.displayActiveOverride = reference?.isEnabled
        self.autoToggle.displayActiveOverride = reference?.isAutoEnabled
        self.preampSlider.displayValueOverride = reference?.preampDecibels
        for (index, slider) in self.bandSliders.enumerated() {
            slider.displayValueOverride = reference.flatMap { index < $0.bandDecibels.count ? $0.bandDecibels[index] : nil }
        }
        self.curveView.reference = reference.map {
            EQCurveView.Reference(
                bandValues: $0.bandDecibels.map { EQValueMapping.normalized(decibels: Float($0)) },
                preampValue: EQValueMapping.normalized(decibels: Float($0.preampDecibels))
            )
        }
        needsDisplay = true
    }

    private func updateBandSliders(from values: [Float]) {
        for index in 0 ..< self.bandSliders.count where index < values.count {
            let db = EQValueMapping.decibels(normalized: values[index])
            bandSliders[index].setValue(Double(db), sendChange: false)
        }
    }

    private func updatePreampSlider(from normalized: Float) {
        let db = EQValueMapping.decibels(normalized: normalized)
        self.preampSlider.setValue(Double(db), sendChange: false)
    }

    private func updateCurve(animated: Bool) {
        self.curveView.setCurve(
            bandValues: self.audioPlayer.eqBandValues,
            preampValue: self.audioPlayer.eqPreampValue,
            animated: animated
        )
    }

    private func showPresetsMenu() {
        let menu = NSMenu()
        for preset in self.audioPlayer.eqPresets() {
            let item = NSMenuItem(
                title: preset.name,
                action: #selector(EQPresetsMenuTarget.applyPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self.presetsMenuTarget
            item.representedObject = preset
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let loadItem = NSMenuItem(
            title: "Load EQF…",
            action: #selector(EQPresetsMenuTarget.loadEQF(_:)),
            keyEquivalent: ""
        )
        loadItem.target = self.presetsMenuTarget
        menu.addItem(loadItem)
        let resetItem = NSMenuItem(
            title: "Reset",
            action: #selector(EQPresetsMenuTarget.resetEQ(_:)),
            keyEquivalent: ""
        )
        resetItem.target = self.presetsMenuTarget
        menu.addItem(resetItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: self.presetsButton.bounds.height), in: self.presetsButton)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        self.layoutControls()
    }

    // MARK: - Layout

    static func sliderFrame(centerX: CGFloat) -> CGRect {
        let thumb = AmpXMetrics.eqSliderThumbSize
        let height = AmpXMetrics.eqSliderTravel + thumb.height
        return CGRect(
            x: centerX - thumb.width / 2,
            y: AmpXMetrics.eqSliderSlotCenterY - height / 2,
            width: thumb.width,
            height: height
        )
    }

    private func layoutControls() {
        self.onToggle.frame = AmpXMetrics.eqOnToggle
        self.autoToggle.frame = AmpXMetrics.eqAutoToggle
        self.presetsButton.frame = AmpXMetrics.eqPresetsButton
        self.curveView.frame = AmpXMetrics.eqCurveFrame
        self.preampSlider.frame = Self.sliderFrame(centerX: AmpXMetrics.eqPreampCenterX)
        for (index, slider) in self.bandSliders.enumerated() {
            slider.frame = Self.sliderFrame(centerX: AmpXMetrics.eqBandCenterX[index])
        }
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        self.drawCurveGrid(in: context)
        self.drawScaleTicks(in: context)
        self.drawDecibelLabels(in: context)
        self.drawSliderLabels(in: context)
    }

    private func drawCurveGrid(in context: CGContext) {
        let frame = AmpXMetrics.eqCurveFrame
        // A grid line under each band knot, plus the graph's two edges.
        let bandKnots = EQCurveView.knotPoints(
            bandValues: Array(repeating: 0, count: AmpXEQBands.bandCount),
            size: frame.size
        )
        let knots = [CGPoint(x: 0, y: 0)] + bandKnots + [CGPoint(x: frame.width, y: 0)]
        let height = AmpXMetrics.eqGridMaxY - AmpXMetrics.eqGridMinY
        // Dark, mid and light half-point columns sampled across a reference grid line.
        let columns: [(offset: CGFloat, color: NSColor)] = [
            (-0.5, NSColor(srgbRed: 21 / 255, green: 31 / 255, blue: 48 / 255, alpha: 1)),
            (0, NSColor(srgbRed: 40 / 255, green: 53 / 255, blue: 78 / 255, alpha: 1)),
            (0.5, NSColor(srgbRed: 66 / 255, green: 84 / 255, blue: 116 / 255, alpha: 1)),
        ]
        for knot in knots {
            let x = frame.minX + knot.x
            for column in columns {
                context.setFillColor(column.color.cgColor)
                context.fill(CGRect(x: x + column.offset - 0.25, y: AmpXMetrics.eqGridMinY, width: 0.5, height: height))
            }
        }
    }

    /// Horizontal ±12/0 dB dashes between sliders at the thumb-center rows, plus slot end marks.
    private func drawScaleTicks(in context: CGContext) {
        let tickColor = NSColor(srgbRed: 170 / 255, green: 180 / 255, blue: 196 / 255, alpha: 1)
        let markColor = NSColor(srgbRed: 58 / 255, green: 70 / 255, blue: 90 / 255, alpha: 1)
        let centers = AmpXMetrics.eqBandCenterX
        var tickXs = [
            AmpXMetrics.eqPreampCenterX - AmpXMetrics.eqPreampTickOffset,
            AmpXMetrics.eqPreampCenterX + AmpXMetrics.eqPreampTickOffset,
            centers[0] - AmpXMetrics.eqOuterBandTickOffset,
            centers[centers.count - 1] + AmpXMetrics.eqOuterBandTickOffset,
        ]
        tickXs += zip(centers, centers.dropFirst()).map { ($0 + $1) / 2 }

        for value in [12.0, 0, -12] {
            let y = self.preampSlider.convert(self.preampSlider.thumbRect(forValue: value), to: self).midY
            context.setFillColor(tickColor.cgColor)
            for x in tickXs {
                context.fill(CGRect(x: x - AmpXMetrics.eqTickWidth / 2, y: y - 0.5, width: AmpXMetrics.eqTickWidth, height: 1))
            }
        }

        context.setFillColor(markColor.cgColor)
        for slider in [self.preampSlider] + self.bandSliders {
            let slot = slider.convert(slider.trackRect, to: self)
            context.fill(CGRect(x: slot.midX - 0.5, y: slot.minY - 3, width: 1, height: 2.5))
            context.fill(CGRect(x: slot.midX - 0.5, y: slot.maxY + 0.5, width: 1, height: 2.5))
        }
    }

    private func drawDecibelLabels(in context: CGContext) {
        for (text, baseline) in zip(["+12 dB", "0 dB", "-12 dB"], AmpXMetrics.eqDecibelLabelBaselines) {
            AmpXLabel(text: text, color: skin.yellow, fontSize: 11.5, weight: .regular, alignment: .center)
                .draw(x: AmpXMetrics.eqDecibelLabelCenterX, baseline: baseline, context: context, skin: skin)
        }
    }

    private func drawSliderLabels(in context: CGContext) {
        for item in Self.sliderLabelLayout(skin: skin) {
            AmpXLabel(text: item.text, color: skin.text, fontSize: Self.sliderLabelSize, weight: .regular)
                .draw(x: item.rect.minX, baseline: item.rect.maxY, context: context, skin: skin)
        }
    }

    // MARK: - Production geometry exposed for regressions

    private static let sliderLabelSize: CGFloat = 12.5

    struct TopRowFrames {
        var on: CGRect
        var auto: CGRect
        var presets: CGRect
        var curve: CGRect
    }

    static var topRowFrames: TopRowFrames {
        TopRowFrames(
            on: AmpXMetrics.eqOnToggle,
            auto: AmpXMetrics.eqAutoToggle,
            presets: AmpXMetrics.eqPresetsButton,
            curve: AmpXMetrics.eqCurveFrame
        )
    }

    /// Preamp first, then the ten bands. Rects are the cap-height box above the shared baseline
    /// (`maxY` is the baseline); `minX` is the drawing origin.
    static func sliderLabelLayout(skin: any AmpXSkin = ClassicModernSkin()) -> [(text: String, rect: CGRect)] {
        let baseline = AmpXMetrics.eqBandLabelBaseline

        func box(_ text: String, originX: (CGFloat, CGRect) -> CGFloat) -> (text: String, rect: CGRect) {
            let label = AmpXLabel(text: text, color: skin.text, fontSize: self.sliderLabelSize, weight: .regular)
            let width = label.measuredSize(skin: skin).width
            let capHeight = label.font(skin: skin).capHeight
            let x = originX(width, label.inkBounds(skin: skin))
            return (text, CGRect(x: x, y: baseline - capHeight, width: width, height: capHeight))
        }

        var items = [box("PREAMP") { _, ink in AmpXMetrics.eqPreampLabelInkX - ink.minX }]
        for (index, text) in AmpXEQBands.displayLabels.enumerated() {
            items.append(box(text) { _, ink in AmpXMetrics.eqBandCenterX[index] - ink.midX })
        }
        return items
    }
}

@MainActor
private final class EQPresetsMenuTarget: NSObject {
    weak var audioPlayer: AudioPlayer?
    var presets: [EQPreset] = []

    @objc func applyPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? EQPreset else { return }
        self.audioPlayer?.applyEQPreset(preset)
    }

    @objc func loadEQF(_: NSMenuItem) {
        self.audioPlayer?.importEQFPresets()
    }

    @objc func resetEQ(_: NSMenuItem) {
        self.audioPlayer?.resetEQ()
    }
}

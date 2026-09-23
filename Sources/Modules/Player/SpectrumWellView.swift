import AppKit
import CoreGraphics
import MetalKit
import QuartzCore

/// Player host for all mini effects. AppKit owns interaction and the frame driver;
/// Metal receives only prepared audio data, style, palette, and drawable dimensions.
final class SpectrumWellView: AmpXContinuousView {
    enum Geometry { case expanded, compact }
    var geometry: Geometry = .expanded {
        didSet {
            self.needsLayout = true
            self.layoutMetalSurface()
            self.redrawPreparedFrame()
        }
    }

    struct Reference: Equatable {
        /// Normalized 0…1 level per column.
        var levels: [Float]
        /// Normalized 0…1 peak-hold level per column.
        var peaks: [Float]
    }

    /// Display-only levels for deterministic reference presentation; `nil` draws live analysis.
    var reference: Reference? {
        didSet {
            self.metalSurface?.isHidden = self.reference != nil
            needsDisplay = true
        }
    }

    var audioSource: (TimeInterval) -> AmpXMiniAudioSnapshot = { time in
        AudioFeatureBus.shared.miniSnapshot(at: time)
    }

    var settings = AmpXMiniVisualizerSettings() {
        didSet {
            if oldValue.style != self.settings.style {
                self.miniState.reset()
                self.preparedFrame.history = [Float](repeating: 0, count: 4096)
                self.preparedFrame.elapsed = 0
            }
            self.updateAccessibility()
            self.redrawPreparedFrame()
        }
    }

    var onSettingsChanged: ((AmpXMiniVisualizerSettings) -> Void)?

    override var acceptsFirstResponder: Bool {
        self.geometry == .compact && AmpXControlView.acceptsFocus(isEnabled: true, currentEventType: NSApp.currentEvent?.type)
    }

    /// The small CPU fallback shares the existing three drawing families.
    private var mode: VisualizationMode {
        switch self.settings.style {
        case .lineWaveform, .particleWaveform: .oscilloscope
        case .dotSpectrum, .mirroredSpectrum: .bars
        default: .analyzer
        }
    }

    /// Classic behavior: a double-click shows or hides the visualizer.
    var onDoubleClick: (() -> Void)?

    /// The afterglow trail behind the columns is a bars-mode feature.
    static func drawsTrail(in mode: VisualizationMode) -> Bool {
        mode == .bars
    }

    /// The analyzer replaces the segmented columns with one thin bar per analysis band.
    static func drawsAnalyzerBars(in mode: VisualizationMode) -> Bool {
        mode == .analyzer
    }

    /// The waveform line replaces the columns in oscilloscope mode.
    static func drawsScopeLine(in mode: VisualizationMode) -> Bool {
        mode == .oscilloscope
    }

    /// Opacity of the afterglow drawn behind the live columns.
    static let trailAlpha: CGFloat = 0.3

    /// Downsamples a mono waveform to one level per polyline point. The shared sampler quantizes to
    /// Metal's clip space, where a positive sample is negative, so the sign is flipped for drawing.
    static func scopeLevels(fromWaveform waveform: [Float], width: CGFloat) -> [Float] {
        OscilloscopeColumnSampler
            .columns(from: waveform, count: AmpXScopeLineLayout.columnCount(forWidth: width))
            .map { -$0 }
    }

    /// A click cycles the mode on the click itself, so the well reacts at once. Waiting out
    /// `doubleClickInterval` first — the only way to know no double-click follows — made every cycle
    /// lag by half a second or more and read as an unresponsive well. The second click of a
    /// double-click instead undoes the advance, so opening the visualizer still never changes mode.
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount < 2 else {
            if let previous = self.styleBeforeClick {
                self.styleBeforeClick = nil
                self.selectStyle(previous)
            }
            self.onDoubleClick?()
            return
        }

        self.styleBeforeClick = self.settings.style
        self.selectStyle(self.settings.style.advanced())
    }

    /// Adopts a mode, reports it for persistence, and wakes a parked well so the new mode draws live
    /// data instead of whatever the last frame before the park left behind.
    func selectStyle(_ style: AmpXMiniVisualizerStyle) {
        guard style != self.settings.style else { return }
        self.settings.style = style
        self.onSettingsChanged?(self.settings)
        self.wakeRendering()
    }

    func selectPalette(_ palette: AmpXMiniVisualizerPalette) {
        guard palette != self.settings.palette else { return }
        self.settings.palette = palette
        self.onSettingsChanged?(self.settings)
    }

    private let segmentCount = AmpXSpectrumColumnModel.segmentCount
    private let columnCount = AmpXSpectrumColumnModel.columnCount
    private var miniState = AmpXMiniVisualizerState()
    private(set) var preparedFrame = AmpXMiniVisualizerFrame()
    private var idleGate = VisualizerIdleGate()
    private var styleBeforeClick: AmpXMiniVisualizerStyle?
    private var renderer: AmpXMiniVisualizerRenderer?
    private var metalSurface: AmpXMiniMetalSurface?
    private var attemptedMetal = false
    private var effectivelyVisible = false
    var rendererFactory: () -> AmpXMiniVisualizerRenderer? = { AmpXMiniVisualizerRenderer() }
    private var scopeLineLevels: [Float] = []
    private var columnLevels = [Float](repeating: 0, count: AmpXSpectrumColumnModel.columnCount)
    private var columnPeakLevels = [Float](repeating: 0, count: AmpXSpectrumColumnModel.columnCount)
    private var columnTrailLevels = [Float](repeating: 0, count: AmpXSpectrumColumnModel.columnCount)
    private var bandLevels = [Float](repeating: 0, count: AudioFeatures.spectrumBandCount)
    private var bandPeakLevels = [Float](repeating: 0, count: AudioFeatures.spectrumBandCount)

    /// Timestamp of the last frame, or `nil` when the next frame starts a fresh delta.
    private(set) var lastTimestamp: TimeInterval?

    /// Bottom-to-top segment colors sampled from the reference columns.
    private static let segmentColors: [NSColor] = [
        NSColor(srgbRed: 28 / 255, green: 247 / 255, blue: 6 / 255, alpha: 1),
        NSColor(srgbRed: 139 / 255, green: 233 / 255, blue: 1 / 255, alpha: 1),
        NSColor(srgbRed: 250 / 255, green: 242 / 255, blue: 6 / 255, alpha: 1),
        NSColor(srgbRed: 250 / 255, green: 227 / 255, blue: 8 / 255, alpha: 1),
        NSColor(srgbRed: 244 / 255, green: 180 / 255, blue: 0, alpha: 1),
        NSColor(srgbRed: 252 / 255, green: 170 / 255, blue: 2 / 255, alpha: 1),
    ]

    override func tick(at time: TimeInterval) {
        if let lastTimestamp, time >= lastTimestamp, time - lastTimestamp < 1.0 / 60.0 - 0.00001 {
            return
        }
        let deltaTime: Float = if let lastTimestamp {
            Float(max(time - lastTimestamp, 0))
        } else {
            1.0 / 60.0
        }
        self.lastTimestamp = time

        let frame = self.miniState.update(self.audioSource(time), at: time)
        self.preparedFrame = frame
        self.scopeLineLevels = frame.waveform
        self.columnLevels = AmpXSpectrumColumnPipeline.columnLevels(fromBands: frame.spectrum)
        self.columnPeakLevels = frame.peaks
        self.columnTrailLevels = AmpXSpectrumColumnPipeline.columnLevels(fromBands: frame.trails)
        self.bandLevels = frame.spectrum
        self.bandPeakLevels = frame.peaks

        self.redrawPreparedFrame()

        // Park the link only after the final decayed frame has been requested, so the well freezes
        // on an empty display rather than mid-decay. `PlayerModuleContent` wakes it on playback.
        self.setContinuousRenderingPaused(
            self.idleGate.update(isActive: frame.isActive, deltaTime: CFTimeInterval(deltaTime))
        )
    }

    func playbackStateDidChange(isPlaying: Bool) {
        if !isPlaying {
            self.miniState.playbackDidPause()
        }
        self.wakeRendering()
    }

    /// Resumes a parked well on a genuine external event (playback started). Only this clears the
    /// idle window: the tick loop must never reset it, or the well could never reach the hold time.
    func wakeRendering() {
        self.idleGate.wake()
        // Drop the parked-frame timestamp: the next frame would otherwise carry the whole parked
        // interval as its delta and run the smoothing and falloff straight to their extremes.
        self.lastTimestamp = nil
        self.setContinuousRenderingPaused(false)
    }

    override func setEffectivelyVisible(_ value: Bool) {
        self.effectivelyVisible = value
        super.setEffectivelyVisible(value)
        if value {
            self.lastTimestamp = nil
            self.redrawPreparedFrame()
        }
    }

    override func layout() {
        super.layout()
        self.layoutMetalSurface()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        self.layoutMetalSurface()
        self.redrawPreparedFrame()
    }

    private func layoutMetalSurface() {
        guard let surface = self.metalSurface else { return }
        surface.frame = self.spectrumRect
        let scale = self.window?.backingScaleFactor ?? 1
        let size = CGSize(width: self.spectrumRect.width * scale, height: self.spectrumRect.height * scale)
        if surface.drawableSize != size {
            surface.drawableSize = size
        }
    }

    private func redrawPreparedFrame() {
        self.needsDisplay = true
        guard self.reference == nil, self.effectivelyVisible, self.window != nil else { return }
        if !self.attemptedMetal {
            self.attemptedMetal = true
            self.renderer = self.rendererFactory()
            if let renderer {
                let surface = AmpXMiniMetalSurface(frame: self.spectrumRect, device: renderer.device)
                surface.colorPixelFormat = .bgra8Unorm
                surface.framebufferOnly = true
                surface.isPaused = true
                surface.enableSetNeedsDisplay = false
                surface.autoResizeDrawable = false
                surface.delegate = surface
                surface.onDraw = { [weak self] view in
                    guard let self, self.effectivelyVisible, self.reference == nil else { return }
                    self.renderer?.render(
                        self.preparedFrame,
                        style: self.settings.style,
                        palette: self.settings.palette,
                        in: view
                    )
                }
                self.metalSurface = surface
                self.addSubview(surface)
                self.layoutMetalSurface()
            } else {
                self.toolTip = "Metal is unavailable. Showing a basic visualizer."
            }
        }
        if self.renderer != nil, let surface = self.metalSurface {
            surface.isHidden = false
            // MTKView refreshes its currentDrawable at the end of this draw cycle.
            // Calling the renderer directly would present the same drawable repeatedly.
            surface.draw()
        }
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        self.makeContextMenu()
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        for style in AmpXMiniVisualizerStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(self.chooseStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style
            item.state = style == self.settings.style ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let palettes = NSMenu()
        for palette in AmpXMiniVisualizerPalette.allCases {
            let item = NSMenuItem(title: palette.title, action: #selector(self.choosePalette(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = palette
            item.state = palette == self.settings.palette ? .on : .off
            palettes.addItem(item)
        }
        let item = NSMenuItem(title: "Palette", action: nil, keyEquivalent: "")
        item.submenu = palettes
        menu.addItem(item)
        return menu
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? AmpXMiniVisualizerStyle {
            self.selectStyle(style)
        }
    }

    @objc private func choosePalette(_ sender: NSMenuItem) {
        if let palette = sender.representedObject as? AmpXMiniVisualizerPalette {
            self.selectPalette(palette)
        }
    }

    private func updateAccessibility() {
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.button)
        self.setAccessibilityLabel("Mini visualizer")
        self.setAccessibilityValue("\(self.settings.style.title), \(self.settings.palette.title)")
    }

    override func accessibilityPerformPress() -> Bool {
        self.selectStyle(self.settings.style.advanced())
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [
            NSAccessibilityCustomAction(name: "Next visualizer", target: self, selector: #selector(self.accessibilityNextStyle)),
            NSAccessibilityCustomAction(name: "Next palette", target: self, selector: #selector(self.accessibilityNextPalette)),
        ]
    }

    @objc private func accessibilityNextStyle() -> Bool {
        self.accessibilityPerformPress()
    }

    @objc private func accessibilityNextPalette() -> Bool {
        self.selectPalette(self.settings.palette.advanced())
        return true
    }

    /// Spectrum area in this view's coordinates (the view is placed on the display well).
    var spectrumRect: CGRect {
        switch self.geometry {
        case .expanded:
            AmpXMetrics.playerSpectrum.offsetBy(dx: -AmpXMetrics.playerDisplayWell.minX, dy: -AmpXMetrics.playerDisplayWell.minY)
        case .compact:
            self.bounds
        }
    }

    func segmentRect(column: Int, segment: Int) -> CGRect {
        let area = self.spectrumRect
        if self.geometry == .compact {
            let pitchX = area.width / CGFloat(self.columnCount)
            let pitchY = area.height / CGFloat(self.segmentCount)
            return CGRect(
                x: area.minX + CGFloat(column) * pitchX,
                y: area.minY + CGFloat(self.segmentCount - 1 - segment) * pitchY,
                width: pitchX * 0.65,
                height: pitchY * 0.65
            )
        }
        let top = area.minY + CGFloat(self.segmentCount - 1 - segment) * AmpXMetrics.spectrumSegmentPitch
        return CGRect(
            x: area.minX + CGFloat(column) * AmpXMetrics.spectrumColumnPitch,
            y: top,
            width: AmpXMetrics.spectrumColumnWidth,
            height: AmpXMetrics.spectrumSegmentHeight
        )
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // The Metal child covers its parent drawing; keep the keyboard outline above its contents.
        if self.geometry == .compact {
            self.metalSurface?.layer?.borderColor = self.skin.green.cgColor
            self.metalSurface?.layer?.borderWidth = self.window?.firstResponder === self
                ? 1 / (self.window?.backingScaleFactor ?? 1) : 0
        }

        // A reference presentation always draws the segmented columns: the deterministic captures
        // must not depend on whichever mode the user last left persisted.
        if let reference {
            self.drawColumns(levels: reference.levels, alpha: 1, in: context)
        } else if self.metalSurface?.isHidden == false {
            // The Metal child draws only the spectrum rectangle; labels remain AppKit.
        } else if Self.drawsScopeLine(in: self.mode) {
            self.drawScopeLine(in: context)
        } else if Self.drawsAnalyzerBars(in: self.mode) {
            self.drawAnalyzerBars(in: context)
        } else {
            if Self.drawsTrail(in: self.mode) {
                self.drawColumns(levels: self.columnTrailLevels, alpha: Self.trailAlpha, in: context)
            }
            self.drawColumns(levels: self.columnLevels, alpha: 1, in: context)
        }

        guard self.geometry == .expanded else {
            self.drawCompactFocusRing(in: context)
            return
        }
        let labelColor = NSColor(srgbRed: 133 / 255, green: 148 / 255, blue: 179 / 255, alpha: 1)
        let origin = AmpXMetrics.playerDisplayWell.origin
        for (text, ink) in [("L", AmpXMetrics.playerChannelLabelL), ("R", AmpXMetrics.playerChannelLabelR)] {
            let label = AmpXLabel(text: text, color: labelColor, fontSize: 19, weight: .semibold)
            let font = label.font(skin: skin)
            label.draw(
                x: ink.minX - origin.x - 1.4,
                baseline: ink.minY - origin.y + font.capHeight,
                context: context,
                skin: skin
            )
        }
    }

    /// One-point-per-column waveform line, zero amplitude on the centre of the spectrum area.
    private func drawScopeLine(in context: CGContext) {
        let points = AmpXScopeLineLayout.points(levels: self.scopeLineLevels, in: self.spectrumRect)
        guard points.count > 1 else { return }

        context.setStrokeColor(self.fallbackColor(self.settings.palette.traceColor).cgColor)
        context.setLineWidth(1)
        context.setLineJoin(.round)
        context.addLines(between: points)
        context.strokePath()
    }

    /// The segmented columns, drawn at full strength for the live bars and dimmed for the afterglow
    /// behind them.
    private func drawColumns(levels: [Float], alpha: CGFloat, in context: CGContext) {
        for column in 0 ..< min(self.columnCount, levels.count) {
            self.drawColumn(column, level: levels[column], alpha: alpha, context: context)
        }
    }

    private func drawColumn(_ column: Int, level: Float, alpha: CGFloat, context: CGContext) {
        let lit = CGFloat(min(max(level, 0), 1)) * CGFloat(self.segmentCount)
        let fullSegments = Int(lit)
        for segment in 0 ..< min(fullSegments, self.segmentCount) {
            let color = self.reference != nil ? Self.segmentColors[segment] : self.fallbackSpectrumColor(level: CGFloat(segment) / 5)
            context.setFillColor(color.withAlphaComponent(alpha).cgColor)
            context.fill(self.segmentRect(column: column, segment: segment))
        }

        let partial = lit - CGFloat(fullSegments)
        if fullSegments < self.segmentCount, partial > 0.08 {
            let slot = self.segmentRect(column: column, segment: fullSegments)
            let height = max(1, slot.height * partial)
            let color = self.reference != nil ? Self.segmentColors[fullSegments] : self
                .fallbackSpectrumColor(level: CGFloat(fullSegments) / 5)
            context.setFillColor(color.withAlphaComponent(alpha).cgColor)
            context.fill(CGRect(x: slot.minX, y: slot.maxY - height, width: slot.width, height: height))
        }
    }

    /// One thin continuous bar per analysis band with a floating peak cap: twice the resolution of
    /// the bars mode, so the two modes read as different instruments.
    private func drawAnalyzerBars(in context: CGContext) {
        let area = self.spectrumRect
        let bars = AmpXAnalyzerBarLayout.bars(levels: self.bandLevels, in: area)
        for (index, bar) in bars.enumerated() {
            context.setFillColor(self.fallbackSpectrumColor(level: CGFloat(self.bandLevels[index])).cgColor)
            context.fill(bar)
        }

        context.setFillColor(Self.analyzerCapColor.cgColor)
        for cap in AmpXAnalyzerBarLayout.caps(peaks: self.bandPeakLevels, in: area) {
            context.fill(cap)
        }
    }

    /// Cool white for the floating caps, so they stay legible over every palette colour.
    private static let analyzerCapColor = NSColor(srgbRed: 217 / 255, green: 234 / 255, blue: 1, alpha: 0.95)

    private func fallbackSpectrumColor(level: CGFloat) -> NSColor {
        let t = Float(min(max(level, 0), 1))
        let low = self.settings.palette.lowColor
        let high = self.settings.palette.highColor
        return self.fallbackColor(low + (high - low) * t)
    }

    private func fallbackColor(_ value: SIMD4<Float>) -> NSColor {
        NSColor(srgbRed: CGFloat(value.x), green: CGFloat(value.y), blue: CGFloat(value.z), alpha: CGFloat(value.w))
    }
}

/// Let the surrounding well handle clicks and its native context menu.
private final class AmpXMiniMetalSurface: MTKView, MTKViewDelegate {
    var onDraw: ((MTKView) -> Void)?

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        self.onDraw?(view)
    }
}

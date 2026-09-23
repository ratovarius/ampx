import AppKit
import CoreGraphics

enum AmpXFaceStyle {
    /// Midnight Hardware key face shared by every button and handle; glyphs use `faceInk`.
    case normal
    case hovered
    /// Transient mechanical press; the bevel stays raised and the ink sinks 0.5 pt.
    case pressed
    /// Orange menu button; glyphs stay light (`text`).
    case menu
    case menuHovered
    case menuPressed
    /// Non-interactive raised navy surface (legacy slider thumb).
    case surface

    var isMenu: Bool {
        self == .menu || self == .menuHovered || self == .menuPressed
    }

    var isPressed: Bool {
        self == .pressed || self == .menuPressed
    }

    /// Face style for a control's interaction state.
    static func resolve(pressed: Bool, hovered: Bool, menu: Bool = false) -> AmpXFaceStyle {
        switch (menu, pressed, hovered) {
        case (true, true, _): .menuPressed
        case (true, false, true): .menuHovered
        case (true, false, false): .menu
        case (false, true, _): .pressed
        case (false, false, true): .hovered
        case (false, false, false): .normal
        }
    }
}

enum AmpXThumbMaterial {
    /// Handle travelling horizontally: three vertical grip cuts (volume, balance, seek).
    case steel
    /// Handle travelling vertically: three horizontal grip cuts (EQ bands).
    case steelLevel
    /// Seek handle; same hardware as `steel`.
    case gold
    /// Playlist scrollbar handle; same hardware as `steelLevel`.
    case goldTab

    /// Grip cuts run across the travel axis.
    var travelsVertically: Bool {
        self == .steelLevel || self == .goldTab
    }
}

enum AmpXTrackFill {
    case volume
    case balance
}

protocol AmpXSkin {
    var background: NSColor { get }
    var panel: NSColor { get }
    var panelLight: NSColor { get }
    var border: NSColor { get }
    var borderHighlight: NSColor { get }
    var borderDark: NSColor { get }
    var text: NSColor { get }
    var textDim: NSColor { get }
    var selection: NSColor { get }
    var green: NSColor { get }
    var yellow: NSColor { get }
    var orange: NSColor { get }
    var display: NSColor { get }
    /// Sampled from PNG scrollbar thumb (ReferenceMeasurementsV1).
    var gold: NSColor { get }
    /// Sampled from PNG scrollbar thumb highlight (ReferenceMeasurementsV1).
    var goldLight: NSColor { get }
    /// Glyph and label ink on steel button faces.
    var faceInk: NSColor { get }
    /// Disabled glyph and label ink on steel button faces.
    var faceInkDim: NSColor { get }
    /// Accent glyph inks on light steel faces, where `green`/`yellow`/`orange` are too light
    /// to read. The bright accents stay for dark surfaces and pressed faces.
    var faceGreen: NSColor { get }
    var faceAmber: NSColor { get }
    var faceOrange: NSColor { get }

    func font(size: CGFloat, weight: NSFont.Weight) -> NSFont

    /// Raised control face in its normal state.
    func bevel(_ rect: CGRect, in context: CGContext, backingScale: CGFloat)
    func inset(_ rect: CGRect, in context: CGContext, backingScale: CGFloat)
    func accentLine(_ rect: CGRect, in context: CGContext, backingScale: CGFloat)
    /// Recessed black well with a steel lip.
    func displayWell(_ rect: CGRect, in context: CGContext, backingScale: CGFloat)

    /// Module panel with layered outer edges and an optional recessed content frame.
    func panelFrame(_ rect: CGRect, contentFrame: CGRect?, in context: CGContext, backingScale: CGFloat)
    func raisedFace(_ rect: CGRect, style: AmpXFaceStyle, in context: CGContext, backingScale: CGFloat)
    /// Paired gold header rules filling `rect` (two 3.5 pt lines, 2.5 pt apart at scale 1).
    func headerRule(_ rect: CGRect, in context: CGContext, backingScale: CGFloat)
    func dotGrid(_ rect: CGRect, in context: CGContext)
    /// Pill track filled end to end with the `AmpXSliderColorRamp` color at the value `fraction` (0…1).
    func sliderTrack(
        _ rect: CGRect,
        fill: AmpXTrackFill,
        fraction: Double,
        in context: CGContext,
        backingScale: CGFloat
    )
    /// Seek channel: the shared track shell with a neutral fill. `well` is the slider's frame.
    func seekWell(_ well: CGRect, track: CGRect, in context: CGContext, backingScale: CGFloat)
    /// Neutral track channel (seek bar, Playlist scrollbar trough).
    func neutralTrack(_ rect: CGRect, in context: CGContext, backingScale: CGFloat)
    /// Vertical EQ slot with a glowing bar tinted by the displayed gain.
    func levelTrack(_ slot: CGRect, decibels: Double, in context: CGContext, backingScale: CGFloat)
    /// Handle in the shared key material; `style` carries hover and drag.
    func metallicThumb(
        _ rect: CGRect,
        material: AmpXThumbMaterial,
        style: AmpXFaceStyle,
        in context: CGContext,
        backingScale: CGFloat
    )
}

extension AmpXSkin {
    func metallicThumb(_ rect: CGRect, material: AmpXThumbMaterial, in context: CGContext, backingScale: CGFloat) {
        self.metallicThumb(rect, material: material, style: .normal, in: context, backingScale: backingScale)
    }
}

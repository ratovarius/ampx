import CoreGraphics

/// Layout constants in logical points. Player values come from ReferenceMeasurementsV2 (2× source);
/// Equalizer/Playlist values remain unvalidated V1 until their reconstruction tasks.
enum AmpXMetrics {
    static let compositionWidth: CGFloat = 490
    static let playerHeight: CGFloat = 223.5
    static let equalizerHeight: CGFloat = 225.5
    static let playlistHeight: CGFloat = 305
    static let entheaHeight: CGFloat = 290
    static let moduleGap: CGFloat = 6

    static let headerHeight: CGFloat = 28.5
    /// Row-area top (10) + footer gap (2) + footer (68.5); reference Playlist 305 pt with a 196 pt viewport.
    static let playlistNonRowChrome: CGFloat = 80.5
    static let playlistRowHeight: CGFloat = 22
    static let minimumPlaylistViewportHeight: CGFloat = playlistRowHeight * 3
    static let defaultPlaylistViewportHeight: CGFloat = playlistHeight - headerHeight - playlistNonRowChrome
    /// Spec Revision 9: the Playlist may be wider than the reference, never narrower than the fixed EQ width.
    static let minimumPlaylistWidth: CGFloat = compositionWidth
    static let defaultPlaylistWidth: CGFloat = compositionWidth

    /// Midnight Hardware key tiers: 36 pt main transport row, 28 pt toggles and actions, 20 pt header,
    /// mini transport and scroll keys. Every key shares a 2 pt radius and 12 pt medium labels.
    static let primaryButtonSize = CGSize(width: 44, height: 36)
    static let secondaryButtonSize = CGSize(width: 64, height: 28)
    static let utilityButtonSize = CGSize(width: 20, height: 20)
    static let keyLabelFontSize: CGFloat = 12
    /// Button-local lamp shared by every toggle; labels start at `keyLampLabelX`.
    static let keyLampSize = CGSize(width: 8, height: 8)
    static let keyLampX: CGFloat = 7
    static let keyLampLabelX: CGFloat = 21

    // MARK: - Module chrome (module coordinates, V2 records 2–12)

    /// Recessed content frame: `content.frame` (7, 27.5, 476, 189.5) within the 490 × 223.5 Player.
    static let contentFrameInsets = (top: CGFloat(27.5), left: CGFloat(7), bottom: CGFloat(6.5), right: CGFloat(7))
    static let headerBrandGlyph = CGRect(x: 9.5, y: 7, width: 18, height: 16)
    static let headerRuleMinX: CGFloat = 37.5
    static let headerRuleMaxX: CGFloat = 405
    /// Gap between the right rule and the leftmost header button (412 − 405 on the Player).
    static let headerRuleGapBeforeButtons: CGFloat = 7
    static let headerRuleY: CGFloat = 9.5
    static let headerRuleHeight: CGFloat = 9.5
    static let headerRuleGapBeforeTitle: CGFloat = 19.5
    static let headerRuleGapAfterTitle: CGFloat = 16.5
    static let headerTitleCenterX: CGFloat = 245
    static let headerBrandInkTop: CGFloat = 6
    static let headerMinimizeButton = CGRect(x: 412, y: 5, width: 20, height: 20)
    static let headerCollapseButton = CGRect(x: 438, y: 5, width: 20, height: 20)
    static let headerCloseButton = CGRect(x: 464, y: 5, width: 20, height: 20)
    /// Glyph ink boxes relative to their header button.
    static let headerMinimizeGlyph = CGRect(x: 5.25, y: 11, width: 8.75, height: 2.75)
    static let headerCollapseGlyph = CGRect(x: 4.75, y: 4.5, width: 10.5, height: 10.5)
    static let headerCloseGlyph = CGRect(x: 5, y: 5, width: 10, height: 10)

    // MARK: - Player (content coordinates, scale 1.0)

    static let metadataDigitStyle: MetadataDigitStyle = .mono

    static let playerDisplayWell = CGRect(x: 14, y: 10.0, width: 168.0, height: 95.0)
    static let playerDisplayInterior = CGRect(x: 16, y: 12.5, width: 164.0, height: 90.5)
    static let playerTrackWell = CGRect(x: 188, y: 10.0, width: 288, height: 31.5)
    static let playerTrackTextInk = CGRect(x: 193.5, y: 18.0, width: 214.5, height: 14.0)
    static let playerTimer = CGRect(x: 84.5, y: 18.0, width: 82.0, height: 25.5)
    static let playerPlayGlyph = CGRect(x: 35.0, y: 21.0, width: 14.0, height: 18.0)
    static let playerSpectrum = CGRect(x: 33.0, y: 57.0, width: 137.5, height: 41.0)
    static let playerChannelLabelL = CGRect(x: 19.0, y: 64.0, width: 9.0, height: 13.5)
    static let playerChannelLabelR = CGRect(x: 19.0, y: 85.0, width: 9.0, height: 13.5)

    static let playerBitrateWell = CGRect(x: 188, y: 46.0, width: 40, height: 24)
    static let playerBitrateInk = CGRect(x: 193.5, y: 52.0, width: 25.5, height: 12.5)
    static let playerKbpsInk = CGRect(x: 232.0, y: 53.5, width: 26.5, height: 13.5)
    static let playerSampleRateWell = CGRect(x: 274.0, y: 46, width: 34, height: 24)
    static let playerSampleRateInk = CGRect(x: 282.0, y: 52.0, width: 16.5, height: 12.5)
    static let playerKHzInk = CGRect(x: 312.5, y: 53.5, width: 20.5, height: 11.5)
    static let playerMonoInk = CGRect(x: 390.5, y: 55.5, width: 30.0, height: 9.0)
    static let playerStereoInk = CGRect(x: 430.5, y: 53.5, width: 41.0, height: 11.0)

    /// Slider frames enclose the visible track and thumb; hit areas expand from these.
    static let playerVolume = CGRect(x: 188, y: 79, width: 106, height: 24)
    static let playerBalance = CGRect(x: 302, y: 79, width: 68, height: 24)
    static let playerSliderTrackHeight: CGFloat = 12
    static let playerSliderThumbSize = CGSize(width: 20, height: 20)
    /// Handles sit centered on their tracks.
    static let playerSliderThumbOffset: CGFloat = 0
    static let playerPosition = CGRect(x: 14, y: 111, width: 462, height: 24)
    static let playerPositionTrackSize = CGSize(width: 454, height: 12)
    static let playerPositionThumbSize = CGSize(width: 44, height: 20)
    static let playerPositionThumbOffset: CGFloat = 0

    static let playerEQToggle = CGRect(x: 376, y: 77.0, width: 48, height: 28)
    static let playerPLToggle = CGRect(x: 428.0, y: 77.0, width: 48, height: 28)
    /// Button-local indicator lamps and label ink (left edge, baseline).
    static let playerEQIndicator = CGRect(x: 7, y: 10, width: 8, height: 8)
    static let playerPLIndicator = CGRect(x: 7, y: 10, width: 8, height: 8)
    static let playerEQLabelInk = CGPoint(x: 21, y: 18.5)
    static let playerPLLabelInk = CGPoint(x: 21, y: 18.5)
    static let playerShuffleIndicator = CGRect(x: 7, y: 14, width: 8, height: 8)
    static let playerShuffleLabelInk = CGPoint(x: 21, y: 22.5)

    static let playerTransport: [CGRect] = [
        CGRect(x: 14, y: 140, width: 44, height: 36),
        CGRect(x: 62, y: 140, width: 44, height: 36),
        CGRect(x: 110, y: 140, width: 44, height: 36),
        CGRect(x: 158, y: 140, width: 44, height: 36),
        CGRect(x: 206, y: 140, width: 44, height: 36),
        CGRect(x: 254, y: 140, width: 44, height: 36),
        CGRect(x: 302, y: 140, width: 86, height: 36),
        CGRect(x: 392, y: 140, width: 36, height: 36),
        CGRect(x: 432, y: 140, width: 44, height: 36),
    ]

    /// Transport glyph boxes (content coordinates): a shared 16 pt cell centered in each key;
    /// Shuffle uses indicator + label instead.
    static let playerTransportGlyphs: [CGRect?] = [
        CGRect(x: 28, y: 150, width: 16, height: 16),
        CGRect(x: 76, y: 150, width: 16, height: 16),
        CGRect(x: 124, y: 150, width: 16, height: 16),
        CGRect(x: 172, y: 150, width: 16, height: 16),
        CGRect(x: 220, y: 150, width: 16, height: 16),
        CGRect(x: 268, y: 150, width: 16, height: 16),
        nil,
        CGRect(x: 402, y: 150, width: 16, height: 16),
        CGRect(x: 446, y: 150, width: 16, height: 16),
    ]

    /// Spectrum: 16 columns × 6 segments sampled from the reference display.
    static let spectrumColumnCount = 16
    static let spectrumSegmentCount = 6
    static let spectrumColumnWidth: CGFloat = 5.5
    static let spectrumColumnPitch: CGFloat = 8.75
    static let spectrumSegmentHeight: CGFloat = 5.0
    static let spectrumSegmentPitch: CGFloat = 6.9

    // MARK: - Equalizer (content coordinates, ReferenceMeasurementsV2 eq-measurements-v2)

    static let eqOnToggle = CGRect(x: 14, y: 10, width: 56, height: 28)
    static let eqAutoToggle = CGRect(x: 74, y: 10, width: 72, height: 28)
    static let eqPresetsButton = CGRect(x: 384, y: 10, width: 92, height: 28)
    /// Button-local lamps, label ink (left edge, baseline) and dropdown triangle.
    static let eqOnIndicator = CGRect(x: 7, y: 10, width: 8, height: 8)
    static let eqAutoIndicator = CGRect(x: 7, y: 10, width: 8, height: 8)
    static let eqOnLabelInk = CGPoint(x: 21, y: 18.5)
    static let eqAutoLabelInk = CGPoint(x: 21, y: 18.5)
    static let eqPresetsLabelInk = CGPoint(x: 10, y: 18.5)
    static let eqPresetsTriangle = CGRect(x: 76, y: 11, width: 8, height: 6)

    /// Curve drawn on the panel (no well): edge knots at the frame edges, band knots from +20 pt at 18.39 pt pitch.
    static let eqCurveFrame = CGRect(x: 161, y: 5, width: 201, height: 42)
    static let eqCurveFirstBandOffset: CGFloat = 20
    static let eqCurveBandPitch: CGFloat = 18.39
    static let eqGridMinY: CGFloat = 10
    static let eqGridMaxY: CGFloat = 47

    /// Band centers on an even 34 pt pitch.
    static let eqPreampCenterX: CGFloat = 36
    static let eqBandCenterX: [CGFloat] = [135, 169, 203, 237, 271, 305, 339, 373, 407, 441]
    static let eqSliderSlotSize = CGSize(width: 12, height: 110)
    static let eqSliderSlotCenterY: CGFloat = 108
    static let eqSliderThumbSize = CGSize(width: 20, height: 20)
    /// Thumb-center travel: +12 dB at the 59 pt tick row, −12 dB at 157 pt.
    static let eqSliderTravel: CGFloat = 98
    static let eqTickWidth: CGFloat = 6.5
    static let eqPreampTickOffset: CGFloat = 15.75
    static let eqOuterBandTickOffset: CGFloat = 17.25
    static let eqDecibelLabelCenterX: CGFloat = 80
    static let eqDecibelLabelBaselines: [CGFloat] = [63.5, 112.5, 161.5]
    static let eqPreampLabelInkX: CGFloat = 20
    static let eqBandLabelBaseline: CGFloat = 180.5

    // MARK: - Playlist (content coordinates, playlist-measurements-v2)

    /// Black row area inside the rows well; its height is the default viewport (reference: 196 pt).
    static let playlistRows = CGRect(x: 15.5, y: 10, width: 437, height: 196)
    /// Well lip around the row area: left, top, right, bottom.
    static let playlistRowsWellOutsets = (left: CGFloat(2), top: CGFloat(1.5), right: CGFloat(2.5), bottom: CGFloat(2))
    /// Scrollbar x/width; it spans the rows well lip, from 1.5 pt above the row area to 2 pt below it.
    static let playlistScrollbar = CGRect(x: 456, y: 8.5, width: 20, height: 199.5)
    static let playlistScrollbarUpButtonHeight: CGFloat = 20
    static let playlistScrollbarDownButtonHeight: CGFloat = 20
    static let playlistScrollbarThumbLength: CGFloat = 36
    static let playlistScrollbarThumbInset: CGFloat = 2
    static let playlistScrollbarUpGlyph = CGRect(x: 6, y: 6, width: 8, height: 8)
    static let playlistScrollbarDownGlyph = CGRect(x: 6, y: 6, width: 8, height: 8)
    /// Footer frame starts this far below the row area and follows the viewport.
    static let playlistFooterGap: CGFloat = 2
    static let playlistFooterHeight: CGFloat = 68.5
    /// Resize strip along the Playlist content's bottom edge, below every footer control.
    static let playlistResizeStripHeight: CGFloat = 6
    /// Resize grip offset from the Playlist content's bottom-right corner, clear of LIST OPTS.
    static let playlistResizeGrip = CGRect(x: -20, y: -12, width: 14, height: 10.5)
    static let playlistDurationColumnWidth: CGFloat = 42
    /// Row text in row coordinates: number advance ends at 27, titles start at 38, durations end 12.75 pt
    /// before the row's trailing edge (reference ink: number 27 pt, title 53.5 pt, duration 442 pt in content).
    static let playlistRowNumberMaxX: CGFloat = 27
    static let playlistRowTitleX: CGFloat = 38
    static let playlistDurationTrailingInset: CGFloat = 12.75
    static let playlistRowFontSize: CGFloat = 13.75

    /// Footer-local frames (footer origin at the row area's left content edge x = 0).
    static let playlistFooterButtons: [(label: String, rect: CGRect)] = [
        ("ADD", CGRect(x: 14, y: 4, width: 44, height: 28)),
        ("REM", CGRect(x: 62, y: 4, width: 44, height: 28)),
        ("SEL", CGRect(x: 110, y: 4, width: 44, height: 28)),
        ("MISC", CGRect(x: 158, y: 4, width: 44, height: 28)),
        ("LIST OPTS", CGRect(x: 394, y: 4, width: 82, height: 28)),
    ]
    /// Footer controls at or beyond this reference x keep their right anchor when the Playlist is wider.
    static let playlistFooterRightGroupMinX: CGFloat = 206
    static let playlistFooterCounterWell = CGRect(x: 206, y: 4, width: 184, height: 28)
    /// Counter text ink left edge and baseline, relative to the counter well.
    static let playlistFooterCounterInk = CGPoint(x: 48, y: 18.5)
    static let playlistFooterRemainingWell = CGRect(x: 346, y: 36, width: 44, height: 20)
    static let playlistFooterRemainingBaseline: CGFloat = 14.5
    static let playlistFooterReadoutFontSize: CGFloat = 12
    static let playlistFooterTransport: [(frame: CGRect, glyph: CGRect)] = [
        (CGRect(x: 206, y: 36, width: 24, height: 20), CGRect(x: 7, y: 5, width: 10, height: 10)),
        (CGRect(x: 234, y: 36, width: 24, height: 20), CGRect(x: 7, y: 5, width: 10, height: 10)),
        (CGRect(x: 262, y: 36, width: 24, height: 20), CGRect(x: 7, y: 5, width: 10, height: 10)),
        (CGRect(x: 290, y: 36, width: 24, height: 20), CGRect(x: 7, y: 5, width: 10, height: 10)),
        (CGRect(x: 318, y: 36, width: 24, height: 20), CGRect(x: 7, y: 5, width: 10, height: 10)),
    ]

    enum MetadataDigitStyle: String {
        case mono
        case segments
    }
}

@testable import AmpX
import AppKit
import XCTest

/// Flipped container matching the stack's top-down module layout.
final class ReferenceStackView: NSView {
    override var isFlipped: Bool {
        true
    }
}

@MainActor
final class AmpXReferenceRenderingTests: XCTestCase {
    let skin = ClassicModernSkin()
    /// EqualizerModuleContent holds its player weakly in menu targets; keep models alive for the test.
    private var retainedPlayers: [AudioPlayer] = []

    // MARK: - Geometry regressions (production geometry, no copied rectangles)

    func testAdjacentTransportFacesDoNotIntersect() {
        for pair in zip(AmpXMetrics.playerTransport, AmpXMetrics.playerTransport.dropFirst()) {
            XCTAssertFalse(pair.0.intersects(pair.1), "Adjacent transport controls overlap")
        }
    }

    func testChannelLabelsDoNotIntersectNumericOrUnitLabels() {
        for (bitrate, sampleRate) in [("128", "48"), ("1411", "44.1"), ("320", "192")] {
            let layout = PlayerModuleContent.metadataLayout(bitrate: bitrate, sampleRate: sampleRate)
            let items = layout.items
            for item in items {
                let measured = AmpXLabel(text: item.text, color: self.skin.green, fontSize: item.fontSize, weight: item.weight)
                    .measuredSize(skin: self.skin)
                XCTAssertLessThanOrEqual(
                    measured.width, item.rect.width + 0.01,
                    "\(item.text) would wrap or clip for \(bitrate)/\(sampleRate)"
                )
            }
            for pair in items.indices.flatMap({ i in items.indices.filter { $0 > i }.map { (items[i], items[$0]) } }) {
                XCTAssertFalse(
                    pair.0.rect.intersects(pair.1.rect),
                    "\(pair.0.text) intersects \(pair.1.text) for \(bitrate)/\(sampleRate)"
                )
            }
        }
    }

    func testShortButtonTextHasPositiveUsableHeight() {
        let button = AmpXButton(skin: skin)
        button.frame = CGRect(x: 0, y: 0, width: 46.5, height: 20.5)
        button.label = "EQ"
        XCTAssertGreaterThanOrEqual(button.labelRect.height, button.labelFont.capHeight)
        XCTAssertTrue(button.bounds.contains(button.labelRect))
    }

    func testDigitCellWidthIsStableAcrossTimeFormats() {
        let frame = PlayerModuleContent.timerFrame
        let short = AmpXSegmentDigits.cells(for: "0:04", in: frame).filter { $0.character != ":" }
        let long = AmpXSegmentDigits.cells(for: "01:51", in: frame).filter { $0.character != ":" }
        let widths = Set((short + long).map { ($0.rect.width * 100).rounded() })
        XCTAssertEqual(widths.count, 1, "Digit cells stretch as the time format changes")
        XCTAssertEqual(short.last?.rect.maxX ?? 0, long.last?.rect.maxX ?? 1, accuracy: 0.01)

        let remaining = AmpXSegmentDigits.cells(for: "-12:34", in: frame)
        for pair in zip(remaining, remaining.dropFirst()) {
            XCTAssertFalse(pair.0.rect.intersects(pair.1.rect))
        }
        XCTAssertGreaterThan(remaining.first?.rect.minX ?? 0, PlayerModuleContent.playGlyphFrame.maxX)
    }

    func testSliderArtworkIsUnchangedWhenOnlyHitBoundsEnlarge() throws {
        let content = self.makePlayerContent()
        let slider = try XCTUnwrap(controlSliders(in: content).first)
        slider.setValue(0.4, sendChange: false)
        let track = slider.convert(slider.trackRect, to: content)
        let thumb = slider.convert(slider.thumbRect, to: content)

        slider.frame = slider.frame.insetBy(dx: -6, dy: -8)

        XCTAssertEqual(slider.convert(slider.trackRect, to: content), track)
        XCTAssertEqual(slider.convert(slider.thumbRect, to: content), thumb)
    }

    func testPointerAtThumbCenterMapsToDisplayedValue() {
        let content = self.makePlayerContent()
        for slider in self.controlSliders(in: content) + self.positionSliders(in: content) {
            for value in [0.0, 0.25, 0.5, 0.75, 1.0] {
                slider.setValue(value, sendChange: false)
                let center = CGPoint(x: slider.thumbRect.midX, y: slider.thumbRect.midY)
                XCTAssertEqual(slider.value(at: center), value, accuracy: 0.002)
            }
            XCTAssertEqual(slider.value(at: CGPoint(x: slider.bounds.minX - 20, y: slider.bounds.midY)), 0)
            XCTAssertEqual(slider.value(at: CGPoint(x: slider.bounds.maxX + 20, y: slider.bounds.midY)), 1)
        }
    }

    func testHeaderButtonsFollowReferenceOrder() {
        let player = AmpXModuleHeaderView(moduleID: .player, skin: skin)
        player.frame = CGRect(x: 0, y: 0, width: AmpXMetrics.compositionWidth, height: AmpXMetrics.headerHeight)
        let playerOrder = player.headerButtonLayout().sorted { $0.frame.minX < $1.frame.minX }.map(\.button)
        XCTAssertEqual(playerOrder, [.minimize, .collapse, .close])

        let equalizer = AmpXModuleHeaderView(moduleID: .equalizer, skin: skin)
        equalizer.frame = player.frame
        let equalizerOrder = equalizer.headerButtonLayout().sorted { $0.frame.minX < $1.frame.minX }.map(\.button)
        XCTAssertEqual(equalizerOrder, [.collapse, .close])
    }

    // MARK: - Equalizer geometry regressions

    func testEqualizerTopRowControlsDoNotOverlapCurve() {
        let frames = EqualizerModuleContent.topRowFrames
        let all = [("ON", frames.on), ("AUTO", frames.auto), ("PRESETS", frames.presets), ("curve", frames.curve)]
        let content = CGRect(
            x: 0, y: 0,
            width: AmpXMetrics.compositionWidth,
            height: AmpXMetrics.equalizerHeight - AmpXMetrics.headerHeight
        )
        for (index, item) in all.enumerated() {
            XCTAssertTrue(content.contains(item.1), "\(item.0) leaves the content area")
            for other in all.dropFirst(index + 1) {
                XCTAssertFalse(item.1.intersects(other.1), "\(item.0) overlaps \(other.0)")
            }
        }
    }

    func testEqualizerSlidersLabelsAndThumbsStaySeparate() {
        let content = self.makeEqualizerContent()
        let sliders = self.allSubviews(of: content).compactMap { $0 as? AmpXSlider }
        XCTAssertEqual(sliders.count, AmpXEQBands.bandCount + 1)
        let labels = EqualizerModuleContent.sliderLabelLayout()
        XCTAssertEqual(labels.count, sliders.count)
        for pair in zip(labels, labels.dropFirst()) {
            XCTAssertFalse(pair.0.rect.intersects(pair.1.rect), "\(pair.0.text) label collides with \(pair.1.text)")
        }
        let topRow = EqualizerModuleContent.topRowFrames
        for slider in sliders {
            for value in [-12.0, 0, 12] {
                slider.setValue(value, sendChange: false)
                let thumb = slider.convert(slider.thumbRect, to: content)
                XCTAssertTrue(content.bounds.contains(thumb), "\(slider.accessibilityTitle ?? "") thumb leaves content at \(value)")
                for rect in [topRow.on, topRow.auto, topRow.presets] + labels.map(\.rect) {
                    XCTAssertFalse(thumb.intersects(rect), "\(slider.accessibilityTitle ?? "") thumb overlaps a control at \(value)")
                }
                let center = CGPoint(x: slider.thumbRect.midX, y: slider.thumbRect.midY)
                XCTAssertEqual(slider.value(at: center), value, accuracy: 0.001)
            }
        }
        let artwork = sliders.map { $0.convert($0.trackRect.union($0.thumbRect), to: content) }
        for (index, rect) in artwork.enumerated() {
            for other in artwork.dropFirst(index + 1) {
                XCTAssertFalse(rect.intersects(other), "Adjacent EQ slider artwork overlaps")
            }
        }
    }

    // MARK: - Playlist geometry regressions

    func testPlaylistFooterFollowsRowViewportInsideContent() throws {
        let viewports: [CGFloat] = [
            AmpXMetrics.minimumPlaylistViewportHeight,
            AmpXMetrics.defaultPlaylistViewportHeight,
            300,
        ]
        for viewport in viewports {
            let content = self.makePlaylistContent()
            content.frame = CGRect(
                x: 0,
                y: 0,
                width: AmpXMetrics.compositionWidth,
                height: AmpXMetrics.playlistNonRowChrome + viewport
            )
            content.setRowViewportHeight(viewport)
            let subviews = self.allSubviews(of: content)
            let rows = try XCTUnwrap(subviews.first { $0 is PlaylistRowsView })
            let footer = try XCTUnwrap(subviews.first { $0 is PlaylistFooterView })
            let scrollbar = try XCTUnwrap(subviews.first { $0 is AmpXScrollbar })

            XCTAssertEqual(rows.frame.height, viewport, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(footer.frame.minY, rows.frame.maxY, "Footer overlaps rows at viewport \(viewport)")
            XCTAssertLessThanOrEqual(footer.frame.maxY, content.bounds.maxY + 0.01, "Footer clipped at viewport \(viewport)")
            XCTAssertLessThanOrEqual(scrollbar.frame.maxY, footer.frame.minY + 0.01, "Scrollbar overlaps footer at viewport \(viewport)")
            for control in footer.subviews {
                XCTAssertTrue(footer.bounds.contains(control.frame), "Footer control outside footer at viewport \(viewport)")
            }
        }
    }

    func testPlaylistRowTextColumnsStaySeparate() {
        let row = PlaylistRowLayout.rowRect(index: 0, width: AmpXMetrics.playlistRows.width)
        let column = PlaylistRowLayout.durationRect(in: row)
        XCTAssertEqual(column.width, 42)
        let longTitle = String(repeating: "Very Long Artist Name - ", count: 4)
        for number in [1, 10, 100, 1000] {
            let text = PlaylistRowLayout.textLayout(number: number, title: longTitle, duration: "59:59", in: row)
            XCTAssertGreaterThanOrEqual(text.numberRect.minX, row.minX, "Number \(number) clipped")
            XCTAssertLessThanOrEqual(text.numberRect.maxX, text.titleRect.minX, "Number \(number) overlaps title")
            XCTAssertLessThanOrEqual(text.titleRect.maxX, text.durationRect.minX, "Title overlaps duration for \(number)")
            XCTAssertTrue(column.insetBy(dx: -0.01, dy: -0.01).contains(text.durationRect), "Duration leaves its column")
        }
    }

    // MARK: - Deterministic reference capture

    /// Display-only values matching `screenshots/AmpX.png`. Spectrum levels/peaks are in segments (of 6).
    static let playerReference = PlayerReferencePresentation(
        trackTitle: "4. Crusher-P - Echo (3:50)",
        timeText: "01:51",
        bitrateText: "128",
        sampleRateText: "48",
        isMono: false,
        isStereo: true,
        isPlaying: true,
        spectrumLevels: [4, 4, 6, 3.3, 4, 2.4, 2.2, 2.5, 1.4, 1, 1, 1, 0.35, 0.3, 0.25, 0.15].map { $0 / 6 },
        spectrumPeaks: [4.6, 5.6, 6, 3.6, 5.6, 3.6, 3.4, 3.6, 2.4, 1.6, 2.6, 1.6, 1.4, 1.4, 1.2, 1.3].map { $0 / 6 },
        volume: 0.762,
        balance: 0.5,
        position: 0.498,
        equalizerOpen: true,
        playlistOpen: true,
        shuffleEnabled: true,
        repeatEnabled: false
    )

    func testPlayerStaticReferenceCaptureIsDeterministic() throws {
        let content = self.makePlayerContent()
        content.referencePresentation = Self.playerReference
        let module = AmpXModuleView(moduleID: .player, content: content, skin: skin)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: AmpXMetrics.compositionWidth, height: AmpXMetrics.playerHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(module)
        module.applyLayout(frame: CGRect(x: 0, y: 0, width: AmpXMetrics.compositionWidth, height: AmpXMetrics.playerHeight))

        let first = try capture(module)
        let second = try capture(module)
        XCTAssertEqual(first.pixelsWide, 980)
        XCTAssertEqual(first.pixelsHigh, 447)
        let firstPNG = try XCTUnwrap(first.representation(using: .png, properties: [:]))
        let secondPNG = try XCTUnwrap(second.representation(using: .png, properties: [:]))
        XCTAssertEqual(firstPNG, secondPNG, "Frozen reference presentation must render identically")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AmpXReferenceRendering")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("player-static.png")
        try firstPNG.write(to: url)
        print("AMPX_REFERENCE_CAPTURE \(url.path) backingScale=\(window.backingScaleFactor)")
        let attachment = XCTAttachment(data: firstPNG, uniformTypeIdentifier: "public.png")
        attachment.name = "player-static.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        withExtendedLifetime(window) {}
    }

    /// Display-only values matching the reference EQ: gains derived from measured thumb centers.
    static let equalizerReference = EqualizerReferencePresentation(
        bandDecibels: [1.79, 0.15, -1.0, -2.34, -4.41, -3.19, -1.25, 0.33, 1.67, 3.07],
        preampDecibels: 0.82,
        isEnabled: true,
        isAutoEnabled: false
    )

    func testEqualizerStaticReferenceCaptureIsDeterministic() throws {
        let content = self.makeEqualizerContent()
        content.referencePresentation = Self.equalizerReference
        let module = AmpXModuleView(moduleID: .equalizer, content: content, skin: skin)
        let frame = CGRect(x: 0, y: 0, width: AmpXMetrics.compositionWidth, height: AmpXMetrics.equalizerHeight)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(module)
        module.applyLayout(frame: frame)

        try self.export(self.deterministicPNG(of: module), named: "eq-static.png", backingScale: window.backingScaleFactor)
        for (name, decibels) in [("eq-min.png", -12.0), ("eq-zero.png", 0.0), ("eq-max.png", 12.0)] {
            content.referencePresentation = EqualizerReferencePresentation(
                bandDecibels: Array(repeating: decibels, count: AmpXEQBands.bandCount),
                preampDecibels: decibels,
                isEnabled: false,
                isAutoEnabled: true
            )
            try self.export(self.deterministicPNG(of: module), named: name, backingScale: window.backingScaleFactor)
        }
        withExtendedLifetime(window) {}
    }

    /// Display-only rows, selection and readouts matching the reference Playlist.
    static let playlistReference = PlaylistReferencePresentation(
        rows: [
            .init(title: "Mori Calliope - Go-Getters", duration: "3:15"),
            .init(title: "CircusP - Goodbye", duration: "3:24"),
            .init(title: "AmaLee - Siren", duration: "4:02"),
            .init(title: "Crusher-P - Echo", duration: "3:50"),
            .init(title: "M83 - Midnight City", duration: "4:03"),
            .init(title: "Sunnexo - Please Wait", duration: "4:15"),
            .init(title: "Omaru Polka - Persona", duration: "4:56"),
        ],
        selectedIndex: 3,
        currentIndex: 3,
        elapsedTotalText: "0:00/27:45",
        remainingText: "-02:12"
    )

    func testPlaylistAndFullStackReferenceCapturesAreDeterministic() throws {
        let playlist = self.makePlaylistContent()
        playlist.referencePresentation = Self.playlistReference
        let single = AmpXModuleView(moduleID: .playlist, content: playlist, skin: self.skin)
        let singleFrame = CGRect(x: 0, y: 0, width: AmpXMetrics.compositionWidth, height: AmpXMetrics.playlistHeight)
        let singleWindow = NSWindow(contentRect: singleFrame, styleMask: .borderless, backing: .buffered, defer: false)
        singleWindow.contentView?.addSubview(single)
        single.applyLayout(frame: singleFrame)
        playlist.setRowViewportHeight(AmpXMetrics.defaultPlaylistViewportHeight)
        try self.export(self.deterministicPNG(of: single), named: "playlist-static.png", backingScale: singleWindow.backingScaleFactor)

        let layout = AmpXLayout.calculate(
            state: AmpXModuleOrder(),
            width: AmpXMetrics.compositionWidth,
            playlistViewportHeight: AmpXMetrics.defaultPlaylistViewportHeight,
            availableHeight: 10000
        )
        let stack = ReferenceStackView(frame: CGRect(x: 0, y: 0, width: AmpXMetrics.compositionWidth, height: layout.contentHeight))
        let window = NSWindow(contentRect: stack.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(stack)

        let player = self.makePlayerContent()
        player.referencePresentation = Self.playerReference
        let equalizer = self.makeEqualizerContent()
        equalizer.referencePresentation = Self.equalizerReference
        let stackPlaylist = self.makePlaylistContent()
        stackPlaylist.referencePresentation = Self.playlistReference
        let contents: [(AmpXModuleID, AmpXModuleContent)] = [(.player, player), (.equalizer, equalizer), (.playlist, stackPlaylist)]
        for (id, content) in contents {
            let module = AmpXModuleView(moduleID: id, content: content, skin: self.skin)
            stack.addSubview(module)
            try module.applyLayout(frame: XCTUnwrap(layout.frames[id]))
        }
        stackPlaylist.setRowViewportHeight(layout.playlistViewportHeight)
        XCTAssertEqual(layout.contentHeight, 754, accuracy: 0.01)
        try self.export(self.deterministicPNG(of: stack), named: "stack-static.png", backingScale: window.backingScaleFactor)
        withExtendedLifetime([singleWindow, window]) {}
    }

    func deterministicPNG(of view: NSView) throws -> Data {
        let first = try capture(view)
        let second = try capture(view)
        XCTAssertEqual(first.pixelsWide, Int(view.bounds.width * 2))
        XCTAssertEqual(first.pixelsHigh, Int(view.bounds.height * 2))
        let firstPNG = try XCTUnwrap(first.representation(using: .png, properties: [:]))
        let secondPNG = try XCTUnwrap(second.representation(using: .png, properties: [:]))
        XCTAssertEqual(firstPNG, secondPNG, "Frozen reference presentation must render identically")
        return firstPNG
    }

    func export(_ png: Data, named name: String, backingScale: CGFloat) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AmpXReferenceRendering")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try png.write(to: url)
        print("AMPX_REFERENCE_CAPTURE \(url.path) backingScale=\(backingScale)")
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func capture(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * 2),
            pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return try XCTUnwrap(rep.converting(to: .sRGB, renderingIntent: .default))
    }

    // MARK: - Helpers

    func makePlayerContent() -> PlayerModuleContent {
        let content = PlayerModuleContent(
            skin: skin,
            audioPlayer: AudioPlayer(installRemoteCommands: false),
            playlistManager: PlaylistManager(
                audioPlayer: MockAudioPlayer(),
                restoreBookmarks: false,
                restorePlaylist: false,
                alertPresenter: SilentPlaylistAlertPresenter()
            ),
            onToggleModule: { _ in }
        )
        content.frame = CGRect(
            x: 0,
            y: 0,
            width: AmpXMetrics.compositionWidth,
            height: AmpXMetrics.playerHeight - AmpXMetrics.headerHeight
        )
        return content
    }

    func makePlaylistContent() -> PlaylistModuleContent {
        let audioPlayer = AudioPlayer(installRemoteCommands: false)
        self.retainedPlayers.append(audioPlayer)
        return PlaylistModuleContent(
            skin: self.skin,
            manager: PlaylistManager(
                audioPlayer: MockAudioPlayer(),
                restoreBookmarks: false,
                restorePlaylist: false,
                alertPresenter: SilentPlaylistAlertPresenter()
            ),
            audioPlayer: audioPlayer
        )
    }

    func makeEqualizerContent() -> EqualizerModuleContent {
        let suite = "AmpXReferenceRenderingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let audioPlayer = AudioPlayer(
            installRemoteCommands: false,
            eqSettingsStore: EQSettingsStore(userDefaults: defaults, settingsKey: "settings", presetsKey: "presets")
        )
        let content = EqualizerModuleContent(skin: skin, audioPlayer: audioPlayer)
        content.frame = CGRect(
            x: 0,
            y: 0,
            width: AmpXMetrics.compositionWidth,
            height: AmpXMetrics.equalizerHeight - AmpXMetrics.headerHeight
        )
        self.retainedPlayers.append(audioPlayer)
        return content
    }

    func controlSliders(in root: NSView) -> [AmpXSlider] {
        self.allSubviews(of: root).compactMap { $0 as? AmpXSlider }.filter { !($0.superview is PositionBarView) }
    }

    private func positionSliders(in root: NSView) -> [AmpXSlider] {
        self.allSubviews(of: root).compactMap { $0 as? AmpXSlider }.filter { $0.superview is PositionBarView }
    }

    func allSubviews(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + self.allSubviews(of: $0) }
    }
}

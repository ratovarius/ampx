@testable import AmpX
import AppKit
import XCTest

// MARK: - Interactive states, UI scales and host states

extension AmpXReferenceRenderingTests {
    func testInteractiveStatesReturnToReferenceRendering() throws {
        let content = self.makePlayerContent()
        content.referencePresentation = Self.playerReference
        let module = AmpXModuleView(moduleID: .player, content: content, skin: self.skin)
        let frame = CGRect(x: 0, y: 0, width: AmpXMetrics.compositionWidth, height: AmpXMetrics.playerHeight)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(module)
        module.applyLayout(frame: frame)
        let reference = try self.deterministicPNG(of: module)

        let buttons = self.allSubviews(of: content).compactMap { $0 as? AmpXButton }
        let button = { (title: String) throws -> AmpXButton in
            try XCTUnwrap(buttons.first { $0.accessibilityTitle == title })
        }
        let previous = try button("Previous")
        let pause = try button("Pause")
        let stop = try button("Stop")
        let next = try button("Next")
        let volume = try XCTUnwrap(self.controlSliders(in: content).first)
        let enter = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
        let exit = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
        func mouse(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
        }

        previous.mouseEntered(with: enter)
        try pause.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: pause.frame.midX, y: pause.frame.midY)))
        stop.isEnabled = false
        next.showsFocusRing = true
        volume.showsFocusRing = true
        var active = Self.playerReference
        active.repeatEnabled = true
        content.referencePresentation = active
        let states = try self.deterministicPNG(of: module)
        XCTAssertTrue(previous.isHovered)
        XCTAssertTrue(pause.isPressed)
        XCTAssertNotEqual(states, reference, "Hover, pressed, disabled, focus and active states must be visible")
        try self.export(states, named: "player-interactive-states.png", backingScale: window.backingScaleFactor)

        previous.mouseExited(with: exit)
        try pause.mouseUp(with: mouse(.leftMouseUp, at: NSPoint(x: -1000, y: -1000)))
        stop.isEnabled = true
        next.showsFocusRing = false
        volume.showsFocusRing = false
        content.referencePresentation = Self.playerReference
        XCTAssertEqual(try self.deterministicPNG(of: module), reference, "Returning to reference state must restore the approved rendering")
        withExtendedLifetime(window) {}
    }

    func testModuleContentScalesDrawingAndHitTestingTogether() throws {
        try AmpXTestEnvironment.skipUnlessRetina()
        let content = self.makePlayerContent()
        let module = AmpXModuleView(moduleID: .player, content: content, skin: self.skin)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 700, height: 320),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let container = ReferenceStackView(frame: CGRect(x: 0, y: 0, width: 700, height: 320))
        window.contentView?.addSubview(container)
        container.addSubview(module)
        defer { withExtendedLifetime(window) {} }
        let play = try XCTUnwrap(self.allSubviews(of: content).compactMap { $0 as? AmpXButton }.first { $0.accessibilityTitle == "Play" })
        let reference = play.frame

        for scale: CGFloat in [0.85, 1, 1.35] {
            let frame = CGRect(
                x: 0,
                y: 0,
                width: AmpXMetrics.compositionWidth * scale,
                height: AmpXMetrics.playerHeight * scale
            )
            module.applyLayout(frame: frame)
            XCTAssertEqual(play.frame, reference, "Content must keep reference-point layout at scale \(scale)")
            let inModule = play.convert(play.bounds, to: module)
            XCTAssertEqual(inModule.width, reference.width * scale, accuracy: 0.01)
            XCTAssertEqual(inModule.minX, reference.minX * scale, accuracy: 0.01)
            XCTAssertEqual(inModule.minY, AmpXMetrics.headerHeight * scale + reference.minY * scale, accuracy: 0.01)
            XCTAssertLessThanOrEqual(content.frame.maxY, module.bounds.maxY + 0.01, "Content overflows the module at scale \(scale)")
            let center = CGPoint(x: inModule.midX, y: inModule.midY)
            // NSView.hitTest takes a point in the receiver's superview coordinates.
            let hit = container.hitTest(module.convert(center, to: container.superview))
            XCTAssertTrue(hit === play, "Hit testing at the Play button center returned \(String(describing: hit)) at scale \(scale)")
        }
    }

    func testSliderPointerKeyboardAndAccessibilityMappings() throws {
        let player = self.makePlayerContent()
        let equalizer = self.makeEqualizerContent()
        let horizontal = try XCTUnwrap(self.controlSliders(in: player).first)
        let vertical = try XCTUnwrap(
            self.allSubviews(of: equalizer).compactMap { $0 as? AmpXSlider }.first { $0.accessibilityTitle == "60 band" }
        )
        func key(_ code: UInt16) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
            ))
        }

        for slider in [horizontal, vertical] {
            let lower = slider.range.lowerBound
            let upper = slider.range.upperBound
            let (start, end) = slider.travel
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let name = slider.accessibilityTitle ?? "slider"
            XCTAssertEqual(slider.value(at: start), lower, accuracy: 0.0001, "\(name) start endpoint")
            XCTAssertEqual(slider.value(at: end), upper, accuracy: 0.0001, "\(name) end endpoint")
            XCTAssertEqual(slider.value(at: mid), (lower + upper) / 2, accuracy: 0.0001, "\(name) midpoint")
            let outsideLow = slider.isVertical ? CGPoint(x: start.x, y: start.y + 100) : CGPoint(x: start.x - 100, y: start.y)
            let outsideHigh = slider.isVertical ? CGPoint(x: end.x, y: end.y - 100) : CGPoint(x: end.x + 100, y: end.y)
            XCTAssertEqual(slider.value(at: outsideLow), lower, "\(name) drag beyond start clamps")
            XCTAssertEqual(slider.value(at: outsideHigh), upper, "\(name) drag beyond end clamps")

            slider.setValue((lower + upper) / 2, sendChange: false)
            var changes: [Double] = []
            slider.onChange = { changes.append($0) }
            let before = slider.value
            let increment = slider.step > 0 ? slider.step : (upper - lower) / 20
            XCTAssertTrue(try slider.handleArrowKey(key(126)))
            XCTAssertEqual(slider.value, before + increment, accuracy: 0.0001, "\(name) arrow up")
            XCTAssertTrue(try slider.handleArrowKey(key(125)))
            XCTAssertEqual(slider.value, before, accuracy: 0.0001, "\(name) arrow down")
            XCTAssertEqual(changes.count, 2)
            XCTAssertEqual(slider.accessibilityValue() as? Double, slider.value)
            XCTAssertEqual(slider.accessibilityMinValue() as? Double, lower)
            XCTAssertEqual(slider.accessibilityMaxValue() as? Double, upper)
        }

        // Real mouse press and drag through a module laid out at UI scale 1.35.
        let scaledContent = self.makePlayerContent()
        let module = AmpXModuleView(moduleID: .player, content: scaledContent, skin: self.skin)
        let scale: CGFloat = 1.35
        let frame = CGRect(x: 0, y: 0, width: AmpXMetrics.compositionWidth * scale, height: AmpXMetrics.playerHeight * scale)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(module)
        module.applyLayout(frame: frame)
        defer { withExtendedLifetime(window) {} }
        let volume = try XCTUnwrap(self.controlSliders(in: scaledContent).first)
        var reported: Double?
        volume.onChange = { reported = $0 }
        func mouse(_ type: NSEvent.EventType, at local: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: volume.convert(local, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
        }
        let (start, end) = volume.travel
        let hitPoint = module.convert(volume.convert(end, to: module), to: module.superview)
        XCTAssertTrue(module.hitTest(hitPoint) === volume, "Scaled click at the volume end point must reach the slider")
        try volume.mouseDown(with: mouse(.leftMouseDown, at: end))
        XCTAssertEqual(reported ?? -1, 1, accuracy: 0.0001)
        try volume.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: start.x - 200, y: start.y)))
        XCTAssertEqual(reported ?? -1, 0, accuracy: 0.0001)
        try volume.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: (start.x + end.x) / 2, y: start.y)))
        XCTAssertEqual(reported ?? -1, 0.5, accuracy: 0.0001)
        try volume.mouseUp(with: mouse(.leftMouseUp, at: end))
    }

    func testHostStateCaptures() throws {
        try self.exportComposition(named: "stack-default.png", state: AmpXModuleState())
        var collapsed = AmpXModuleState()
        collapsed.setCollapsed(.equalizer, true)
        try self.exportComposition(named: "stack-collapsed-eq.png", state: collapsed)
    }

    /// The default Winamp arrangement of separate module windows, captured as one image.
    private func exportComposition(named name: String, state: AmpXModuleState) throws {
        let layout = ReferenceStackView.defaultComposition(
            state: state,
            playlistViewportHeight: AmpXMetrics.defaultPlaylistViewportHeight,
            playlistWidth: AmpXMetrics.defaultPlaylistWidth
        )
        let container = ReferenceStackView(frame: CGRect(origin: .zero, size: layout.size))
        let window = NSWindow(contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(container)
        let modules = self.referenceModules()
        for (id, module) in modules {
            guard let frame = layout.frames[id] else { continue }
            module.setContentCollapsed(state.collapsed.contains(id))
            container.addSubview(module)
            module.applyLayout(frame: frame)
        }
        try self.export(self.deterministicPNG(of: container), named: name, backingScale: window.backingScaleFactor)
        withExtendedLifetime(window) {}
    }

    private func referenceModules() -> [AmpXModuleID: AmpXModuleView] {
        let player = self.makePlayerContent()
        player.referencePresentation = Self.playerReference
        let equalizer = self.makeEqualizerContent()
        equalizer.referencePresentation = Self.equalizerReference
        let playlist = self.makePlaylistContent()
        playlist.referencePresentation = Self.playlistReference
        return [
            .player: AmpXModuleView(moduleID: .player, content: player, skin: self.skin),
            .equalizer: AmpXModuleView(moduleID: .equalizer, content: equalizer, skin: self.skin),
            .playlist: AmpXModuleView(moduleID: .playlist, content: playlist, skin: self.skin),
        ]
    }
}

@testable import AmpX
import XCTest

@MainActor
final class AmpXKeyboardFocusTests: XCTestCase {
    func testStackWindowCanBecomeKey() throws {
        let hosts = self.makeHosts()
        hosts.showStack()

        let window = try XCTUnwrap(hosts.stackWindow)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
    }

    func testDetachedModuleWindowCanBecomeKey() throws {
        let hosts = self.makeHosts()
        hosts.showStack()
        hosts.detach(.equalizer, at: CGPoint(x: 400, y: 500), inheritedWidth: 490)

        let window = try XCTUnwrap(hosts.moduleView(for: .equalizer)?.window)
        XCTAssertFalse(window === hosts.stackWindow)
        XCTAssertTrue(window.canBecomeKey)
    }

    func testTheaterWindowCanBecomeKey() throws {
        let hosts = self.makeHosts(entheaEnabled: true)
        hosts.reopenModule(.enthea)
        let view = try XCTUnwrap(hosts.moduleView(for: .enthea))
        var presentation: NSApplication.PresentationOptions = []
        let controller = AmpXTheaterController(
            hosts: hosts,
            screenFrame: { CGRect(x: 0, y: 0, width: 1200, height: 800) },
            getPresentation: { presentation },
            setPresentation: { presentation = $0 }
        )
        controller.enter()
        defer { controller.exit() }

        let window = try XCTUnwrap(view.window)
        XCTAssertTrue(window.canBecomeKey)
    }

    func testMakingStackKeyDoesNotFocusAControl() throws {
        let hosts = self.makeHosts()
        hosts.showStack()
        let window = try XCTUnwrap(hosts.stackWindow)

        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        XCTAssertFalse(
            window.firstResponder is AmpXControlView,
            "first responder: \(String(describing: window.firstResponder))"
        )
    }

    /// A click must not move keyboard focus, or global shortcuts stop working after any mouse use.
    /// AppKit's current event identifies the click; `sendEvent` cannot be overridden for this
    /// because an isolated `@objc` override crashes on macOS 26.
    func testClicksRefuseFocusWhileKeyboardNavigationKeepsIt() {
        for mouseDown in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            XCTAssertFalse(AmpXControlView.acceptsFocus(isEnabled: true, currentEventType: mouseDown))
        }

        XCTAssertTrue(AmpXControlView.acceptsFocus(isEnabled: true, currentEventType: .keyDown))
        XCTAssertTrue(AmpXControlView.acceptsFocus(isEnabled: true, currentEventType: nil))
        XCTAssertFalse(AmpXControlView.acceptsFocus(isEnabled: false, currentEventType: nil))
    }

    func testKeyboardFocusStillReachesButton() {
        let (window, button) = self.makeWindowWithButton()

        XCTAssertTrue(window.makeFirstResponder(button))
        XCTAssertTrue(window.firstResponder === button)
    }

    func testReturnPressesFocusedButton() {
        let (window, button) = self.makeWindowWithButton()
        var fired = 0
        button.action = { fired += 1 }
        window.makeFirstResponder(button)

        let handled = self.dispatch(self.keyDown(keyCode: 36, characters: "\r"), in: window)

        XCTAssertTrue(handled)
        XCTAssertEqual(fired, 1)
    }

    func testSpaceTogglesPlaybackInsteadOfPressingFocusedButton() {
        let (window, button) = self.makeWindowWithButton()
        var fired = 0
        button.action = { fired += 1 }
        window.makeFirstResponder(button)

        let space = self.keyDown(keyCode: 49, characters: " ")
        XCTAssertEqual(AmpXKeyRouter.route(event: space, context: AmpXKeyRouter.focusContext(from: window)), .global)
        XCTAssertTrue(self.dispatch(space, in: window))
        XCTAssertFalse(button.performKeyEquivalent(with: space))
        XCTAssertEqual(fired, 0)
    }

    /// Uses a throwaway defaults suite so these tests never overwrite the running app's saved layout.
    private func makeHosts(entheaEnabled: Bool = false) -> AmpXHostCoordinator {
        let suite = "AmpXKeyboardFocusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        self.addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AmpXHostCoordinator(
            state: AmpXModuleOrder(),
            skin: ClassicModernSkin(),
            layoutStore: AmpXLayoutStore(defaults: defaults),
            entheaEnabled: entheaEnabled
        )
    }

    private func makeWindowWithButton() -> (NSWindow, AmpXButton) {
        let window = AmpXHostWindow(
            contentRect: CGRect(x: 200, y: 200, width: 200, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let button = AmpXButton(skin: ClassicModernSkin())
        button.frame = CGRect(x: 60, y: 30, width: 80, height: 40)
        window.contentView?.addSubview(button)
        return (window, button)
    }

    private func click(at point: CGPoint, in window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            )!
            window.sendEvent(event)
        }
    }

    private func dispatch(_ event: NSEvent, in window: NSWindow) -> Bool {
        AmpXKeyRouter.dispatch(
            event,
            context: AmpXKeyRouter.focusContext(from: window),
            window: window,
            audioPlayer: nil,
            playlistManager: nil,
            entheaTheater: nil
        )
    }

    private func keyDown(keyCode: UInt16, characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

/// Records whether a sibling control accepts focus at the moments AppKit handles a mouse-down,
/// whether the window delivers the click or only asks about first-mouse (inactive test host).
private final class MouseDownProbe: NSView {
    weak var control: AmpXControlView?
    private(set) var observedControlAcceptsFocus: [Bool] = []

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        self.record()
        return false
    }

    override func mouseDown(with _: NSEvent) {
        self.record()
    }

    private func record() {
        if let control {
            self.observedControlAcceptsFocus.append(control.acceptsFirstResponder)
        }
    }
}

import AppKit

/// Borderless host window that can still become key, so keyboard shortcuts and focus reach it.
/// Plain borderless `NSWindow`s refuse key and main status.
///
/// The overrides are `nonisolated`: AppKit reads and calls them from event routing and layer
/// display with no Swift task, and on macOS 26 an isolated `@objc` entry point crashes in
/// `swift_task_isCurrentExecutor` (see commit 5562af8). For the same reason this class must not
/// override `sendEvent`: that crashed under mouse-moved routing, and the click-focus rule lives in
/// `AmpXControlView` instead.
final class AmpXHostWindow: NSWindow {
    override nonisolated var canBecomeKey: Bool {
        true
    }

    override nonisolated var canBecomeMain: Bool {
        true
    }
}

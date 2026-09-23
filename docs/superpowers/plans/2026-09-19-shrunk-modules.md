# Functional Collapsed Modules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Make collapsed Player, Equalizer, and Playlist useful, interactive compact strips matching the reference and the user's confirmed behavior decisions.

**Architecture:** Keep `AmpXModuleOrder.collapsed` and existing window/module ownership. Add a retained compact presentation beside each module's expanded header/content, share Player presentation settings, and reuse existing audio models, transport actions, and Metal rendering. Route expanded and compact visibility separately; ENTHEA keeps its existing header-only collapse.

**Tech Stack:** Swift, AppKit, Core Graphics, Combine for discrete changes, the existing Metal mini renderer and audio feature bus, XCTest through the repository script, Pillow through the scripts uv environment for reference comparisons. No new runtime dependencies.

**Spec:** [Functional Collapsed Modules](../specs/2026-09-15-shrunk-modules-design.md), including the September 19 decisions. Read the spec and this plan together.

**Execution status, 2026-09-19:** All seven implementation tasks are complete. Player/shared treatment was approved before EQ/Playlist work. The full suite passes 724 tests, the independent review's five findings are resolved, and native/deterministic evidence is saved in [validation](shrunk-modules/validation.md). SwiftLint's five baseline errors and the disabled production ENTHEA feature are documented there. No merge or publication is part of this implementation.

## Global Constraints

- Player and EQ remain **490 logical points** wide.
- Playlist retains its chosen width in both expanded and compact presentations, with a **490 pt minimum and no maximum**, in docked and detached hosts.
- Vertically stacked modules touch **edge-to-edge, with no gap**. The **6 pt gap** applies only between the left column and docked ENTHEA.
- Player alone has Minimize / Expand / Close; EQ and Playlist have Expand / Close, without an empty minimize slot.
- Expanded and compact Player share visualizer style/palette and elapsed/remaining timer mode. The compact visualizer is not fixed to the pictured spectrum.
- Compact volume is warm-colored and continuous; compact balance is segmented green. Both fill to the thumb. Preserve expanded Player's full-length, value-colored tracks.
- Space remains global play/pause; Return/Enter activates focused controls.
- Retain existing audio/DSP, ENTHEA, menus, persistence identifiers, module commands, and expanded appearance. Do not introduce another audio analysis pipeline.
- Continuous work runs only in the visible presentation. Preserve the macOS 26 callback/executor precautions in `AmpXContinuousView`.
- Python runs through uv. Tests run through `./scripts/run-tests.sh`; do not substitute `swift test`.
- Never add `Co-Authored-By` to commits, PRs, or GitHub comments.
- Complete the concrete compact Player visual checkpoint before implementing the compact EQ/Playlist treatment.

## Review Focus

1. **Tiny adjacent controls:** the base control currently expands hit bounds; a click near Next must not minimize the window or activate the neighboring control. Pin to Task 3's actual `hitTest` checks.
2. **Loading, selection, and loaded track disagree:** compact Playlist must identify `AudioPlayer.currentTrack`, find that ID in the current list, and never display the selected row as the playing track. Pin to Task 6's summary and observation tests.
3. **A restored compact module starts hidden or occluded:** neither presentation may start a frame loop; visible compact Player must wake after the host returns. Pin to Tasks 4 and 7's independent visibility gates and display-link counters.
4. **Long or malformed display values:** negative hour-long timers, unknown/nonfinite durations, long Unicode titles, and thousands of playlist rows must not crash or overlap controls. Pin to Tasks 2 and 6's formatter and layout tests.
5. **An interaction crosses a presentation/host change:** collapsing during slider, seek, row, resize, or module dragging must cancel tracking; repeated detach/re-dock must preserve the same module and avoid duplicate observers. Pin to Tasks 4 and 7's cancellation and ownership tests.

---

## Starting point and execution order

Planning inspected `feature/ampx-ui` at `88684ef` and the reviewed spec changes in this worktree. Recheck HEAD and local changes at execution time; preserve unrelated work. This is already an isolated worktree.

Implement Tasks 1–4 in order. Task 4 ends with the first Player visual checkpoint. After that checkpoint, implement Tasks 5 and 6, then Task 7. EQ and Playlist body work is separate, but their shared host/chrome files make sequential execution preferable in this worktree.

This plan is not evidence of a successful build, test run, or visual approval. Record those during execution.

### Current implementation facts that shape the plan

- `AmpXModuleView.setContentCollapsed` only hides expanded content and focuses its header. `focusableViews()` still returns hidden controls.
- `AmpXLayout.moduleHeight` returns `AmpXMetrics.headerHeight` for every collapsed module. Width already uses the stored Playlist width in either presentation.
- `AmpXHostCoordinator.refreshEffectiveVisibility` calls only `moduleView.content.setEffectivelyVisible(inputs.isVisible)`.
- `PlayerModuleContent` privately owns visualizer settings/persistence. `TimeDisplayView` owns its own elapsed/remaining boolean.
- `SpectrumWellView.spectrumRect` and L/R labels use expanded-only coordinates. Setting its old `reference` property bypasses Metal and draws the old segmented spectrum.
- `AmpXSegmentDigits.cells` explicitly allows long strings to extend left of their frame. Compact timers need bounded, discrete digit styles.
- LIST OPTS is built inside `PlaylistFooterView`; its New List action also clears the existing selection. Share that menu action owner, not the hidden footer view.
- Unregistering `PlaylistKeyboardAdapter` alone does not prevent global key routing from choosing Playlist editing based on the focused module.
- `AmpXControlView.hitTest` expands control hit areas. Compact controls need explicit containment; disabling a control must not expose window dragging underneath.
- Xcode's source/test groups are filesystem synchronized. New Swift files in `Sources/` and `Tests/AmpXTests/` do not need manual project entries.
- The test wrapper currently ignores arguments. Task 1 adds argument forwarding so focused checks still generate fixtures and use the project script.

## File ownership

| Files | Responsibility |
| --- | --- |
| `Sources/Modules/Player/AmpXPlayerPresentationState.swift` (new) | Shared visualizer settings and timer display mode, with existing settings persistence |
| `Sources/Modules/Player/AmpXTransportActions.swift` (new) | Existing five transport closures shared by expanded and compact Player |
| `Sources/Modules/Player/PlayerModuleContent.swift` | Accept shared state, preserve expanded bindings and reference presentation |
| `Sources/Modules/Player/SpectrumWellView.swift` | Expanded/compact geometry; existing Metal rendering, fallback, selection, and lifecycle |
| `Sources/Modules/Player/TimeDisplayView.swift` | Shared timer mode, expanded/compact digit presentation, accessible toggle |
| `Sources/Modules/Player/AmpXCompactTimeLayout.swift` (new) | Safe compact time strings and bounded segment metrics |
| `Sources/Theme/AmpXCompactMetrics.swift` (new) | Measured compact geometry, chrome rectangles, heights, and Playlist stretching |
| `Sources/Components/AmpXCompactModuleView.swift` (new) | Shared compact frame/branding/chrome, grip routing, focusable controls |
| `Sources/Modules/Player/PlayerCompactContent.swift` (new) | Compact transport, timer, and visualizer composition |
| `Sources/Modules/Equalizer/EqualizerCompactContent.swift` (new) | Master volume and balance bindings |
| `Sources/Theme/AmpXCompactSliderDrawing.swift` (new) | Mockup-style fill and thumb drawing, without changing expanded track drawing |
| `Sources/Modules/Playlist/PlaylistCompactContent.swift` (new) | Discrete summary observation, stretched well, List Options button |
| `Sources/Modules/Playlist/AmpXCompactPlaylistSummary.swift` (new) | Loaded-track identity, index, title/duration formatting and column geometry |
| `Sources/Modules/Playlist/PlaylistListOptionsMenu.swift` (new) | Shared New/Save/Load List menu and retained targets |
| `Sources/Components/AmpXModuleView.swift`, `Sources/Modules/AmpXEffectiveVisibility.swift`, `Sources/Windows/AmpXHostCoordinator.swift` | Presentation selection, visibility, focus, construction, and coordinator actions |
| `Sources/Modules/AmpXLayout.swift`, `Sources/Windows/AmpXStackWindowController.swift`, `Sources/Windows/AmpXDetachedModuleWindowController.swift` | Compact heights, existing retained Playlist width, top-edge anchoring, resize constraints |
| `Sources/Components/AmpXControlView.swift`, `Sources/Components/AmpXSlider.swift`, `Sources/Utilities/AmpXKeyRouter.swift` | Bounded hit areas, compact artwork/accessibility, focused activation and hidden-row exclusion |
| `Tests/AmpXTests/AmpXCompactCaptureSupport.swift` (new) | Deterministic AppKit capture and compositing of the actual offscreen Metal output |
| `Tests/AmpXTests/AmpXReferenceRenderingTests+Compact.swift` (new) | Compact and mixed-stack captures using production views |
| `scripts/measure_compact_reference.py` (new), `docs/superpowers/plans/shrunk-modules/` (new) | Source measurements, crops, comparisons, and validation evidence |

Each task below lists its tests and any additional touched files. Short source basenames in the tasks refer to the paths in this map; short test basenames are under `Tests/AmpXTests/`. Additional control files are under `Sources/Components/`, and `AmpXModuleContent.swift` is under `Sources/Modules/`.

### Task 1: Share Player presentation state and existing transport actions

**Files:** Create `AmpXPlayerPresentationState.swift`, `AmpXTransportActions.swift`, and `Tests/AmpXTests/AmpXPlayerPresentationStateTests.swift`. Modify `PlayerModuleContent.swift`, `TimeDisplayView.swift`, `Sources/Windows/AmpXHostCoordinator.swift`, and `scripts/run-tests.sh`. Retain existing `AmpXPlayerBindingTests` and `AmpXPlayerMiniVisualizerWiringTests`.

**Interfaces produced:**

```swift
import Combine
import Foundation

@MainActor
final class AmpXPlayerPresentationState: ObservableObject {
    @Published private(set) var visualizerSettings: AmpXMiniVisualizerSettings
    @Published private(set) var showRemainingTime = false
    private let store: AmpXMiniVisualizerSettingsStore

    init(store: AmpXMiniVisualizerSettingsStore = .init()) {
        self.store = store
        self.visualizerSettings = store.load()
    }

    func setVisualizerSettings(_ value: AmpXMiniVisualizerSettings) {
        guard value != visualizerSettings else { return }
        visualizerSettings = value
        store.save(value)
    }

    func setRemainingTime(_ value: Bool) {
        guard value != showRemainingTime else { return }
        showRemainingTime = value
    }

    func toggleTimeMode() {
        setRemainingTime(!showRemainingTime)
    }
}
```

`PlayerModuleContent` gains a trailing `presentationState: AmpXPlayerPresentationState? = nil` initializer argument. Keep its existing `settingsStore` argument for current callers; use it to construct state only when none was injected. Expose the resolved `let presentationState` internally. `TimeDisplayView` accepts `init(skin:presentationState:)`, while its existing `init(skin:)` remains a convenience path for standalone callers.

- [x] **1. Preserve the wrapper's default invocation and add forwarding.** Append `"$@"` after `ONLY_ACTIVE_ARCH=YES` in `scripts/run-tests.sh`. Run `bash -n scripts/run-tests.sh`, then run the baseline `./scripts/run-tests.sh` and record actual failures/counts before changing Player behavior. Do not treat pre-existing failures as compact regressions.

```bash
xcodebuild test \
    -project AmpX.xcodeproj \
    -scheme AmpX \
    -destination "platform=macOS,arch=${ARCH}" \
    ONLY_ACTIVE_ARCH=YES "$@"
```

- [x] **2. Write tests for shared state and real timer views.** Include the following test in an `@MainActor` XCTestCase, with `@testable import AmpX`, AppKit, and XCTest imports. Also test that loading/attaching views does not overwrite saved selections; setting the same settings twice causes one observed change; changing settings preserves timer mode; a fresh state retains the current elapsed default.

```swift
func testTwoTimerViewsShareTheModeInBothDirections() {
    let suite = "AmpXPlayerPresentationStateTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = AmpXPlayerPresentationState(
        store: AmpXMiniVisualizerSettingsStore(defaults: defaults)
    )
    let first = TimeDisplayView(skin: ClassicModernSkin(), presentationState: state)
    let second = TimeDisplayView(skin: ClassicModernSkin(), presentationState: state)
    first.showRemainingTime = true
    XCTAssertTrue(second.showRemainingTime)
    second.showRemainingTime = false
    XCTAssertFalse(first.showRemainingTime)
}
```

- [x] **3. Run the new tests before implementation.** Use `./scripts/run-tests.sh -only-testing:AmpXTests/AmpXPlayerPresentationStateTests`. Record compilation failures for absent interfaces separately from failing assertions; once the interfaces compile, demonstrate the synchronization assertion fails with independent timer state.

- [x] **4. Implement and inject one state per Player module.** The coordinator owns the state and passes it to the expanded Player now and compact Player in Task 3. Move settings load/save ownership from `PlayerModuleContent` to the shared state. Subscribe once per view lifetime using Combine payloads, not rereads inside `@Published`'s will-set delivery. Set `SpectrumWellView.settings` from the shared publisher and route `onSettingsChanged` back to `setVisualizerSettings`. Equality guards prevent echo writes. Replace the timer's stored boolean with a forwarding property and a retained subscription that invalidates its bounds.

```swift
// TimeDisplayView, after storing the injected presentationState:
var showRemainingTime: Bool {
    get { presentationState.showRemainingTime }
    set { presentationState.setRemainingTime(newValue) }
}

// Both Player presentations use this binding pattern.
presentationState.$visualizerSettings
    .removeDuplicates()
    .sink { [weak spectrumWell] value in spectrumWell?.settings = value }
    .store(in: &cancellables)
spectrumWell.onSettingsChanged = { [weak presentationState] value in
    presentationState?.setVisualizerSettings(value)
}
```

- [x] **5. Extract only the five common transport actions.** Keep shuffle, repeat, eject, and expanded-only menus where they are. Replace the corresponding branches in expanded `transportAction(for:)` with this helper; compact Player consumes it in Task 3.

```swift
@MainActor
enum AmpXTransportActions {
    static func make(
        for icon: AmpXIcon,
        audioPlayer: AudioPlayer,
        playlistManager: PlaylistManager
    ) -> (() -> Void)? {
        switch icon {
        case .previous: return { [weak playlistManager] in playlistManager?.previous() }
        case .play: return { [weak audioPlayer] in audioPlayer?.playOrResume() }
        case .pause: return { [weak audioPlayer] in audioPlayer?.pause() }
        case .stop: return { [weak audioPlayer] in audioPlayer?.stop() }
        case .next: return { [weak playlistManager] in playlistManager?.next() }
        default: return nil
        }
    }
}
```

- [x] **6. Verify and commit this extraction.** Run the state, existing binding, existing wiring, and reference-rendering suites through the wrapper. Expanded reference geometry and settings migration must remain unchanged. Commit only this task's paths with `refactor(ui): share Player presentation state and transport actions`.

### Task 2: Make visualizer and timer drawing fit a compact host

**Files:** Modify `SpectrumWellView.swift` and `TimeDisplayView.swift`; create `AmpXCompactTimeLayout.swift` and `Tests/AmpXTests/AmpXCompactDisplayTests.swift`. Extend `AmpXMiniVisualizerMetalTests.swift`.

**Consumes:** `AmpXPlayerPresentationState` from Task 1; existing `AmpXMiniVisualizerRenderer.renderOffscreen(_:style:palette:width:height:) -> MTLTexture`.

**Interfaces produced:**

- `SpectrumWellView.Geometry`: `.expanded` and `.compact`; mutable `geometry`, default `.expanded`.
- `TimeDisplayView.Style`: `.expanded` and `.compact`; mutable `style`, default `.expanded`.
- `AmpXCompactTimeLayout.text(current: TimeInterval, duration: TimeInterval, remaining: Bool, hasLoadedTrack: Bool) -> String`.
- `AmpXCompactTimeLayout.metrics(for: String, in: CGRect) -> AmpXSegmentDigits.Metrics`.
- `TimeDisplayView.performKeyboardPress() -> Bool`: toggles shared mode and returns true.

- [x] **1. Add formatter and bounded-cell tests.** Verify `00:00`, `01:51`, `59:59`, `1:00:00`, `100:00:00`, signed remaining equivalents, no loaded track, unavailable duration, negative current time, and NaN/infinity. Select among discrete digit styles instead of stretching cells with each time string.

```swift
func testNegativeLongTimerFitsInsideItsOwnRectangle() {
    let rect = CGRect(x: 0, y: 0, width: 52, height: 18)
    let text = AmpXCompactTimeLayout.text(
        current: 0, duration: 360_000, remaining: true, hasLoadedTrack: true
    )
    XCTAssertEqual(text, "-100:00:00")
    let metrics = AmpXCompactTimeLayout.metrics(for: text, in: rect)
    let cells = AmpXSegmentDigits.cells(for: text, in: rect, metrics: metrics)
    XCTAssertTrue(cells.allSatisfy { rect.contains($0.rect) })
    for pair in zip(cells, cells.dropFirst()) {
        XCTAssertFalse(pair.0.rect.intersects(pair.1.rect))
    }
}
```

Add `testCompactSpectrumUsesOnlyItsBounds`: a `.compact` well sized 110×18 must have `spectrumRect == bounds`, including after resizing and backing-scale changes; expanded geometry must still equal the existing metrics offset.

- [x] **2. Run focused tests and record the failing behavior.** Run `./scripts/run-tests.sh -only-testing:AmpXTests/AmpXCompactDisplayTests -only-testing:AmpXTests/AmpXMiniVisualizerIntegrationTests`.

- [x] **3. Add the geometry switch without duplicating the renderer.** Compact `spectrumRect` is `bounds`; expanded keeps its current rect. Draw L/R surrounding labels only for `.expanded`. Size the Metal child and fallback drawing from `spectrumRect`. In compact fallback, derive segment pitch/width/height from that rectangle; preserve exact expanded calculations.

```swift
enum Geometry { case expanded, compact }

var spectrumRect: CGRect {
    switch geometry {
    case .expanded:
        return AmpXMetrics.playerSpectrum.offsetBy(
            dx: -AmpXMetrics.playerDisplayWell.minX,
            dy: -AmpXMetrics.playerDisplayWell.minY
        )
    case .compact:
        return bounds
    }
}
```

Setting geometry requests layout/redraw. Keep all eight styles, five palettes, fallback behavior, click/double-click, pause/park/wake, and frame submission in the existing host/renderer. Do not use the old `reference` property for new compact Metal captures.

- [x] **4. Implement safe compact formatting and fixed digit styles.** Keep `AmpXTimeFormatting` and expanded rendering unchanged. Guard nonfinite/unrepresentable inputs before integer conversion, clamp negative current time to zero, and clamp remaining to zero when current exceeds duration. Return `00:00` for no track or unavailable remaining duration. Format hours as `h:mm:ss` and shorter values as `mm:ss`.

```swift
// After input validation and choosing elapsed or remaining seconds:
let total = Int(seconds)
let hours = total / 3600
let minutes = (total / 60) % 60
let remainder = total % 60
let body = hours > 0
    ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
    : String(format: "%02d:%02d", total / 60, remainder)
return remaining ? "-" + body : body
```

Start compact normal/hour/long-hour digit cells with these explicit styles. These are initial drawing values, finalized against Task 3's measured timer rectangle. Choose the largest whose complete cell union fits; preserve aspect ratio within each style and include the minus sign in fitting. Ensure the defined 100-hour case fits at the final reference width.

```swift
static let digitStyles: [AmpXSegmentDigits.Metrics] = [
    .init(digitSize: CGSize(width: 7.8, height: 13.5), gap: 0.8,
          colonWidth: 3, minusWidth: 4, stroke: 1.2, joint: 0.3,
          colonDot: CGSize(width: 1.5, height: 1.5)),
    .init(digitSize: CGSize(width: 6, height: 10.4), gap: 0.6,
          colonWidth: 2.3, minusWidth: 3.1, stroke: 0.92, joint: 0.23,
          colonDot: CGSize(width: 1.15, height: 1.15)),
    .init(digitSize: CGSize(width: 4.3, height: 7.45), gap: 0.45,
          colonWidth: 1.65, minusWidth: 2.2, stroke: 0.66, joint: 0.165,
          colonDot: CGSize(width: 0.83, height: 0.83)),
]
```

- [x] **5. Add compact timer activation and production Metal capture checks.** `mouseDown`, keyboard activation, and `accessibilityPerformPress` call the same shared toggle. Expose a mode label/value without posting time changes every frame. Use `renderOffscreen` at compact dimensions for every style/palette; require opaque, finite output and distinguish signal from silence. Reuse existing test signal setup, but do not impose large-display pixel thresholds on tiny outputs.

```swift
@discardableResult
func performKeyboardPress() -> Bool {
    presentationState.toggleTimeMode()
    return true
}
```

- [x] **6. Verify and commit.** Run compact display, mini-visualizer integration/Metal, Player wiring, and expanded reference-rendering tests. Commit with `feat(ui): support compact Player display geometry`.

### Task 3: Build measured compact chrome and the Player strip

**Files:** Create `AmpXCompactMetrics.swift`, `AmpXCompactModuleView.swift`, `PlayerCompactContent.swift`, `AmpXCompactCaptureSupport.swift`, `AmpXReferenceRenderingTests+Compact.swift`, `Tests/AmpXTests/AmpXCompactChromeTests.swift`, `Tests/AmpXTests/AmpXCompactPlayerTests.swift`, and `scripts/measure_compact_reference.py`. Modify `AmpXControlView.swift` and `.gitignore`. Create measurement evidence under `docs/superpowers/plans/shrunk-modules/`.

**Consumes:** Task 1 state/actions; Task 2 compact display geometry.

**Interfaces produced:**

- `AmpXCompactMetrics.playerHeight`, `equalizerHeight`, `playlistHeight`: logical measured heights.
- `AmpXCompactMetrics.Chrome`: `grip`, `brand`, `separators`, `minimize: CGRect?`, `expand`, `close`.
- `AmpXCompactMetrics.PlayerLayout`: `chrome`, `well`, `visualizer`, `timer`, `transport: [CGRect]`, `transportGlyphs: [CGRect]`; `static func playerLayout() -> PlayerLayout`.
- `AmpXCompactModuleView: AmpXModuleContent`: `init(moduleID: AmpXModuleID, skin: any AmpXSkin)`, retained module ID; `expandButton`, `closeButton`, optional `minimizeButton`; closures `onExpand`, `onClose`, `onMinimize` of type `(() -> Void)?`, and `onGripMouseDown`, `onGripMouseDragged`, `onGripMouseUp` of type `((NSEvent) -> Void)?`; `cancelInteraction()`.
- The shell exposes overridable `chromeLayout: AmpXCompactMetrics.Chrome` and `protectedRects: [CGRect]`. Subclasses provide their current measured chrome and the wells/control cells that cannot initiate background dragging.
- `PlayerCompactContent.init(skin:audioPlayer:playlistManager:presentationState:onToggleModule:)`; internally readable `spectrumWell`, `timeDisplay`, and `transportButtons`.
- `AmpXControlView.confinesHitTestingToBounds: Bool = false`; compact controls opt in, expanded controls retain current behavior.
- `AmpXControlView.focusRingInset: CGFloat = -2`; compact controls use a positive inset to keep their focus ring inside their cell.
- Test helper `AmpXCompactCaptureSupport.capture(_: NSView, scale: CGFloat, visualizer: SpectrumWellView?, frame: AmpXMiniVisualizerFrame?, settings: AmpXMiniVisualizerSettings?) throws -> Data`, returning PNG data.

- [x] **1. Preserve the source and record measurements.** Replace the ignored directory entry `screenshots/` with `screenshots/*` and add `!screenshots/shrinked_modules.png`, keeping other scratch images ignored. The source restored during review has SHA-256 `d792a98ad96ae4d0792251256a644081c1f3fa08b4a5970e7d796e4f78781aed` and size 1415×1111; remeasure if it changes.

The measurement script must take `source` and `--output`, record source hash, source-pixel rectangles, crop origins, normalization, colors, and uncertainties in JSON, and produce annotated/cropped PNGs. Use these initial crop estimates only to begin inspection:

```python
CROPS = {
    "player": (28, 276, 1361, 84),
    "equalizer": (28, 557, 1361, 84),
    "playlist": (28, 832, 1361, 76),
}

def logical_rect(source_rect, crop):
    x, y, width, height = source_rect
    cx, cy, crop_width, _ = crop
    factor = 490 / crop_width
    return [(x - cx) * factor, (y - cy) * factor,
            width * factor, height * factor]
```

Measure Player borders, bevel layers, glyphs, wordmark, separators, well, timer, each transport face, and each trailing button before setting Swift rectangles. Keep the different strip heights; approximate 30.25/30.25/27.5 pt are not approved final measurements. Run from `scripts/`:

```bash
uv run python measure_compact_reference.py ../screenshots/shrinked_modules.png --output ../docs/superpowers/plans/shrunk-modules/reference
```

- [x] **2. Write actual hit-testing and action tests.** Construct `PlayerCompactContent` with isolated Player state and the existing AudioPlayer/PlaylistManager spy pattern from `AmpXPlayerBindingTests`. Invoke each of the five buttons and require exactly the corresponding model action. Require all glyph and face rectangles inside their hit cell/module. For chrome buttons, test both active and disabled states.

```swift
func testCompactControlDoesNotCaptureItsNeighborsPoint() {
    let root = NSView(frame: CGRect(x: 0, y: 0, width: 60, height: 24))
    let first = AmpXButton(skin: ClassicModernSkin())
    let second = AmpXButton(skin: ClassicModernSkin())
    first.frame = CGRect(x: 0, y: 0, width: 20, height: 24)
    second.frame = CGRect(x: 22, y: 0, width: 20, height: 24)
    first.confinesHitTestingToBounds = true
    second.confinesHitTestingToBounds = true
    root.addSubview(first)
    root.addSubview(second)
    XCTAssertNil(first.hitTest(CGPoint(x: 21, y: 12)))
    XCTAssertIdentical(root.hitTest(CGPoint(x: 23, y: 12)), second)
}
```

Also enumerate Player chrome versus EQ/Playlist chrome layouts: Player has three trailing controls, the others exactly two. No minimize rectangle, target, accessible element, or reserved blank slot may exist for non-Player modules.

- [x] **3. Run the focused tests before implementing the strip.** Use `./scripts/run-tests.sh -only-testing:AmpXTests/AmpXCompactChromeTests -only-testing:AmpXTests/AmpXCompactPlayerTests`.

- [x] **4. Implement the shared shell and compact Player.** Draw the shell/frame/slanted wordmark/separators with existing skin primitives and font; add real `AmpXButton` chrome and transport controls. Keep per-control artwork separate from hit cells. Make all compact hit cells bounded and focus rings fit inside the strip. Base shell `mouseDown` uses the grip callbacks for module dragging, consumes inert wells/control regions, and uses `window?.performDrag(with:)` only on the allowed background/branding/separator region.

```swift
// AmpXControlView.hitTest, after its existing enabled/hidden guards:
let localPoint = superview.map { convert(point, from: $0) } ?? point
let hitRect = confinesHitTestingToBounds
    ? bounds
    : AmpXControlMath.expandedHitRect(for: bounds)
return hitRect.contains(localPoint) ? self : nil
```

The shell must separately exclude disabled control rectangles from background dragging. `PlayerCompactContent` lays out the measured single well, sets `.compact` display geometry/styles, binds the shared state, and uses `AmpXTransportActions.make`. Subscribe once to playback state and forward it to the compact visualizer even while hidden so pause/resume notifications stay correct. Frame submission remains visibility gated. Override `focusableControls()` to include the timer and visualizer actions plus visible chrome/transport in spatial order.

Update the control base's focus-ring rectangle to `bounds.insetBy(dx: focusRingInset, dy: focusRingInset)` and set compact controls to an inset of 1 pt. Keep the default expanded appearance unchanged.

- [x] **5. Produce deterministic compact Player comparisons using the actual renderer.** AppKit bitmap capture does not reliably include a Metal child. In the test-only capture helper, capture chrome/text/buttons via `cacheDisplay`, then composite `renderOffscreen` output at `visualizer.convert(visualizer.spectrumRect, to: root)`, using the same backing scale and recorded BGRA/orientation conversion. This reuses production drawing/shaders; it is not a second spectrum renderer. Keep live-window screenshots as separate evidence.

```swift
// The existing renderer returns a completed, CPU-readable texture.
let texture = try renderer.renderOffscreen(
    frame, style: settings.style, palette: settings.palette,
    width: Int((visualizer.spectrumRect.width * scale).rounded()),
    height: Int((visualizer.spectrumRect.height * scale).rounded())
)
```

Use `01:51`, active Play, and a fixed prepared signal frame. Choose and record `.dotSpectrum`/`.classic` for the first reference-like comparison, but record the approved difference from the old pictured spectrum. Never write capture settings to the user's defaults. Export native-size results, aspect-preserving normalized reference, side-by-side, and 50% overlay. Compare material layers and every control before Task 4's live checkpoint. The original expanded captures must remain unchanged.

- [x] **6. Verify and commit.** Run compact chrome/Player/display and expanded reference-rendering tests; inspect exported PNGs. Commit the source reference, measurement script/evidence, and code with `feat(ui): draw functional compact Player and shared chrome`. Do not mark the Player visual checkpoint approved yet.

### Task 4: Activate compact Player through the existing hosts

**Files:** Modify `AmpXModuleView.swift`, `AmpXModuleContent.swift`, `AmpXEffectiveVisibility.swift`, `AmpXLayout.swift`, `AmpXHostCoordinator.swift`, `AmpXStackWindowController.swift`, `AmpXDetachedModuleWindowController.swift`, `AmpXControlView.swift`, `AmpXButton.swift`, `AmpXSlider.swift`, `Sources/Modules/Player/PositionBarView.swift`, `Sources/Modules/Playlist/PlaylistRowsView.swift`, `Sources/Modules/Playlist/PlaylistResizeHandleView.swift`, and `AmpXKeyRouter.swift`. Create `Tests/AmpXTests/AmpXCompactHostTests.swift`, `AmpXCompactVisibilityTests.swift`, and `AmpXCompactKeyboardTests.swift`. Extend compact reference captures.

**Consumes:** Tasks 1–3's state, measured Player, shell, and capture helpers.

**Interfaces produced:**

- `AmpXPresentationVisibility: Equatable`, with `expanded: Bool`, `compact: Bool`.
- `AmpXVisibilityInputs.hostVisible: Bool` and `presentationVisibility(hasCompactPresentation: Bool) -> AmpXPresentationVisibility`; keep `isVisible` as the existing expanded predicate.
- `AmpXModuleView.init(moduleID:content:skin:compactContent: AmpXCompactModuleView? = nil)` and internally readable `compactContent`.
- `AmpXModuleView.applyPresentationVisibility(_:)`, `preferredFocusView: NSView`, and `isContentCollapsed: Bool` derived from the content's hidden state.
- `AmpXModuleView.snappedFrame(_: CGRect, backingScale: CGFloat) -> CGRect`, a static helper that aligns shared edges rather than rounding position and size independently.
- `AmpXModuleContent.cancelInteractions()`; `AmpXControlView.cancelInteraction()` defaults to no action and is overridden by tracking controls.
- `AmpXFocusContext.playlistEditingEnabled: Bool = true` for existing direct test callers; actual window context derives it from expanded Playlist visibility.

- [x] **1. Write independent visibility tests before changing the predicate.** Cover every host gate in both presentations, and ensure `hasCompactPresentation == false` never wakes collapsed ENTHEA. Keep the existing `AmpXEffectiveVisibilityTests` expectations for expanded content.

```swift
func testVisibleCollapsedPlayerRunsOnlyCompactPresentation() {
    var inputs = AmpXVisibilityInputs(
        collapsed: true, closed: false, windowVisible: true,
        miniaturized: false, occluded: false, intersectsViewport: true
    )
    XCTAssertEqual(
        inputs.presentationVisibility(hasCompactPresentation: true),
        AmpXPresentationVisibility(expanded: false, compact: true)
    )
    inputs.occluded = true
    XCTAssertEqual(
        inputs.presentationVisibility(hasCompactPresentation: true),
        AmpXPresentationVisibility(expanded: false, compact: false)
    )
    XCTAssertFalse(inputs.isVisible)
}
```

Add host tests for collapsing Player: its compact view fills the complete module bounds, expanded header/body are hidden, lower modules move, window top-left stays fixed when within the screen, and the same expanded body returns on expansion. Use an isolated layout store and non-remote-command audio models; close created windows in teardown. Install display-link starter/stopper counters on actual `AmpXContinuousView` instances, as in `AmpXEffectiveVisibilityTests`, to prove repeated visibility refreshes do not create extra links.

- [x] **2. Run the new host/visibility tests and capture failures.** Run `./scripts/run-tests.sh -only-testing:AmpXTests/AmpXCompactHostTests -only-testing:AmpXTests/AmpXCompactVisibilityTests`.

- [x] **3. Implement presentation visibility while preserving the old gate.**

```swift
var hostVisible: Bool {
    !closed && windowVisible && !miniaturized && !occluded && intersectsViewport
}

var isVisible: Bool { hostVisible && !collapsed }

func presentationVisibility(hasCompactPresentation: Bool) -> AmpXPresentationVisibility {
    AmpXPresentationVisibility(
        expanded: isVisible,
        compact: hostVisible && collapsed && hasCompactPresentation
    )
}
```

The coordinator computes this from its existing stack/detached/theater inputs and calls the module container. The container suspends the outgoing presentation before waking the incoming one. `AmpXModuleContent.setEffectivelyVisible` remains responsible for the expanded Playlist adapter/footer and ENTHEA's existing behavior. Do not remove the collapsed term globally.

- [x] **4. Construct and route compact Player without replacing module identity.** In `createModuleViews`, build compact Player with the same Player state and audio models, attach it hidden, wire coordinator actions, then apply restored collapse state. Use one coordinator closure set for expanded header and compact shell, including the existing Player minimize/hide behavior and grip callbacks.

```swift
func applyPresentationVisibility(_ value: AmpXPresentationVisibility) {
    // Stop first so transitions never run both presentation paths.
    if !value.expanded { content.setEffectivelyVisible(false) }
    if !value.compact { compactContent?.setEffectivelyVisible(false) }
    if value.expanded { content.setEffectivelyVisible(true) }
    if value.compact { compactContent?.setEffectivelyVisible(true) }
}
```

When collapsed with a compact view, hide the expanded header/body and lay out compact content over all module bounds. Preserve the expanded body's last valid frame/bounds instead of resizing it to zero; this protects scroll position and control geometry. ENTHEA and modules not yet activated keep the old header-only path.

Snap common boundaries, not each frame's origin and height independently. Otherwise fractional compact heights can leave a pixel gap between adjacent modules:

```swift
static func snappedFrame(_ frame: CGRect, backingScale: CGFloat) -> CGRect {
    let minX = AmpXPixelGrid.align(frame.minX, backingScale: backingScale)
    let minY = AmpXPixelGrid.align(frame.minY, backingScale: backingScale)
    let maxX = AmpXPixelGrid.align(frame.maxX, backingScale: backingScale)
    let maxY = AmpXPixelGrid.align(frame.maxY, backingScale: backingScale)
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}
```

Use this helper in `applyNormalLayout`. Add a test with sequential 30.25/30.25/27.5 pt frames at 1×/2×/3×: each snapped next `minY` equals the previous `maxY`, and width stays 490 pt. Preserve expanded 2× reference geometry.

For this commit only, `AmpXLayout.moduleHeight` uses `AmpXCompactMetrics.playerHeight` for collapsed Player; EQ/Playlist retain `headerHeight` until their real compact bodies are added in Tasks 5–6. Keep the width calculation unchanged. Recompute restored detached dimensions from current metrics, and ensure compact Playlist's eventual sub-header-height strip will not be inflated by old minimum-window constraints.

- [x] **5. Fix focus routing and cancellation as part of the transition.** `setContentCollapsed` cancels outgoing content/control tracking, preserves the focused expanded responder only if it belongs to this module, and focuses compact Expand only when this module owned focus. On expansion, restore the remembered valid responder; otherwise focus the normal header. Do not move focus from another module. `focusModule` uses `preferredFocusView`, and module accessibility actions expose Expand when compact.

`focusableViews()` returns only controls from the active presentation. Rebuild the traversal after switching; retain the same controls across reparenting. Classify timer and mini visualizer as button-like key targets, with Return/Enter invoking their action; Space still routes globally. Keep focused module identity for reorder/detach/collapse commands, but require `playlistEditingEnabled` before dispatching row navigation/deletion.

```swift
// In AmpXKeyRouter.route:
if context.module == .playlist,
   context.playlistEditingEnabled,
   matchesPlaylistKey(event, flags: flags) {
    return .playlist
}
```

Add no-op cancellation to the control base, reset `isDragging` on sliders, clear pending press reset/state on buttons, and cancel seek/row/resize tracking through `AmpXModuleContent.cancelInteractions()`. Its default implementation traverses descendant controls; specialized rows/resize views clear their own tracking. Override this method in `AmpXCompactModuleView` to call the base traversal and its own `cancelInteraction()` for grip state. The module drag session already has `cancelDragIfDragging`; retain it. Ensure a later mouse-up only activates a button that is still tracking its own press:

```swift
// AmpXButton.mouseUp:
let shouldFire = isPressed && isEnabled && bounds.contains(point)
```

Test collapse during a drag with further mouse-drag/mouse-up events: no further seek/volume/resize/reorder mutation may occur. Test Space versus Return on compact Stop/Expand; test focus in another module is not stolen.

- [x] **6. Verify the running Player and present its concrete visual checkpoint.** Run compact host/visibility/keyboard tests, existing module drag, Player bindings, accessibility, and reference-rendering tests. Launch with `./scripts/shoot.sh`, collapse Player through its actual control/command, exercise transport, style/palette, timer, window minimize/hide/reopen, and capture with `./scripts/shoot.sh --capture-only --output-prefix /tmp/ampx_compact_player`. Use Task 3's deterministic output for the normalized comparison and label the live capture separately.

Record native-size reference/result, overlay, build revision, measured dimensions, and remaining differences in `docs/superpowers/plans/shrunk-modules/validation.md`. Correct differences before presenting. Obtain the spec's approval of this concrete Player capture before Tasks 5–6; passing tests or generating files is not approval.

- [x] **7. Commit the verified Player integration.** Use `feat(ui): activate compact Player in existing module hosts`. Record the actual Player visual decision in the validation note; if it is still pending, do not begin the EQ/Playlist visual treatment.

### Task 5: Add compact Equalizer volume and balance

**Files:** Create `EqualizerCompactContent.swift`, `AmpXCompactSliderDrawing.swift`, and `Tests/AmpXTests/AmpXCompactEqualizerTests.swift`. Modify `AmpXCompactMetrics.swift`, `AmpXSlider.swift`, `AmpXHostCoordinator.swift`, `AmpXLayout.swift`, compact reference tests, and existing collapsed-EQ accessibility/height expectations.

**Consumes:** Approved Player shell/material treatment, shared coordinator actions, and presentation visibility.

**Interfaces produced:**

- `AmpXCompactMetrics.EqualizerLayout`: `chrome`, `volume`, `balance`, with track/thumb rectangles recorded separately; `equalizerLayout()`.
- `AmpXSlider.Artwork.compact(AmpXTrackFill)`.
- `AmpXCompactSliderDrawing.draw(track: CGRect, thumb: CGRect, fill: AmpXTrackFill, value: Double, skin: any AmpXSkin, context: CGContext, backingScale: CGFloat)`.
- `AmpXSlider.accessibilityStep: Double?`, `accessibilityRangeOverride: ClosedRange<Double>?`, `accessibilityValueFormatter: ((Double) -> Any)?`; defaults preserve expanded behavior.
- `EqualizerCompactContent.init(skin: any AmpXSkin, audioPlayer: AudioPlayer)`; internally readable `volumeSlider`, `balanceSlider`.

- [x] **1. Measure EQ artwork after the Player checkpoint.** Keep Expand/Close at the reference's right edge, remove the erroneous minimize button, and extend balance into the recovered space. Record the source and corrected layout separately. Measure the warm gradient, green segment spacing, tracks, thumb faces/grooves, and travel endpoints.

- [x] **2. Add binding and drawing tests.** Instantiate `AudioPlayer(installRemoteCommands: false)` with an isolated EQ settings store. Change compact controls at 0, 0.5, 1; verify normalized volume and balance mapping, actual model-driven updates back into the view, and no changes to preamp/bands/enabled/auto. Subscribe using expectations to discrete publishers instead of sleeping.

```swift
func testCompactBalanceCenterMapsToModelAndAccessibleCenter() {
    let suite = "AmpXCompactEqualizerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let player = AudioPlayer(
        installRemoteCommands: false,
        eqSettingsStore: EQSettingsStore(
            userDefaults: defaults, settingsKey: "settings", presetsKey: "presets"
        )
    )
    let compact = EqualizerCompactContent(skin: ClassicModernSkin(), audioPlayer: player)
    compact.balanceSlider.setValue(0.5, sendChange: true)
    XCTAssertEqual(player.balance, 0, accuracy: 0.0001)
    XCTAssertEqual(compact.balanceSlider.accessibilityValue() as? String, "Center")
}
```

Add actual pixel samples showing green balance fill, warm volume fill, black remainder, and steel thumb at min/center/max. Keep `AmpXSliderColorRampTests` unchanged to guard expanded behavior. Test thumb-center input mapping, control containment, disabled hit regions, scroll/arrow/accessible increments, and exactly two trailing chrome buttons in both hosts.

- [x] **3. Run the new tests, then implement the compact artwork and model binding.** Add one new slider drawing branch; do not modify `AmpXSkin.sliderTrack`'s existing full-length ramp. Clip compact fill at the thumb center and paint the thumb over it. At value zero draw no lit fill; center balance fills half the track. Anchor the warm gradient to the track, not the changing clip width. Draw green segments with their measured gap and retain the unlit remainder.

```swift
// EqualizerCompactContent control callbacks:
volumeSlider.onChange = { [weak audioPlayer] value in
    audioPlayer?.setVolume(Float(value))
}
balanceSlider.onChange = { [weak audioPlayer] value in
    audioPlayer?.setBalance(Float(value * 2 - 1))
}
```

Keep slider `step == 0` so pointer input is continuous. Set compact accessible increments to 0.05 without quantizing clicks. Expose volume as 0–100%, balance as left/center/right percentages, with corresponding accessible range; retain default accessibility behavior for existing EQ bands and expanded sliders.

- [x] **4. Activate EQ in both hosts and check focus/height.** Build its compact view in the coordinator, switch collapsed EQ height to the measured compact height, and retain the existing detach/re-dock and close/reopen behavior. Update the existing `testCollapseFallsBackToHeaderAndExpandRestoresContentFocus` expectation to compact Expand for EQ, and `testRepeatedDetachUsesCurrentCollapsedHeight` to the compact metric.

```swift
// Extend the collapsed module-height branch activated in Task 4:
switch moduleID {
case .player: return AmpXCompactMetrics.playerHeight
case .equalizer: return AmpXCompactMetrics.equalizerHeight
default: return AmpXMetrics.headerHeight
}
```

- [x] **5. Verify, compare, and commit.** Run compact EQ, slider ramp, accessibility, module-interaction, and compact/reference-rendering tests. Check that expanded Player sliders update when changed through compact EQ and the reverse. Capture docked/detached compact EQ and reference overlays, record differences/approval in the validation note, then commit with `feat(ui): add compact Equalizer volume and balance`.

### Task 6: Add compact Playlist summary and shared List Options

**Files:** Create `PlaylistCompactContent.swift`, `AmpXCompactPlaylistSummary.swift`, `PlaylistListOptionsMenu.swift`, and `Tests/AmpXTests/AmpXCompactPlaylistTests.swift`. Modify `PlaylistModuleContent.swift`, `PlaylistFooterView.swift`, `AmpXCompactMetrics.swift`, `AmpXHostCoordinator.swift`, `AmpXLayout.swift`, `AmpXDetachedModuleWindowController.swift`, and compact capture tests.

**Consumes:** Compact shell and active-presentation routing. Reuse the expanded Playlist's existing keyboard adapter for shared New List selection cleanup; do not register another adapter for compact content.

**Interfaces produced:**

- `AmpXCompactPlaylistSummary: Equatable`, fields `title: String`, `duration: String`.
- `static make(loadedTrack: Track?, tracks: [Track], loadedDuration: TimeInterval) -> AmpXCompactPlaylistSummary`.
- `AmpXCompactMetrics.PlaylistLayout`: `chrome`, `well`, `listOptions`; `playlistLayout(width: CGFloat)`.
- `AmpXCompactPlaylistSummary.textRects(in: CGRect, durationWidth: CGFloat) -> (title: CGRect, duration: CGRect)`.
- `PlaylistListOptionsMenu.init(manager: PlaylistManager, keyboardAdapter: PlaylistKeyboardAdapter)`, `makeMenu() -> NSMenu`, `show(relativeTo: AmpXButton)`.
- `PlaylistModuleContent.listOptionsMenu: PlaylistListOptionsMenu`; injected into both footer and compact content.
- `PlaylistCompactContent.init(skin:manager:audioPlayer:listOptionsMenu:)`, internally readable `summary`, `listOptionsButton`.

- [x] **1. Test loaded-track identity independently of current index/selection.** Include no track, missing metadata, reordered tracks, loaded track removed from the list, loaded track differing from manager's current index, unknown/nonfinite duration, long Unicode metadata, and original casing. Prefer valid `loadedDuration` for the loaded track; fall back to that track's metadata duration; otherwise use `--:--`.

```swift
func testLoadedTrackSummaryFollowsIdentityThroughReorderAndRemoval() {
    let first = Track(title: "First", artist: "Artist", duration: 100)
    let loaded = Track(title: "GOD DAMN", artist: "SLEAZE", duration: 226)
    let before = AmpXCompactPlaylistSummary.make(
        loadedTrack: loaded, tracks: [first, loaded], loadedDuration: 226
    )
    XCTAssertEqual(before.title, "2. SLEAZE - GOD DAMN")
    XCTAssertEqual(before.duration, "3:46")
    let reordered = AmpXCompactPlaylistSummary.make(
        loadedTrack: loaded, tracks: [loaded, first], loadedDuration: 226
    )
    XCTAssertEqual(reordered.title, "1. SLEAZE - GOD DAMN")
    let removed = AmpXCompactPlaylistSummary.make(
        loadedTrack: loaded, tracks: [first], loadedDuration: 226
    )
    XCTAssertEqual(removed.title, "SLEAZE - GOD DAMN")
}
```

Test observed view updates using `audioPlayer.currentTrack`/`duration` and manager tracks, without playing audio. Changing selection alone must not change the compact summary. Pause/stop retain the summary while `currentTrack` remains loaded.

- [x] **2. Add menu parity tests before extracting its owner.** Require exactly New List, Save List…, Load List… in the same order as the existing footer. Invoke the actual targets/selectors and verify New List clears both tracks and existing selection, Save calls `saveM3UPlaylist`, and Load calls `showLoadM3UPicker`. Use isolated persistence stores and spies so tests cannot modify the user's saved playlist or open file panels.

```swift
func testListOptionsMenuPreservesCommandOrderAndTarget() {
    let suite = "AmpXCompactPlaylistTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = PlaylistManager(
        audioPlayer: MockAudioPlayer(), restoreBookmarks: false, restorePlaylist: false,
        stateStore: PlaylistStateStore(userDefaults: defaults)
    )
    let adapter = PlaylistKeyboardAdapter(manager: manager)
    let owner = PlaylistListOptionsMenu(manager: manager, keyboardAdapter: adapter)
    let menu = owner.makeMenu()
    XCTAssertEqual(menu.items.map(\.title), ["New List", "Save List…", "Load List…"])
    XCTAssertTrue(menu.items.allSatisfy { $0.target === owner && $0.action != nil })
}
```

- [x] **3. Run focused tests, then share menu behavior and summary observation.** Move only List Options construction/actions into the retained menu owner. `PlaylistModuleContent` creates it with the existing manager/adapter and gives it to the footer and coordinator-created compact view. For `"LIST\nOPTS"`, the footer calls this owner; other footer menus stay unchanged. Preserve the selection notification when clearing a list and keep the target alive while the menu tracks.

```swift
// In the shared List Options owner:
@objc private func newList() {
    PlaylistChromeActions.clearList(
        manager: manager, selection: &keyboardAdapter.selection
    )
    keyboardAdapter.onSelectionChanged?()
}

func show(relativeTo button: AmpXButton) {
    makeMenu().popUp(
        positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button
    )
}
```

Compact summary observes loaded track, decoded duration, and list contents once per view lifetime; it has no display link. Use IDs to derive the index. Model notifications can arrive through `@Published` will-set, so derive a consistent snapshot after changes reach the main queue and avoid a stale duration/index from another track.

- [x] **4. Measure and implement the stretching compact layout.** Remove the erroneous minimize slot, shift List Options and its separator right, and extend the summary well. For additional Playlist width, keep brand/grip/type/buttons fixed and extend only the well; keep duration right-aligned in a separately measured column.

```swift
// Relative to the measured 490 pt Playlist layout:
let extra = max(0, width - AmpXMetrics.compositionWidth)
let stretchedWell = CGRect(
    x: referenceWell.minX, y: referenceWell.minY,
    width: referenceWell.width + extra, height: referenceWell.height
)
let listOptions = referenceListOptions.offsetBy(dx: extra, dy: 0)
```

Measure the formatted duration with the actual font, reserve that column before laying out the title, and clip title drawing to its own rectangle. Validate a 1000-row index and long Unicode title at 490 and 800 pt, plus long known durations and `--:--`; no wrapping or marquee. Expose summary as static text and List Options as a real button accessible by Return/Enter.

- [x] **5. Activate Playlist while retaining width and expanded state.** Add the compact view in the coordinator and finalize the collapsed height switch:

```swift
switch moduleID {
case .player: return AmpXCompactMetrics.playerHeight
case .equalizer: return AmpXCompactMetrics.equalizerHeight
case .playlist: return AmpXCompactMetrics.playlistHeight
case .enthea: return AmpXMetrics.headerHeight
}
```

Keep the existing preferred Playlist width as the single source for expanded and compact layouts. Disable edge/handle resizing while compact in both hosts without clamping the saved width. Ensure the detached minimum height allows the measured compact Playlist height even when shorter than the old 28.5 pt header. Preserve expanded selection, scroll offset, preferred viewport, and content instance across collapse/expand.

- [x] **6. Verify, compare, and commit.** Run compact Playlist, Playlist chrome actions, Playlist width/resize, keyboard, layout-store, and reference-rendering tests. Capture 490 pt and wide compact Playlist, docked and detached, with `7. SLEAZE - GOD DAMN` / `3:46`. Record geometry/visual differences and commit with `feat(ui): add compact Playlist summary and List Options`.

### Task 7: Verify the complete presentation lifecycle and visual matrix

**Files:** Extend `AmpXCompactHostTests.swift`, `AmpXCompactVisibilityTests.swift`, `AmpXCompactKeyboardTests.swift`, `AmpXReferenceRenderingTests+Compact.swift`, `AmpXModuleDragTests.swift`, and `AmpXModuleInteractionRegressionTests.swift`. Make any targeted fixes in the owning files above. Update `docs/superpowers/plans/shrunk-modules/validation.md` and add a cross-reference to the compact spec in `docs/superpowers/specs/2026-09-11-ampx-ui-design.md` so its older header-only/width statements do not mislead future work.

**Consumes:** All three active compact presentations; no new product interfaces.

- [x] **1. Add a complete composition test and restored-state cases.** Cover all eight collapse combinations, default and wide Playlist, reordered modules, closed/detached exclusions, and right-side ENTHEA. The expected height is the sum of the visible left modules, with no vertical gaps; with ENTHEA it is the larger column.

```swift
func testAllCollapseCombinationsKeepWidePlaylistAndVisualizerClear() throws {
    let ids: [AmpXModuleID] = [.player, .equalizer, .playlist]
    for mask in 0..<8 {
        var state = AmpXModuleOrder()
        state.reopen(.enthea)
        for (index, id) in ids.enumerated() {
            state.setCollapsed(id, mask & (1 << index) != 0)
        }
        let layout = AmpXLayout.calculate(
            state: state, width: 800,
            playlistViewportHeight: AmpXMetrics.defaultPlaylistViewportHeight,
            availableHeight: 10_000, playlistWidth: 800
        )
        let player = try XCTUnwrap(layout.frames[.player])
        let equalizer = try XCTUnwrap(layout.frames[.equalizer])
        let playlist = try XCTUnwrap(layout.frames[.playlist])
        XCTAssertEqual(equalizer.minY, player.maxY)
        XCTAssertEqual(playlist.minY, equalizer.maxY)
        XCTAssertEqual(playlist.width, 800)
        XCTAssertEqual(layout.frames[.enthea]?.minX, 806)
        XCTAssertEqual(layout.contentHeight, max(playlist.maxY, AmpXMetrics.entheaHeight))
    }
}
```

Add restart tests using old layout JSON and widened compact detached Playlist frames. Never trust saved expanded heights; preserve the preferred viewport and width. Check that closing a wide compact Playlist shrinks the remaining host and reopening restores it. Check that relayout does not reveal closed views or move detached views into the stack.

- [x] **2. Exercise visibility, cancellation, focus, and ownership through real containers.** Repeatedly collapse/expand, hide/show, minimize/restore, and detach/re-dock EQ/Playlist. Count display-link starts/stops with injected factories, not timing guesses. A hidden compact Player must submit no GPU frames; its expanded renderer must stay stopped while compact is visible. Verify pause/park, style changes while parked, seek/track discontinuities, and injected renderer failure.

Test disabled compact controls consume neither neighboring commands nor background drag. Test collapse during seek, slider, row-reorder, module-reorder, and resize tracking, then deliver late drag/up events. Test a retained focus target returns only if still valid and the transitioning module owns focus. Weak-reference tests must show shared state/bindings and compact views release with their module.

For collapsed Playlist, send Delete, arrows, Return, and reorder shortcuts from its compact controls: hidden rows do not change, focused controls get their intended action, and module commands still target Playlist. Space stays play/pause in each focus context. Test returning to expanded Playlist restores its keyboard adapter and prior selection.

- [x] **3. Run focused checks, fix their causes, then run the complete repository checks.**

```bash
./scripts/run-tests.sh -only-testing:AmpXTests/AmpXCompactHostTests -only-testing:AmpXTests/AmpXCompactVisibilityTests -only-testing:AmpXTests/AmpXCompactKeyboardTests -only-testing:AmpXTests/AmpXModuleDragTests
./scripts/run-tests.sh
./scripts/lint-swift.sh
```

Run `./scripts/format-swift.sh` if formatting is required, inspect its diff, and keep unrelated formatting out of this feature. Rerun affected checks after corrections; do not repeatedly rerun the full suite after it passes without new changes or failures. Record actual commands, revisions, result bundles, and any limitations.

- [x] **4. Capture and inspect the complete visual matrix.** Export deterministic 1×/2×/3× compact Player/EQ/Playlist, all-compact stack, mixed and reordered stacks, detached EQ/Playlist, wide Playlist, and compact left column beside expanded ENTHEA. Include long/signed timer and long-title cases. Use the actual offscreen Metal renderer for all eight compact styles and all five palettes at compact dimensions.

Use `./scripts/shoot.sh` and `--capture-only` for actual running-app evidence. Exercise pointer hit targets, focus, menus, volume/balance, timer mode, style/palette, resizing restrictions, window controls, and detach/re-dock. Label physical-display captures versus offscreen raster checks. Compare unchanged expanded panels at matching Playlist viewport/width and deterministic content.

Update `validation.md` with a row per required state: revision, logical size, backing scale, reference/result paths, observed differences, and actual review status. Keep original references; do not overwrite baseline images to conceal regressions.

- [x] **5. Reconcile documentation and finish the implementation review.** Add a short superseding cross-reference near the main UI spec's layout/lifecycle sections for compact presentation behavior, retained wide Playlist, and zero vertical gaps. Update this plan's checkboxes from actual evidence, not intention. Request the appropriate fresh code review of the final diff and resolve concrete findings, then rerun affected tests.

Commit verified final fixes/evidence with `test(ui): verify compact module lifecycle and visual regressions`. Report implementation status and remaining visual approvals accurately; do not merge, publish, or mark unresolved visual gates complete on the strength of unit tests alone.

## Plan self-review

- **Spec coverage:** geometry/material measurements and fixed-vs-stretched dimensions are in Tasks 2–3, 5–6; state/actions/observation in Tasks 1, 3–6; host sizing/visibility/drag/focus in Task 4; all combinations, restoration, accessibility, and final visual evidence in Task 7.
- **Interface consistency:** shared presentation state belongs to the Player/coordinator; compact modules reuse `AmpXCompactModuleView`; the legacy expanded visibility predicate remains; `PlaylistListOptionsMenu` is the only new owner of List Options commands.
- **Review focus coverage:** bounded hit testing in Task 3; loaded-track identity in Task 6; independent host gates in Task 4; long/malformed values in Tasks 2/6; cancellation and reparenting in Tasks 4/7.
- **Reference availability:** compact source is restored locally and preserved in Task 3. The old expanded `ampX_UI_v1.1.png` is missing; use existing approved expanded reference tests/crops and record a fresh current expanded baseline before comparing the implementation. Do not substitute the compact mockup for expanded appearance.
- **Execution recommendation:** implement in this session with a final independent review. The shared state, chrome, host transitions, and drawing contracts are tightly coupled; preserving one implementation context reduces interface drift. The Player visual checkpoint remains a required intermediate review.

# AmpX UI Migration Plan — Historical

> Superseded for execution by [the visual correction plan](./2026-09-11-ampx-ui.md) on 2026-09-12. This preserves the original migration instructions; unchecked boxes do not describe current outstanding work.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Classic with the specified AppKit/Core Graphics UI while preserving audio and playlist behavior, and delivering reliable stack, detached, and theater hosts.

**Architecture:** The same module views live in stack or detached window controllers. Pure module state and layout determine presentation; hosts own window lifecycle, focus, and visibility. A small theme supplies drawing values, and adapters connect existing models without changing their internals.

**Tech Stack:** Swift 6, AppKit, Core Graphics/Core Text, Combine, existing AVAudioEngine/WebKit/Metal code, Xcode XCTest. Keep the current deployment/build settings; no new runtime dependency.

**Spec:** [AmpX UI design](../specs/2026-09-11-ampx-ui-design.md). Read both documents before execution. [Reference PNG](../../../screenshots/AmpX.png), [PDF](../specs/AmpX%20UI.pdf), [review history](../specs/2026-09-11-ampx-ui-design-review.md).

## Global Constraints

- “The primary interface uses **AppKit and Core Graphics**, with custom controls and chrome.”
- “It contains no SwiftUI, `NSButton`, `NSSlider`, `NSTextField`, `NSTableView`, `NSScrollView`, native scrollbars, or SF Symbols.” Native menus, open panels, alerts, and About remain native.
- “Modules fill a **490 pt-wide** window at scale 1.0.” Use `scale = clamp(width / 490, 0.85, 1.35)` outside theater; gaps scale too.
- “Player is the anchor: it always remains in the stack's `order`, cannot detach, and never enters the module `closed` set.”
- “Never automatically collapse, close, or detach modules.” Overflow shrinks Playlist to three rows, then scrolls the stack.
- “Entering and exiting reparent the same mounted ENTHEA view; never recreate its WebView.”
- “Tear-off inherits source scale. Re-dock adopts destination stack scale.”
- Preserve models, audio, ENTHEA, shaders, visualization internals, and playlist persistence. The allowed playlist-directory change is the extracted `PlaylistChromeActions`.
- Keep Classic operational until cutover. `AmpXNewUI` defaults to NO through phases 1–4; remove the flag and Classic in phase 5.
- Keep `PlaylistChromeActionsTests` unchanged. Run tests through Xcode; Package.swift is a build smoke target, not a test runner.
- Run Python only through `uv` from `scripts/`. Do not alter unrelated user work, stage whole directories containing unrelated edits, or create a worktree until execution needs one.

## Execution conventions and repository facts

This is one migration plan, split into independently verifiable tasks across the spec's six phases. Execute in order unless a task explicitly permits otherwise. This document does not authorize implementation by itself.

Before Task 1, record `git status --short` and run `./scripts/run-tests.sh` to generate fixtures and establish the baseline. Existing untracked specs and `.worktrees/` are not deliverables to stage. At execution start use the worktree skill if isolation is needed; carry the reviewed spec/plan into that checkout explicitly.

For focused red/green loops, define this shell function from the repository root after fixture generation:

```bash
ampx_test() {
    xcodebuild test -project AmpX.xcodeproj -scheme AmpX \
        -destination "platform=macOS,arch=$(uname -m)" ONLY_ACTIVE_ARCH=YES \
        "-only-testing:AmpXTests/$1"
}
```

Each task names its suite. New XCTest files use `@testable import AmpX`, `import XCTest`, and `@MainActor` for AppKit/model tests. The sample assertions belong in test methods in the named suite. Run the named suite before implementation to confirm a relevant failure, then after implementation for green. At phase boundaries run `./scripts/run-tests.sh`; do not invent SPM tests. Run formatting/lint scripts before commits when their tools are installed, inspecting changes for unrelated formatting.

Code blocks below define interfaces, algorithms, and test examples, not permission to introduce empty production stubs. Complete the listed behavior in each task; do not commit a red build. Each task's last checkbox means stage only that task's listed created/modified files, inspect `git diff --cached`, and commit with its specified message.

Important inspected seams:

- `Sources/` and `Tests/AmpXTests/` are Xcode filesystem-synchronized. `Resources/Fonts/` is an explicit PBXGroup and resource build phase: font additions **do require** project entries.
- `ContentView.bindPlaybackCoordination()` installs next/previous/completion callbacks; `loadStartupSound()` implements launch behavior. Move ownership at cutover; do not discard it.
- `AudioPlayer.eqBandValues` and `eqPreampValue` are normalized. `setEQBand(_:gain:)` takes dB; `setEQPreamp(_:)` takes normalized values.
- `PlaybackClock.currentTime` is already sampled by the player. Pull it for UI timing; do not add a UI subscription to its publisher or change engine timing.
- `CatmullRomSpline.path(through:)` returns SwiftUI `Path`. Consume its `.cgPath` for Core Graphics drawing; the utility may retain its import without putting a SwiftUI view in the new interface.
- Reuse `EntheaWKHostView` directly, not the SwiftUI `EntheaWebView` representable. Its public activation, playback-update, backing-scale, loading, and teardown methods are the adapter boundary.
- `scripts/shoot.sh` currently relaunches without app arguments. Task 5 adds flag forwarding so visual checks actually capture the new UI.

## File map

These are the planned ownership boundaries. Each task below gives its exact file set.

| Area | Files / responsibility |
|---|---|
| Bootstrap | `AmpXMain.swift` chooses UI during migration; final `AmpXAppDelegate.swift` owns models and launch; `AmpXApplicationController.swift` owns UI session and model coordination |
| Theme | `Theme/AmpXSkin.swift`, `ClassicModernSkin.swift`, `AmpXMetrics.swift`, `AmpXFonts.swift`, `AmpXPixelGrid.swift` |
| Components | Drawing base, button/slider/label/icon/segment/scrollbar views and module chrome |
| Module state | `Modules/AmpXModuleID.swift`, `AmpXModuleOrder.swift`, `AmpXLayout.swift`, `AmpXLayoutStore.swift` |
| Module views | `Modules/Player/`, `Equalizer/`, `Playlist/`, `Enthea/` own composition and model subscriptions |
| Hosting | `Windows/AmpXStackWindowController.swift`, `AmpXDetachedModuleWindowController.swift`, `AmpXWindowChrome.swift`, `AmpXStackViewport.swift`, `AmpXHostCoordinator.swift`, `AmpXTheaterController.swift` |
| Lifecycle/input | `Modules/AmpXEffectiveVisibility.swift`, `Components/AmpXContinuousView.swift`, `Utilities/AmpXKeyRouter.swift`, `Utilities/AmpXMenuBuilder.swift` |

---

## Phase 0 — Preparation

### Task 1: Preserve playlist actions and free the metrics name

**Files:** Create `Sources/Playlist/PlaylistChromeActions.swift`; rename `Sources/Utilities/AmpXMetrics.swift` to `LegacyPanelMetrics.swift`; modify `Sources/Views/Classic/PlaylistListInteractions.swift`, `Sources/Utilities/AmpXUIScale.swift`, `Sources/Views/Classic/ClassicVisualizerPanelView.swift`, `Sources/AmpXPanelLayoutState.swift`, and `Tests/AmpXTests/ClassicUITests.swift`. Find any additional legacy references with the command below before renaming and add discovered callers to this task's file list before staging. Test: existing `PlaylistChromeActionsTests` and `ClassicUITests`.

**Interfaces:** Preserve every existing `PlaylistChromeActions` signature; only the containing file changes. Rename the legacy enum and its existing references without changing values.

- [ ] Run `ampx_test PlaylistChromeActionsTests` and `rg -n '\bAmpXMetrics\b' Sources Tests`; capture baseline references. No new tests for a mechanical move.
- [ ] Extract the complete `enum PlaylistChromeActions` verbatim; new file imports AppKit/Foundation as required. Leave selection and drag adapters in Classic for now. Rename only the legacy metrics symbol.

```swift
// Sources/Playlist/PlaylistChromeActions.swift
import AppKit
import Foundation
// Copy the existing @MainActor enum and all method bodies verbatim.
```

- [ ] Run `ampx_test PlaylistChromeActionsTests`, `ampx_test ClassicUITests`, then `./scripts/run-tests.sh`; confirm `PlaylistChromeActionsTests.swift` is unchanged and no remaining legacy `AmpXMetrics` references exist. `ClassicUITests.swift` receives only the mechanical rename here and is retired in Task 19.
- [ ] Commit: `refactor(ui): extract playlist actions and rename legacy metrics`.

## Phase 1 — Foundation and static composition

### Task 2: Define module membership and transitions as pure state

**Files:** Create `Sources/Modules/AmpXModuleID.swift`, `AmpXModuleOrder.swift`; test `Tests/AmpXTests/AmpXModuleOrderTests.swift`.

**Interfaces:**

```swift
enum AmpXModuleID: String, CaseIterable, Codable { case player, equalizer, playlist, enthea }
struct AmpXModuleOrder: Equatable {
    var order: [AmpXModuleID] = [.player, .equalizer, .playlist, .enthea]
    var collapsed: Set<AmpXModuleID> = []
    var detached: Set<AmpXModuleID> = []
    var closed: Set<AmpXModuleID> = [.enthea]
    // mutating move(_ id: AmpXModuleID, to index: Int)
    // mutating setCollapsed(_ id: AmpXModuleID, _ value: Bool)
    // mutating detach(_ id: AmpXModuleID)
    // mutating redock(_ id: AmpXModuleID, at index: Int)
    // mutating close(_ id: AmpXModuleID), reopen(_ id: AmpXModuleID)
}
```

Default ENTHEA is closed so first launch matches the three-panel reference. `move` uses a final index after removal, clamped to valid positions. Close retains order, collapsed state, and detached membership; reopen removes only `closed`. All mutators are idempotent where applicable. Player close/detach are rejected without mutation.

- [ ] Add a failing test and cases for stable ordering, duplicate requests, Player restrictions, and re-dock index boundaries:

```swift
var state = AmpXModuleOrder()
state.detach(.playlist)
state.close(.playlist)
state.reopen(.playlist)
XCTAssertEqual(state.order, [.player, .equalizer, .playlist, .enthea])
XCTAssertTrue(state.detached.contains(.playlist))
state.close(.player)
state.detach(.player)
XCTAssertFalse(state.closed.contains(.player))
XCTAssertFalse(state.detached.contains(.player))
```

- [ ] Run `ampx_test AmpXModuleOrderTests` and confirm failure from the missing behavior.
- [ ] Implement transitions with enum identity, never geometry. For `redock`, remove detached/closed membership then call `move`; preserve collapsed state.
- [ ] Run the suite green; commit: `feat(ui): define module order and capability rules`.

### Task 3: Theme, fonts, and pixel-aligned drawing base

**Files:** Create `Sources/Theme/{AmpXSkin,ClassicModernSkin,AmpXMetrics,AmpXFonts,AmpXPixelGrid}.swift`, `Sources/Components/AmpXDrawingView.swift`; add `Resources/Fonts/RobotoMono-{Regular,Medium,SemiBold}.ttf` and `RobotoMono-LICENSE.txt`; modify `AmpX.xcodeproj/project.pbxproj`; inspect `Resources/Info.plist` and modify only if needed to keep its font path consistent with the chosen bundle layout. Test `AmpXPixelGridTests.swift`, `AmpXFontsTests.swift` under `Tests/AmpXTests/`.

**Interfaces:** `AmpXPixelGrid.align(_:backingScale:) -> CGFloat`, `strokeRect(_:lineWidth:backingScale:) -> CGRect`; `AmpXFonts.register(bundle: Bundle)`, `font(size: CGFloat, weight: NSFont.Weight) -> NSFont`. `AmpXSkin` supplies named colors, metrics, fonts, and four drawing primitives; `ClassicModernSkin` is the only conformance. `AmpXDrawingView.init(skin: any AmpXSkin)` owns skin, flips coordinates, tracks hover, and responds to backing changes.

- [ ] Add numerical edge tests for stroke edges at 1×/2×/3× and font fallback:

```swift
XCTAssertEqual(AmpXPixelGrid.align(0.26, backingScale: 2), 0.5)
let r = AmpXPixelGrid.strokeRect(CGRect(x: 0, y: 0, width: 10, height: 10),
                               lineWidth: 1, backingScale: 1)
XCTAssertEqual(r.minX, 0.5)
XCTAssertEqual(r.maxX, 9.5)
```

- [ ] Run `ampx_test AmpXPixelGridTests`; confirm red. Test unavailable-face fallback using an injected lookup returning nil, not merely an empty bundle: process-registered fonts can remain available even with an empty bundle. Test real bundled registration twice and assert the actual family is Roboto Mono both times.
- [ ] Implement edge alignment using physical-pixel stroke widths; use the spec's exact palette and starting metrics. Resolve gold samples during composition, not from an invented replacement palette. Implement fallback with `NSFont.monospacedSystemFont(ofSize:weight:)`.
- [ ] Obtain the three static font faces from the official Roboto Mono distribution, retain Apache license and source provenance, and add explicit PBX file/build/group entries. Do not introduce a runtime font download. Validate family/face names via Core Text rather than assuming filename equals PostScript name.
- [ ] Make registration idempotent. Resolve each font in `Fonts/` and at the resource root, as the legacy loader does. Inspect the built `.app` to verify where Xcode copied it; `ATSApplicationFontsPath = Fonts` does not by itself establish that output directory. Keep JetBrains Mono and its registrations during coexistence; Roboto replaces it at cutover. Leave audio document types unchanged.

```swift
// Availability, not the registration Boolean, decides whether fallback is needed.
var registrationError: Unmanaged<CFError>?
let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)
let error = registrationError?.takeRetainedValue()
let alreadyRegistered = error.map {
    CFErrorGetCode($0) == CTFontManagerError.alreadyRegistered.rawValue
} ?? false
// Record a diagnostic for !registered && !alreadyRegistered; still try the face.
let font = NSFont(name: postScriptName, size: size)
    ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
```

Use verified face names and log an unavailable face once. Expose an internal `resolve(name:size:weight:lookup:) -> NSFont`, with lookup `(String, CGFloat) -> NSFont?` defaulting to `NSFont(name:size:)`, so the fallback test can deterministically pass `{ _, _ in nil }`.
- [ ] Run both suites and a build; commit: `feat(ui): add custom theme fonts and pixel grid`.

### Task 4: Pure scale/layout calculation and module frames

**Files:** Create `Sources/Modules/AmpXLayout.swift`, `AmpXModuleContent.swift`, `AmpXModuleStackView.swift`; create `Sources/Components/AmpXModuleView.swift`, `AmpXModuleHeaderView.swift`; test `AmpXLayoutTests.swift`.

**Interfaces:**

```swift
struct AmpXLayoutResult {
    var scale: CGFloat
    var frames: [AmpXModuleID: CGRect] // full-width stack-document coordinates; centered x
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
    var playlistViewportHeight: CGFloat // logical points
    var scrolls: Bool
}
// AmpXLayout.scale(width: CGFloat) -> CGFloat
// AmpXLayout.calculate(state: AmpXModuleOrder, width: CGFloat,
//   playlistViewportHeight: CGFloat, availableHeight: CGFloat) -> AmpXLayoutResult
```

`AmpXMetrics` supplies header height and playlist non-row chrome height, measured during static composition. Expanded starting heights are 223.5/225.5/305/290; gap 6. Ignore detached/closed members in stack layout. Overflow shrinks only the current expanded Playlist viewport to 66 logical points, then clamps host viewport. Keep saved preferred viewport separate from the temporary effective value.

- [ ] Add scaling test plus table-driven checks for full/collapsed/Player-only layouts:

```swift
XCTAssertEqual(AmpXLayout.scale(width: 490), 1)
XCTAssertEqual(AmpXLayout.scale(width: 416.5), 0.85)
XCTAssertEqual(AmpXLayout.scale(width: 980), 1.35)
var state = AmpXModuleOrder()
state.close(.equalizer)
state.close(.playlist)
let layout = AmpXLayout.calculate(state: state, width: 490,
    playlistViewportHeight: 180, availableHeight: 1000)
XCTAssertEqual(layout.contentHeight, 223.5)
let wide = AmpXLayout.calculate(state: state, width: 800,
    playlistViewportHeight: 180, availableHeight: 1000)
XCTAssertEqual(wide.frames[.player]!.minX, (800 - 490 * 1.35) / 2, accuracy: 0.0001)
XCTAssertEqual(wide.frames[.player]!.width, 490 * 1.35, accuracy: 0.0001)
```

- [ ] Run `ampx_test AmpXLayoutTests` red, then implement top-down frames and content-height arithmetic. Convert scale before pixel snapping; never infer module order from frame positions.

```swift
let scale = AmpXLayout.scale(width: width)
let compositionWidth = 490 * scale
let originX = max(0, (width - compositionWidth) / 2)
// Each frame uses originX and compositionWidth. Pixel-snap only in view layout.
```

The document stays the full host width; do not add a second centering transform in the viewport. This coordinate convention also governs drag hit testing.
- [ ] Implement shared chrome and noninteractive headers using theme primitives. Header callbacks are `onCollapse: (() -> Void)?`, `onClose`, `onMinimize`; chrome owns them, content does not. Expose `AmpXModuleView.content: AmpXModuleContent` and `moduleID: AmpXModuleID` for later reparenting.
- [ ] Run the suite; commit: `feat(ui): lay out module frames with width-driven scale`.

### Task 5: Flag-gated AppKit host and screenshot access

**Files:** Create `Sources/AmpXMain.swift`, `Sources/AmpXAppDelegate.swift`, `Sources/Windows/AmpXStackWindowController.swift`, `AmpXWindowChrome.swift`; modify `Sources/AmpXApp.swift`, `scripts/shoot.sh`; test `AmpXBootstrapTests.swift`.

**Interfaces:** `AmpXMain.usesNewUI(defaults: UserDefaults) -> Bool`; `AmpXStackWindowController.init(state: AmpXModuleOrder, skin: any AmpXSkin)`; `showWindow(_:)` is inherited. New delegate must not initialize windows/audio while running under XCTest.

- [ ] Test that a clean isolated defaults suite chooses Classic, while setting `AmpXNewUI` chooses the new branch. Run `ampx_test AmpXBootstrapTests` red.

```swift
let name = "AmpXBootstrapTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: name)!
defer { defaults.removePersistentDomain(forName: name) }
XCTAssertFalse(AmpXMain.usesNewUI(defaults: defaults))
defaults.set(true, forKey: "AmpXNewUI")
XCTAssertTrue(AmpXMain.usesNewUI(defaults: defaults))
```

- [ ] Make `AmpXMain` the only `@main`; remove `@main` from the legacy SwiftUI App but preserve its scene. Dispatch synchronously, retaining the AppKit delegate for the application's lifetime:

```swift
if AmpXMain.usesNewUI(defaults: .standard) {
    let app = NSApplication.shared
    let delegate = AmpXAppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
} else {
    AmpXApp.main()
}
```

Place this in `static func main()`; guard test launch before constructing live models. The new delegate creates a mock-data stack; the old delegate remains owned by the legacy branch only. New host chrome hides native window buttons without touching system panels.

- [ ] Apply actual window minimum sizing in `AmpXWindowChrome.apply(to:minimumHeaderHeight:)`, not just a scale clamp:

```swift
window.contentMinSize = NSSize(width: 490 * 0.85, height: minimumHeaderHeight)
```

Task 9 recalculates height from visible headers and gaps. Normal detached hosts use the same minimum width; theater suspends normal constraints and restores them on exit. Add a host test asserting `contentMinSize.width == 416.5` and an attempted interactive resize below that bound.

- [ ] Extend `shoot.sh` argument parsing: `--no-build` retains its meaning; `--` ends script options and passes remaining arguments to `open -n "$APP_PATH" --args "${APP_ARGS[@]}"`. No arguments still launches Classic. Do not write permanent defaults just to screenshot.
- [ ] Run suite, `bash -n scripts/shoot.sh`, `./scripts/shoot.sh -- -AmpXNewUI YES`, and default `./scripts/shoot.sh --no-build`; inspect both modes. Commit: `feat(ui): launch AppKit stack behind migration flag`.

### Task 6: Measure and freeze the static composition inputs

**Files:** Modify `Sources/Theme/AmpXMetrics.swift`, `ClassicModernSkin.swift`, `Sources/Modules/AmpXLayout.swift`, and header geometry; create `docs/superpowers/plans/2026-09-11-ampx-ui-visual-checks.md`. Test existing `AmpXLayoutTests.swift` against the measured dimensions.

**Interfaces:** Record a table named **ReferenceMeasurementsV1** containing source-pixel rectangles and corresponding logical content-coordinate rectangles. Its required keys are `headerHeight`, `player.displayWell`, `player.trackWell`, `player.metadata`, `player.volume`, `player.balance`, `player.position`, `player.transport`, `eq.curve`, `eq.preamp`, `eq.bandRow`, `playlist.rows`, `playlist.scrollbar`, `playlist.footer`, `gold`, `goldLight`, `spectrum.segmentHeight`, and `spectrum.segmentGap`. Convert visual subrectangles relative to their owning content origin, excluding header and outer canvas margins.

- [ ] Capture the new blank module stack. Record the PNG's module crop bounds, gaps, content origins, and header height in ReferenceMeasurementsV1. Use `uv` from `scripts/` for image analysis.
- [ ] Measure Player wells/transport/slider tracks and record the numeric kbps/kHz decision explicitly as `metadataDigitStyle = mono` or `segments`, with a reference crop supporting it. Timer remains segment-drawn.
- [ ] Measure EQ curve/preamp/band regions and Playlist row area/scrollbar/footer; sample the gold palette and spectrum segment geometry.
- [ ] Populate named `AmpXMetrics` properties from that complete table. Store single rectangles as `CGRect`, transport positions as `[CGRect]`, and palette samples as named skin colors. Missing measurements are a task failure; do not leave placeholder constants for composition tasks.
- [ ] Run `ampx_test AmpXLayoutTests` and compare module outlines against the PNG. Commit: `docs(ui): freeze reference measurements for composition`.

### Task 6A: Static Player, glyphs, and segment timer

**Files:** Create `Sources/Modules/Player/PlayerModuleContent.swift`, `Sources/Components/AmpXLabel.swift`, `AmpXIcon.swift`, `AmpXSegmentDigits.swift`; modify the stack content factory and visual-checks document.

**Interfaces:** `PlayerModuleContent.init(skin: any AmpXSkin)`; `AmpXLabel.text: String`; `AmpXIcon` cases play/pause/stop/previous/next/eject/repeat/menu/collapse/minimize/close/grip; `AmpXSegmentDigits.draw(_ text: String, in rect: CGRect, context: CGContext)`. Theme primitives use `displayWell(_ rect: CGRect, in context: CGContext)` and the same rect/context convention for bevel/inset/accentLine.

- [ ] Create local-coordinate Player content and display/track wells using ReferenceMeasurementsV1. Draw the reference track string and mono/stereo labels at the measured baselines with bundled fonts.

```swift
skin.displayWell(AmpXMetrics.playerDisplayWell, in: context)
skin.displayWell(AmpXMetrics.playerTrackWell, in: context)
segmentDigits.draw("01:51", in: AmpXMetrics.playerTimer, context: context)
```

`playerTimer` is measured within `player.displayWell` during this step and added to the table before use. `segmentDigits` is the content's retained `AmpXSegmentDigits`, initialized with its skin.

- [ ] Draw grid/spectrum segments and play glyph; use the measured metadata digit style and record it in the visual check.
- [ ] Draw volume, balance, position track/thumbs; add each transport silhouette and glyph at its measured rectangle, including shuffle/repeat/menu. These are static until Task 7.
- [ ] Capture `./scripts/shoot.sh -- -AmpXNewUI YES`, compare the Player crop, and correct local coordinates until wells, timer, glyphs, and baselines match the reference exceptions. Commit: `feat(ui): render static Player composition`.

### Task 6B: Static Equalizer composition

**Files:** Create `Sources/Modules/Equalizer/EqualizerModuleContent.swift`; modify stack content factory and visual-checks document.

**Interfaces:** `EqualizerModuleContent.init(skin: any AmpXSkin)` consumes ReferenceMeasurementsV1, `AmpXEQBands.displayLabels`, `bandCenterX(bandIndex:width:)`, and `responseCurvePoints(bandValues:preampValue:width:height:maxGainDB:)`.

- [ ] Draw ON/AUTO and PRESETS silhouettes and the curve well from measured EQ rectangles.
- [ ] Draw preamp and ten tracks/thumbs; derive labels and band x-centers from `AmpXEQBands`, offset into the measured band region. Add +12/0/−12 dB labels.
- [ ] Draw the mock curve through the existing helper; translate the graphics context into the measured curve origin before adding the path.

```swift
let points = AmpXEQBands.responseCurvePoints(bandValues: mockBands,
    preampValue: 0, width: AmpXMetrics.eqCurve.width, height: AmpXMetrics.eqCurve.height)
context.saveGState()
context.translateBy(x: AmpXMetrics.eqCurve.minX, y: AmpXMetrics.eqCurve.minY)
context.addPath(CatmullRomSpline.path(through: points).cgPath)
context.strokePath()
context.restoreGState()
```

Define `mockBands: [Float]` from the reference thumb positions during this step and record them beside the EQ crop; they are normalized display data, not audio settings.

- [ ] Capture and compare the EQ crop. Commit: `feat(ui): render static Equalizer composition`.

### Task 6C: Static Playlist and complete composition checkpoint

**Files:** Create `Sources/Modules/Playlist/PlaylistModuleContent.swift`; modify stack content factory and visual-checks document.

**Interfaces:** `PlaylistModuleContent.init(skin: any AmpXSkin)`; measured `AmpXMetrics.playlistRows`, `playlistScrollbar`, and `playlistFooter` rectangles. Use `AmpXLabel`, `AmpXIcon`, and skin primitives from Tasks 3/6A.

- [ ] Draw the black row area, reference track rows, selected rectangle, and right-aligned duration column. Derive row origins from the measured area plus `22 * index`, never distribute them responsively.

```swift
let row = CGRect(x: AmpXMetrics.playlistRows.minX,
    y: AmpXMetrics.playlistRows.minY + CGFloat(index) * 22,
    width: AmpXMetrics.playlistRows.width, height: 22)
let durationRect = CGRect(x: row.maxX - 42, y: row.minY, width: 42, height: row.height)
```

- [ ] Draw amber arrows/gold thumb and the ADD/REM/SEL/MISC/LIST OPTS footer, counters, and mini transport with measured rectangles.
- [ ] Capture the complete three-module stack at scale 1.0 and scale bounds. Inspect crops against the PNG and record any remaining differences honestly.
- [ ] Run `./scripts/run-tests.sh` for the phase boundary. Commit: `feat(ui): render static Playlist and verify composition`.

## Phase 2 — Controls

### Task 7: Custom button, slider, and scrollbar interaction

**Files:** Create `Sources/Components/AmpXButton.swift`, `AmpXSlider.swift`, `AmpXScrollbar.swift`, `AmpXControlMath.swift`; modify module content files to replace static control drawings with these views. Test `AmpXControlsTests.swift`.

**Interfaces:** `AmpXButton.action: (() -> Void)?`, `isActive: Bool`, `isEnabled: Bool`; `AmpXSlider.value: Double`, `range: ClosedRange<Double>`, `step: Double`, `onChange: ((Double) -> Void)?`, `isVertical: Bool`; scrollbar `offset/contentLength/viewportLength: CGFloat`, `onScroll: ((CGFloat) -> Void)?`. `AmpXControlMath.value(fraction:range:) -> Double` clamps to range.

- [ ] Write tests for track endpoints, vertical inversion, disabled activation, release outside bounds, and scrollbar limits:

```swift
XCTAssertEqual(AmpXControlMath.value(fraction: -0.2, range: -12...12), -12)
XCTAssertEqual(AmpXControlMath.value(fraction: 0.5, range: -12...12), 0)
XCTAssertEqual(AmpXControlMath.value(fraction: 1.2, range: -12...12), 12)
```

- [ ] Run `ampx_test AmpXControlsTests` red. Implement event tracking: press highlights immediately; release fires only if still enabled/inside. Sliders send each clamped value immediately; vertical high values map to the top. Use `mouseDown`, `mouseDragged`, `mouseUp`, and wheel events instead of a blocking tracking loop.

```swift
let fraction = isVertical ? 1 - (point.y - track.minY) / track.height
                          : (point.x - track.minX) / track.width
let next = AmpXControlMath.value(fraction: Double(fraction), range: range)
value = next
onChange?(next)
```

- [ ] Implement hover/pressed/active/disabled drawing without losing combined active+hover state. Add keyboard focus-ring drawing in theme style, minimum hit rectangles, and native accessibility press/increment/decrement/value methods. Programmatic value assignment redraws but does not invoke `onChange`.
- [ ] Run suite and screenshot; verify button press lasts 60–80 ms and no unrelated view animates. Run full phase suite; commit: `feat(ui): add accessible custom controls`.

## Phase 3 — Interaction

### Task 8: Persistence and stack-window close/reopen behavior

**Files:** Create `Sources/Modules/AmpXLayoutStore.swift`, `Sources/Windows/AmpXHostCoordinator.swift`; modify `AmpXStackWindowController.swift`, `AmpXAppDelegate.swift`; test `AmpXLayoutStoreTests.swift`, `AmpXHostCoordinatorTests.swift`.

**Interfaces:** `AmpXSavedLayout` contains `state: AmpXModuleOrder`, `stackFrame: CGRect`, `detachedFrames: [AmpXModuleID: CGRect]`, `playlistViewportHeight: CGFloat`; `AmpXLayoutStore.init(defaults: UserDefaults)`, `load() -> AmpXSavedLayout`, `save(_:)`; `AmpXHostCoordinator.init(state: AmpXModuleOrder, skin: any AmpXSkin)`, `state`, `showStack()`, `closeStack()`, `closeModule(_:)`, `reopenModule(_:)`, `setCollapsed(_ id: AmpXModuleID, _ value: Bool)`, `moduleView(for id: AmpXModuleID) -> AmpXModuleView?`.

- [ ] Add raw JSON corruption tests, including an unknown module ID mixed with known IDs, duplicate IDs, missing Player, non-finite/invalid sizes, and detached-state restoration. Use isolated UserDefaults suites and remove only that suite after each test.

```swift
let name = "AmpXLayoutStoreTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: name)!
defer { defaults.removePersistentDomain(forName: name) }
defaults.set(Data("not-json".utf8), forKey: "AmpXModuleLayoutV1")
let loaded = AmpXLayoutStore(defaults: defaults).load()
XCTAssertEqual(loaded.state.order.first, .player)
XCTAssertFalse(loaded.state.closed.contains(.player))
```

- [ ] Run `ampx_test AmpXLayoutStoreTests` red. Encode a versioned DTO using raw strings for IDs so one unknown ID cannot fail the whole decode. Normalize duplicates, append missing known modules, enforce Player capability rules, and validate finite geometry before making windows. Keep default frames computed from the current screen, not hardcoded absolute positions.
- [ ] Connect header actions and window delegate close: stack close orders out, retains its controller and state, and never calls `audioPlayer.stop()`. Add Dock reopen handling via the delegate. Detached close invokes module close. Saving is triggered on completed move/resize/state changes, not continuous paint callbacks.
- [ ] Run both suites; manually close/reopen stack with EQ/Playlist visible. Commit: `feat(ui): persist module layout and restore stack visibility`.

### Task 9: Stack viewport and constrained resizing

**Files:** Create `Sources/Windows/AmpXStackViewport.swift`; modify `AmpXLayout.swift`, `AmpXStackWindowController.swift`, `AmpXModuleStackView.swift`, `AmpXHostCoordinator.swift`; test `AmpXStackViewportTests.swift`.

**Interfaces:** `AmpXStackViewport.scrollOffset: CGFloat`, `visibleContentRect: CGRect`, `setScrollOffset(_:)`, `reveal(_ rect: CGRect)`, `onVisibleRectChanged: ((CGRect) -> Void)?`. It clips its document view with a layer; no NSScrollView. `AmpXLayoutResult` from Task 4 remains the only layout computation.

- [ ] Test maximum-scale short-screen overflow and offset clamping:

```swift
var state = AmpXModuleOrder()
state.reopen(.enthea)
let result = AmpXLayout.calculate(state: state, width: 661.5,
    playlistViewportHeight: 180, availableHeight: 600)
XCTAssertEqual(result.playlistViewportHeight, 66)
XCTAssertTrue(result.scrolls)
XCTAssertEqual(result.viewportHeight, 600)
XCTAssertGreaterThan(result.contentHeight, result.viewportHeight)
```

- [ ] Run `ampx_test AmpXStackViewportTests` red. Lay out the stack with a translated origin, clamp offsets to `0...max(0, contentHeight - viewportHeight)`, and expose content-coordinate visible rects. The scrollbar is an overlay/inset that does not silently rescale the 490-point module width.
- [ ] Handle horizontal and vertical live resize separately; preserve top edge when content height changes. Treat preferred Playlist viewport as saved user intent and screen-induced shrinking as temporary. Route wheel events to Playlist when it can scroll, otherwise to stack. Keyboard focus calls `reveal` so offscreen focus becomes reachable.
- [ ] Run suite, resize all four modules at scale 1.35 on a short screen, then restore screen space and confirm viewport preference returns. Commit: `feat(ui): scroll overflowing module stacks`.

### Task 10: Reorder, tear-off, and re-dock with a single transfer path

**Files:** Create `Sources/Modules/AmpXModuleDragController.swift`, `Sources/Windows/AmpXDetachedModuleWindowController.swift`; modify host coordinator, header, viewport, stack view. Test `AmpXModuleDragTests.swift`.

**Interfaces:** `AmpXDropGeometry { var bounds: CGRect; var orderedFrames: [(AmpXModuleID, CGRect)] }`; `AmpXModuleDragController.dropIndex(geometry:point:) -> Int?`; coordinator `detach(_ id: AmpXModuleID)`, `redock(_ id: AmpXModuleID, at index: Int)`. Drop indices refer to the visible stack with the dragged module removed; coordinator maps them to the full retained `order` before mutation.

- [ ] Add tests for above/between/below, outside, closed/detached intervening entries, scale inheritance, and same-view transfer:

```swift
let g = AmpXDropGeometry(bounds: CGRect(x: 0, y: 0, width: 490, height: 300),
    orderedFrames: [(.player, CGRect(x: 0, y: 0, width: 490, height: 100)),
                    (.playlist, CGRect(x: 0, y: 106, width: 490, height: 190))])
XCTAssertEqual(AmpXModuleDragController.dropIndex(geometry: g, point: CGPoint(x: 20, y: 104)), 1)
XCTAssertNil(AmpXModuleDragController.dropIndex(geometry: g, point: CGPoint(x: -1, y: 104)))
```

- [ ] Run `ampx_test AmpXModuleDragTests` red. Calculate insertion by module midpoints after rejecting out-of-bounds points. Convert screen/window coordinates into stack content coordinates once; account for viewport scroll offset before calling the pure function.
- [ ] Implement grip tracking, threshold 40 pt, insertion marker, and 150–200 ms settle. Transfer a strongly retained `AmpXModuleView` between content parents without reconstructing content. Tear-off creates a window at inherited scale and cursor anchor; re-dock adopts stack scale. Cancel safely if the source collapses mid-gesture.
- [ ] Add edge auto-scroll (bounded scroll speed with repeated drop-index recomputation); stop it on release/cancel. When re-docking through a menu into a hidden stack, call `showStack()` first. Menus use the same transfer operations.
- [ ] Run suite and exercise closed/interleaved states plus differently scaled hosts. Commit: `feat(ui): support module reorder and window transfers`.

### Task 11: Focus routing, module commands, and accessibility traversal

**Files:** Create `Sources/Utilities/AmpXKeyRouter.swift`; modify custom controls, headers, module views, host coordinator, app delegate; test `AmpXKeyRouterTests.swift` and `AmpXAccessibilityTests.swift`. Keep `AmpXHotkeys.swift` for the Classic branch until cutover.

**Interfaces:** `AmpXFocusContext` describes focused module and `control: AmpXControlFocus?` (`button`, `slider`, or nil). `AmpXKeyRouter.route(event: NSEvent, context: AmpXFocusContext) -> AmpXKeyRoute` returns `.control`, `.playlist`, `.enthea`, `.global`, or `.unhandled`; dispatching invokes the recipient exactly once. Modifier-aware routing preserves all existing playlist bindings.

- [ ] Test Space/arrows under control and module focus, plain letters, and command-modified module keys. Include a system text responder that bypasses global single-letter shortcuts so native dialogs remain usable.

```swift
let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
    timestamp: 0, windowNumber: 0, context: nil, characters: " ",
    charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
XCTAssertEqual(AmpXKeyRouter.route(event: event,
    context: AmpXFocusContext(module: .playlist, control: .button)), .control)
```

- [ ] Run `ampx_test AmpXKeyRouterTests` red. Implement control → Playlist → ENTHEA → global precedence from the spec. Return unhandled NSEvents unchanged; do not confuse “handled nil” with “no matching route,” as the old optional routing shape permits.
- [ ] Install only the new router in the new UI branch. Wire module keyboard commands through coordinator methods; register key equivalents in a temporary Window menu that final menu construction will reuse. Respect system-reserved shortcut interception; verify the spec's Cmd-Option-D binding on the target Mac and retain the menu/accessibility action regardless.
- [ ] Add first-responder eligibility, Tab traversal, accessible module actions, selected-row semantics hooks, and header fallback focus on collapse; restore remembered content focus on expansion. Revealing focus uses Task 9's viewport method. Close chooses the next available module, wrapping to Player if needed.
- [ ] Run suites; perform keyboard-only navigation of the mock controls in both hosts. Commit: `feat(ui): route keyboard and accessibility actions by focus`.

## Phase 4 — Real state

### Task 12: Shared visibility and display-link lifecycle

**Files:** Create `Sources/Modules/AmpXEffectiveVisibility.swift`, `Sources/Components/AmpXContinuousView.swift`; modify hosts/coordinator/viewport to publish visibility inputs. Test `AmpXEffectiveVisibilityTests.swift`.

**Interfaces:**

```swift
struct AmpXVisibilityInputs {
    var collapsed, closed, windowVisible, miniaturized, occluded: Bool
    var intersectsViewport: Bool
    var isVisible: Bool {
        !collapsed && !closed && windowVisible && !miniaturized && !occluded && intersectsViewport
    }
}
// AmpXContinuousView.setEffectivelyVisible(_ value: Bool)
// AmpXContinuousView.tick(at time: TimeInterval) // override in leaf views
```

- [ ] Test each input independently and repeated transitions using injected `start`/`stop` closures; verify false→false never restarts/stops twice. Set theater/detached `intersectsViewport` true, never the whole predicate true.

```swift
var input = AmpXVisibilityInputs(collapsed: false, closed: false,
    windowVisible: true, miniaturized: false, occluded: false, intersectsViewport: true)
XCTAssertTrue(input.isVisible)
input.collapsed = true
input.intersectsViewport = false
input.intersectsViewport = true
XCTAssertFalse(input.isVisible)
```

- [ ] Run `ampx_test AmpXEffectiveVisibilityTests` red. Hosts compute inputs from module state, NSWindow notifications, and viewport content-coordinate intersection. Module content receives only the Boolean, not windows.
- [ ] Implement one `NSView.displayLink(target:selector:)` per visible continuous leaf. Check the installed SDK declaration for callback/run-loop types when implementing; keep start/stop injectable for tests. Invalidate and release links on false/deinit; on true recreate, using a weak forwarding target to avoid retain cycles. Tick invalidates only leaf bounds, never its parent/window.
- [ ] Run suite, instrument tick counts before/after collapse, scrolling out, hide, and reparenting. Commit: `feat(ui): gate continuous rendering on effective visibility`.

### Task 13: Connect Player and spectrum to existing models

**Files:** Create `Sources/Modules/Player/AmpXSpectrumColumnModel.swift`, `SpectrumWellView.swift`, `TimeDisplayView.swift`, `PositionBarView.swift`; modify `PlayerModuleContent.swift`, `Sources/Windows/AmpXHostCoordinator.swift`, and `Sources/AmpXAppDelegate.swift` to supply the new model initializer arguments; test `AmpXSpectrumColumnModelTests.swift`, `AmpXPlayerBindingTests.swift`.

**Interfaces:** `AmpXSpectrumColumnModel.litCount(level: Float, segmentCount: Int) -> Int`, `colorBand(segment: Int, count: Int) -> Int`, mutating `updatePeak(level: Float, at time: TimeInterval) -> Float`. Player initializer gains `audioPlayer: AudioPlayer, playlistManager: PlaylistManager, onToggleModule: (AmpXModuleID) -> Void`; continuous leaves inherit Task 12.

- [ ] Test clamping/count boundaries and time-driven peak decay with fake timestamps. Add callback tests that distinguish play, pause, stop, seek, volume, and balance.

```swift
XCTAssertEqual(AmpXSpectrumColumnModel.litCount(level: -1, segmentCount: 12), 0)
XCTAssertEqual(AmpXSpectrumColumnModel.litCount(level: 1, segmentCount: 12), 12)
XCTAssertEqual(AmpXSpectrumColumnModel.litCount(level: 0.5, segmentCount: 12), 6)
```

- [ ] Run both suites red. Implement segmented coloring from Task 6's measurements and reuse existing peak behavior where its interface fits; avoid changing the analysis bus. The bus's spectrum is a mixed band array, not two independent spectra: preserve existing signal semantics and reference L/R labels, without inventing stereo FFT data.
- [ ] Bind actions to existing methods: `playOrResume`, `pause`, `stop`, `seek(to:)`, `setVolume`, `setBalance`; previous/next through PlaylistManager; eject through `showFilePicker`; shuffle/repeat via playlist properties. Module toggles call coordinator close/reopen. Observe metadata/discrete state with Combine on the main actor.

```swift
positionBar.onChange = { [weak audioPlayer] seconds in audioPlayer?.seek(to: seconds) }
// On each visible tick, read values; do not subscribe to the clock publisher.
let seconds = audioPlayer.playbackClock.currentTime
let duration = audioPlayer.duration
```

- [ ] Implement empty-track/zero-duration states, remaining/elapsed timer toggle, and track formatting through existing helpers. Pull `spectrumSnapshot(at:)` using the existing bus timing convention; don't modify the engine for display-rate sampling.
- [ ] Run suites, play/pause/seek the fixture, and confirm hidden leaves stop ticking. Commit: `feat(ui): connect Player controls and live spectrum`.

### Task 14: Connect EQ with correct unit conversions and preset actions

**Files:** Create `Sources/Modules/Equalizer/EQCurveView.swift`, `EQValueMapping.swift`; modify `EqualizerModuleContent.swift` and its factory in `Sources/Windows/AmpXHostCoordinator.swift`; test `AmpXEQBindingTests.swift`.

**Interfaces:** `EQValueMapping.decibels(normalized: Float) -> Float`, `normalized(decibels: Float) -> Float`. EQ initializer gains `audioPlayer: AudioPlayer`.

- [ ] Write conversion and callback tests; run `ampx_test AmpXEQBindingTests` red:

```swift
XCTAssertEqual(EQValueMapping.decibels(normalized: 0.5), 6)
XCTAssertEqual(EQValueMapping.normalized(decibels: -12), -1)
```

- [ ] Implement value mapping by multiplying/dividing by 12 with ±12 dB limits. Display band/preamp normalized state as dB, send band changes as dB, and preamp changes as normalized values:

```swift
bandSlider.onChange = { [weak audioPlayer] db in
    audioPlayer?.setEQBand(index, gain: Float(db))
}
preampSlider.onChange = { [weak audioPlayer] db in
    audioPlayer?.setEQPreamp(EQValueMapping.normalized(decibels: Float(db)))
}
```

- [ ] Wire ON/AUTO to setters, presets to `eqPresets()`/`applyEQPreset`, reset/import to existing APIs. Refresh presets on `eqPresetsRevision`. Animate the curve only for 50–100 ms using the existing spline converted to CGPath; UI updates must not feed back into model setters.
- [ ] Run suite and existing `EQSettingsStoreTests`/`EQAudioEffectTests`. Verify AUTO-adjusted preamp is reflected correctly. Commit: `feat(ui): connect EQ controls and presets`.

### Task 15: Playlist rows, selection, scrolling, and commands

**Files:** Create `Sources/Modules/Playlist/PlaylistRowLayout.swift`, `PlaylistRowsView.swift`, `PlaylistKeyboardAdapter.swift`, `PlaylistFooterView.swift`; modify `PlaylistModuleContent.swift` and its factory in `Sources/Windows/AmpXHostCoordinator.swift`; test `PlaylistRowLayoutTests.swift`, `PlaylistKeyboardAdapterTests.swift`.

**Interfaces:** `PlaylistRowLayout.visibleRange(offset: CGFloat, viewport: CGFloat, count: Int) -> Range<Int>` uses row height 22; `rowRect(index: Int, width: CGFloat) -> CGRect` reserves 42 points for duration. `PlaylistKeyboardAdapter.init(manager: PlaylistManager)` owns `selection: PlaylistSelectionModel`, conforms to every `AmpXPlaylistKeyboard.Handling` method, and exposes `onSelectionChanged: (() -> Void)?`. Content initializer accepts `manager: PlaylistManager` and `audioPlayer: AudioPlayer` for mini transport.

- [ ] Test visible ranges and reproduce selection/navigation/crop/reorder cases from the existing adapters with the existing MockAudioPlayer setup:

```swift
XCTAssertEqual(PlaylistRowLayout.visibleRange(offset: 22, viewport: 44, count: 10), 1..<3)
XCTAssertEqual(PlaylistRowLayout.visibleRange(offset: 0, viewport: 100, count: 0), 0..<0)
let player = MockAudioPlayer()
let manager = PlaylistManager(audioPlayer: player, restoreBookmarks: false,
    restorePlaylist: false, alertPresenter: SilentPlaylistAlertPresenter())
let a = Track(title: "A", artist: "Artist", url: URL(fileURLWithPath: "/tmp/a.wav"))
let b = Track(title: "B", artist: "Artist", url: URL(fileURLWithPath: "/tmp/b.wav"))
manager.addTracks([a, b])
let adapter = PlaylistKeyboardAdapter(manager: manager)
adapter.selection.selectOnly(b.id)
adapter.removeSelectedTracks()
XCTAssertEqual(manager.tracks.map(\.id), [a.id])
```

- [ ] Run both suites red. Port keyboard behavior from `PlaylistKeyboardNavigation` using plain owned selection state, keeping track IDs stable across reorder. Register/unregister the handler when the Playlist module is active; changing hosts must not create a second handler.
- [ ] Draw only visible rows; retain selection by ID; implement click, shift-range, command-toggle, double-click playback, wheel/scrollbar, and row drag with the existing 6 pt movement threshold. Convert visible row indices back to manager indices before actions. Prune selection on track removal and reveal cursor on keyboard navigation.
- [ ] Wire ADD/REM/SEL/MISC/LIST OPTS using `PlaylistChromeActions` and current `ClassicPlaylistView` menu behavior: file/folder add, remove/crop/clear, select/invert, sort/reverse/randomize/file info, and playlist load/save. Preserve file-URL drop import through `manager.importDroppedURL(_:)`; keep destructive file removal's existing confirmation. Use `NSMenu` popups from custom buttons, not custom text editors or new file services.
- [ ] Expose accessible visible rows and selected rows; footer mini transport uses Player's existing methods and time formatting. Run new suites and unchanged `PlaylistChromeActionsTests`; manually test a list larger than the viewport. Commit: `feat(ui): connect playlist selection menus and file drops`.

### Task 16: ENTHEA adapter with testable ownership and suspension

**Files:** Create `Sources/Modules/Enthea/EntheaModuleContent.swift`, `EntheaHostLifecycle.swift`; modify host coordinator. Test `EntheaHostLifecycleTests.swift`. Do not modify `Sources/Enthea/`.

**Interfaces:**

```swift
@MainActor protocol AmpXEntheaHosting: AnyObject {
    func setAudioBridgeActive(_ active: Bool)
    func teardown()
}
// Existing public methods satisfy the conformance; declare it in the NEW adapter file.
extension EntheaWKHostView: AmpXEntheaHosting {}
@MainActor final class EntheaHostLifecycle {
    private(set) var host: (any AmpXEntheaHosting)?
    // init(host: any AmpXEntheaHosting)
    // func setVisible(_ visible: Bool)
    // func close()
}
```

The module retains the actual host subview; `close()` must remove that subview and clear **all** owning references as well as lifecycle.host. Keeping the module wrapper for reopen is fine, keeping its old WebView is not. Reopen creates/loads a new host; transfers do not.

- [ ] Add a local fake host with `activeCalls: [Bool]` and `teardownCount` and these tests:

```swift
@MainActor final class FakeEntheaHost: AmpXEntheaHosting {
    var activeCalls: [Bool] = []
    var teardownCount = 0
    func setAudioBridgeActive(_ active: Bool) { activeCalls.append(active) }
    func teardown() { teardownCount += 1 }
}
let host = FakeEntheaHost()
let lifecycle = EntheaHostLifecycle(host: host)
lifecycle.setVisible(true)
lifecycle.setVisible(false)
lifecycle.setVisible(false)
XCTAssertEqual(host.activeCalls, [true, false])
lifecycle.close()
XCTAssertEqual(host.teardownCount, 1)
XCTAssertNil(lifecycle.host)
```

Also use a weak reference in a separate test with no external strong owner to verify deallocation.

- [ ] Run `ampx_test EntheaHostLifecycleTests` red. Forward visibility to `setAudioBridgeActive`; its existing render/push policy stops the timer, track bridge, and renderer. Never directly access the private timer or blank the page to simulate release. Add an actual-host test for ownership, and a manual process/render activity check; a fake alone cannot prove WebView behavior.
- [ ] Construct `EntheaWKHostView`, set `panelController`, call `loadEnthea`, and host it directly. Mirror the existing representable's calls to `applyBackingScale(for:)` and `updatePlayback(trackURL:seconds:isPlaying:isTheater:)`. Discrete model subscriptions update track/play state; use a visible continuous update for playback position. No Combine subscription to PlaybackClock.
- [ ] Connect effective visibility and teardown; recompute after reparenting in the destination host. Close removes subview, calls teardown, clears host and lifecycle ownership. Ensure a delayed callback cannot resurrect a closed host. Preserve ENTHEA's existing mode/autopilot/look commands through its controller and menu actions where the old chrome offered them.
- [ ] Run lifecycle and existing ENTHEA suites. Verify collapse and scrolling out stop activity while the stack window stays visible; expansion resumes. Commit: `feat(ui): host ENTHEA with explicit visibility lifecycle`.

### Task 17: Theater with restored host identity and presentation

**Files:** Create `Sources/Windows/AmpXTheaterController.swift`; modify host coordinator, detached host, ENTHEA content, key router. Test `AmpXTheaterTests.swift`.

**Interfaces:** `AmpXTheaterSnapshot` stores original host ID (`AmpXModuleID?`, nil = stack), module position, frame, scale, and `NSApplication.PresentationOptions`; `AmpXTheaterController.enter()`, `exit()`, `isActive: Bool`. Its initializer takes `hosts: AmpXHostCoordinator`, `screenFrame: () -> CGRect`, `getPresentation: () -> NSApplication.PresentationOptions`, and `setPresentation: (NSApplication.PresentationOptions) -> Void`. Store snapshot once; repeated enter is a no-op. Coordinator owns the controller; controller holds the coordinator weakly to avoid a cycle. Injected accessors keep tests from changing application presentation options.

- [ ] Write a host-transfer test that captures view identity, enters theater, verifies content geometry, exits, and compares the original identity/frame:

```swift
let hosts = AmpXHostCoordinator(state: AmpXModuleOrder(), skin: ClassicModernSkin())
hosts.reopenModule(.enthea)
let view = try XCTUnwrap(hosts.moduleView(for: .enthea))
let identity = ObjectIdentifier(view.content)
let previousFrame = view.frame
var presentation: NSApplication.PresentationOptions = []
let controller = AmpXTheaterController(hosts: hosts,
    screenFrame: { CGRect(x: 0, y: 0, width: 1200, height: 800) },
    getPresentation: { presentation }, setPresentation: { presentation = $0 })
controller.enter()
XCTAssertTrue(controller.isActive)
XCTAssertEqual(view.content.bounds.size, CGSize(width: 1200, height: 800))
XCTAssertTrue(presentation.contains(.autoHideDock))
controller.exit()
XCTAssertEqual(ObjectIdentifier(view.content), identity)
XCTAssertEqual(view.frame, previousFrame)
XCTAssertEqual(presentation, [])
```

- [ ] Run `ampx_test AmpXTheaterTests` red. Add an explicit host presentation enum `.normal`/`.theater`; theater bypasses width-driven scale/height, hides module header/frame/insets, uses black ground, and fills screen.frame. No module-content reconstruction.
- [ ] Capture and restore application presentation options; route F/Escape to enter/exit. If entered from stack, remove only ENTHEA from that host and restore its retained position; if detached, restore its original frame. Use the current screen clamp when the prior screen no longer exists. Do not persist theater geometry as the normal detached frame.
- [ ] Restore presentation options on theater-window close and application termination too. If the user closes ENTHEA in theater, exit presentation before teardown; do not reopen it as a side effect. Keep effective window visibility/occlusion gates active in theater.
- [ ] Run suite and full phase suite, then manually enter/exit from stack and detached states. Commit: `feat(ui): add reversible ENTHEA theater presentation`.

## Phase 5 — Cutover

### Task 18: Application coordination and native menus

**Files:** Create `Sources/AmpXApplicationController.swift`, `Sources/Utilities/AmpXMenuBuilder.swift`; modify `AmpXAppDelegate.swift`, host coordinator, Player's menu button, key router. Test `AmpXApplicationControllerTests.swift`, `AmpXMenuBuilderTests.swift`. Classic remains present until Task 19.

**Interfaces:** `AmpXApplicationController.init(audioPlayer: AudioPlayer, playlistManager: PlaylistManager, hosts: AmpXHostCoordinator)`, `start()`, `terminate()`; `AmpXMenuBuilder.makeMainMenu(application: AmpXApplicationController) -> NSMenu`. Delegate retains controller and shared models. Application exposes `hosts`, `audioPlayer`, and `playlistManager` internally for action dispatch.

- [ ] Add tests for File/Playback/Window menus, one File menu only, Save disabled for empty lists, checked toggles, and close-stack not stopping playback. Use the existing test-isolation pattern for AudioPlayer; do not drive real audio for a menu test.

```swift
let player = AudioPlayer.shared
let manager = PlaylistManager(audioPlayer: MockAudioPlayer(), restoreBookmarks: false,
    restorePlaylist: false, alertPresenter: SilentPlaylistAlertPresenter())
let hosts = AmpXHostCoordinator(state: AmpXModuleOrder(), skin: ClassicModernSkin())
let application = AmpXApplicationController(audioPlayer: player,
    playlistManager: manager, hosts: hosts)
// Construct menus without calling start(), loading media, or showing windows.
let menu = AmpXMenuBuilder.makeMainMenu(application: application)
XCTAssertEqual(menu.items.filter { $0.title == "File" }.count, 1)
let file = try XCTUnwrap(menu.item(withTitle: "File")?.submenu)
file.update()
XCTAssertEqual(file.items.filter { !$0.isSeparatorItem }.map(\.title),
    AmpXMenuCatalog.FileItem.allCases.map(\.rawValue))
let save = try XCTUnwrap(file.item(withTitle: "Save Playlist…"))
XCTAssertFalse(save.isEnabled)
XCTAssertNotNil(save.target)
XCTAssertNotNil(save.action)
```

- [ ] Run new suites red. Move coordination from `ContentView` into `start()`, binding once rather than on each window reopening:

```swift
audioPlayer.onTrackFinished = { [weak playlistManager] in playlistManager?.next() }
audioPlayer.onNextTrackRequested = { [weak playlistManager] in playlistManager?.next() }
audioPlayer.onPreviousTrackRequested = { [weak playlistManager] in playlistManager?.previous() }
```

Preserve guarded startup-sound behavior from `ContentView.loadStartupSound()` and its asynchronous `Track.load`/load completion sequence. Tests must skip live startup playback, as the existing delegate does.

- [ ] Build App/About/Quit, File, Playback, View module toggles, and Window menus. Reuse catalog labels and file shortcut policy. Retire discrete UI Scale entries; do not mutate AmpXMenuCatalog just to remove unused constants. Window includes AmpX reopen and applicable reorder/detach/re-dock/collapse/close operations. Menu items invoke the same coordinator/control actions as UI buttons and accessibility.
- [ ] Preserve native open/save/alert/About presentation and existing EQ/playlist popup menus. Prevent bare menu equivalents from bypassing focused-control routing; key-window/control dispatch must consume those before global menu actions where necessary. Use `validateMenuItem` for current enabled/checked states.
- [ ] Run suites and verify playback completion, media keys, menu actions with stack hidden, Dock reopen, and detached windows remaining open. Commit: `feat(ui): coordinate playback and AppKit menus`.

### Task 19: Remove the migration flag and retired UI families

**Files:** Modify `Sources/AmpXAppDelegate.swift`, `scripts/shoot.sh`, `AGENTS.md`, `docs/WINDOWING_REVIEW.md`; delete `Sources/AmpXMain.swift`, `Sources/AmpXApp.swift`, `Sources/ContentView.swift`, `Sources/AmpXCommands.swift`, `Sources/AmpXSkinSprites.swift`, `Sources/Views/Classic/`, `Sources/Utilities/AmpXHotkeys.swift`, legacy metrics/scale/typography/window helpers listed in the spec, and the panel/dock family. Delete only the 15 retired `AmpXSkin*` imagesets and the four retired suites listed in the spec. Update tests that solely validate the now-deleted bootstrap flag by replacing them with AppKit-launch coverage; retain all protected regression tests.

**Interfaces:** Final app delegate is the only entry point. Keep its test guard and retained application controller; the Classic delegate is gone.

- [ ] Before deletion, run the full suite and capture a new-UI screenshot. Search dependencies:

```bash
rg -n 'AmpXPanelWindowManager|AmpXDockGraph|AmpXUIScale|LegacyPanelMetrics|AmpXSkinSprites|ClassicSkin' Sources Tests
rg -n '@main|AmpXNewUI' Sources scripts Tests
```

Classify each reference as a retired subject, protected test, or remaining caller. Port any remaining UI callers before removal; do not fix compilation by editing audio/ENTHEA internals or deleting protected suites.

- [ ] Make the AppKit delegate own startup directly and remove the bootstrap switch. Transfer `main()` retention logic if needed; only one `@main` remains. Remove legacy files with explicit paths from the spec, after confirming the extracted playlist enum is outside that set.
- [ ] Remove flag-specific screenshot usage while retaining general `--` argument forwarding. Update AGENTS module map and screenshot instructions to the new architecture, preserving unrelated user edits. Add a superseded banner linking the design spec to the old windowing review.
- [ ] Run `./scripts/run-tests.sh`, `./build.sh --release`, `./scripts/shoot.sh`; check no SwiftUI control/view is used in the new primary UI. Existing untouched helpers may still import SwiftUI (spline/representable), so search findings require inspection rather than deleting all imports.
- [ ] Verify no flag or retired production reference remains, and compare the protected regression files to the execution baseline. Commit: `refactor(ui): complete AppKit cutover and remove Classic`.

### Task 20: Acceptance walkthrough and release evidence

**Files:** Update `docs/superpowers/plans/2026-09-11-ampx-ui-visual-checks.md`; modify only task-owned implementation files if acceptance uncovers a defect, with a focused regression test for the defect before fixing it.

**Interfaces:** No new architecture. Validate the spec's complete acceptance table.

- [ ] Record the Xcode/macOS version, tested screen backing scales, window sizes, and build commit. Run the full suite once on the final tree; preserve actual result paths/counts. Don't claim an unavailable 3× display was physically tested: render pixel-grid/geometry offscreen at 3× and label that limitation.
- [ ] Capture scale 0.85/1.0/1.35, expanded/collapsed, detached Playlist/EQ, and all-four-module overflow screenshots. Compare to the cropped PNG panel bounds; document accepted header/padding differences and font fallback behavior. Verify hit areas align after display/backing changes.
- [ ] Exercise this sequence: play a fixture → change EQ and volume → add/reorder/select/crop playlist tracks → detach Playlist → resize both hosts differently → re-dock → close/reopen stack → enter/exit ENTHEA theater → close ENTHEA → relaunch. Confirm playback coordination, persistence, scale rules, view identity, and restored presentation.
- [ ] Perform keyboard-only and VoiceOver passes: activate buttons, adjust every slider, select/read playlist rows, operate every module command, traverse overflow, and restore focus after collapse/reparenting. Record any OS-reserved shortcut conflict and verify equivalent menu/accessibility access. Inspect effective visibility counters and ENTHEA process/render activity during collapse, full viewport clipping, hide, occlusion, and close.
- [ ] If any check fails, add the smallest reproducer to its owning suite, fix that task's implementation, and rerun the affected checks. Once all required checks pass, record remaining environmental limitations honestly; commit: `docs(ui): record AppKit acceptance verification`.

## Spec coverage and handoff

| Spec area | Tasks |
|---|---|
| Scope, models, migration flag, entry point | 1, 5, 18, 19 |
| Theme, geometry, font licensing/fallback, pixel grid | 3, 4, 6, 20 |
| Shared module boundaries/state/persistence | 2, 4, 8 |
| Window close/reopen, sizing, overflow, transfers | 8–10 |
| Theater and mounted view identity | 16, 17 |
| Discrete/continuous state and visibility | 12–16 |
| Player, EQ, Playlist, ENTHEA composition | 6, 7, 13–16 |
| Focus, keyboard, accessibility | 7, 9, 11, 15, 20 |
| Menu/startup/media-key parity | 13, 18 |
| Retirement and regression protection | 1, 19, 20 |

The plan is complete when all task checkboxes and the final evidence document are complete, not merely when the new window appears. Execution can proceed with subagent-driven task/review cycles or inline batches using executing-plans; do not start either until the user chooses execution.

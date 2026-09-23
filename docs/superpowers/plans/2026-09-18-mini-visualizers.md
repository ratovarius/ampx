# Player Mini Visualizers Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans. Follow the test-first steps; keep delegated write sets disjoint.

**Goal:** Ship nine mini visualizers in the current Player, with independently selectable Blue and Classic palettes.

**Architecture:** One analysis tap publishes timed audio snapshots. Pure display state prepares levels and bounded history; a Metal renderer consumes that state. The AppKit well handles selection, persistence, accessibility, fallback, and visibility.

**Tech Stack:** Swift 6, AppKit, MetalKit/Metal, Accelerate, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-17-mini-visualizers-design.md`

**Follow-up:** The user subsequently removed Retro and requested clearer mirroring
and faster Stereo Bars. The current selection has eight styles; the updated spec
and [validation report](2026-09-18-mini-visualizers-validation.md) record those
changes. The original implementation checklist below is retained as history.

## Global constraints

- Existing mini display only; no new windows or Player geometry changes.
- All nine styles; Blue is the default palette.
- Preserve post-EQ/pre-fader analysis and existing ENTHEA calibration.
- Stable preference identifiers with independent fallback and legacy migration.
- Target 60 FPS; bounded particle count 512 and waterfall history four seconds.
- Never wait for GPU work or consumers on the audio callback.
- Use Xcode tests, generating fixtures first; SPM is build-smoke only.
- Preserve pre-existing worktree edits; do not stage unrelated work.

## Shared interfaces

Task 1 produces:

```swift
enum AmpXMiniVisualizerStyle: String, CaseIterable, Sendable {
    case classicSpectrum, smoothSpectrum, dotSpectrum, mirroredSpectrum
    case lineWaveform, waterfall, retro, particleWaveform, stereoBars
    var title: String { get }
    var shaderIndex: UInt32 { get }
    func advanced() -> Self
}
enum AmpXMiniVisualizerPalette: String, CaseIterable, Sendable {
    case blue, classic
    var title: String { get }
}
struct AmpXMiniVisualizerSettings: Equatable {
    var style: AmpXMiniVisualizerStyle = .classicSpectrum
    var palette: AmpXMiniVisualizerPalette = .blue
}
struct AmpXMiniVisualizerSettingsStore {
    init(defaults: UserDefaults = .standard)
    func load() -> AmpXMiniVisualizerSettings
    func save(_ settings: AmpXMiniVisualizerSettings)
}
```

Task 2 produces `AmpXMiniAudioSnapshot` with default-initialized members:

```swift
struct AmpXMiniAudioSnapshot: Sendable {
    var sequence: UInt64 = 0
    var generation: UInt64 = 0
    var time: Double = 0
    var sampleRate: Double = 44100
    var spectrum: [Float] = Array(repeating: 0, count: 32)
    var waveformLeft: [Float] = []
    var waveformRight: [Float] = []
    var rms: SIMD2<Float> = .zero
    var peak: SIMD2<Float> = .zero
    var isPlaying: Bool = false
}
```

Task 3 produces `AmpXMiniVisualizerFrame` and state. Frame members are
`spectrum: [Float]`, `peaks: [Float]`, `trails: [Float]`, `waveform: [Float]`,
`meterLevels: SIMD2<Float>`, `meterPeaks: SIMD2<Float>`, `history: [Float]`
(32 columns × 128 rows, oldest row first), `particleOpacity: Float`,
`elapsed: Float`, `isActive: Bool`. Provide defaults for deterministic fixtures.

```swift
struct AmpXMiniVisualizerState {
    mutating func update(_ snapshot: AmpXMiniAudioSnapshot,
                         at time: Double) -> AmpXMiniVisualizerFrame
    mutating func reset()
}
```

Task 4 produces:

```swift
@MainActor
final class AmpXMiniVisualizerRenderer {
    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice())
    func render(_ frame: AmpXMiniVisualizerFrame,
                style: AmpXMiniVisualizerStyle,
                palette: AmpXMiniVisualizerPalette, in view: MTKView)
    func renderOffscreen(_ frame: AmpXMiniVisualizerFrame,
                         style: AmpXMiniVisualizerStyle,
                         palette: AmpXMiniVisualizerPalette,
                         width: Int, height: Int) throws -> MTLTexture
}
```

The offscreen method is a general capture path, not a test-only production hook.
It uses the same encoding path as the view and waits only for an explicit capture.

## Task 1: Preferences and palettes

Files: create `Sources/Modules/Player/AmpXMiniVisualizerSettings.swift`,
`Sources/Theme/AmpXMiniVisualizerPalette.swift`,
`Tests/AmpXTests/AmpXMiniVisualizerSettingsTests.swift`.

- [x] Add tests for absent preferences, independent invalid values, precedence,
  legacy migration, and round trips. Example independent expected result:
  `defaults.set(1, forKey: "visualizationMode"); XCTAssertEqual(store.load().style, .lineWaveform)`.
- [x] Run the new test target and observe the missing feature.
- [x] Implement the shared interfaces. Store style under `miniVisualizer.style`
  and palette under `miniVisualizer.palette`. Preserve the old key.
  Raw identifiers are explicit stable strings; shader indices follow the shared
  case ordering 0…8.
- [x] Run settings tests and review migration against all three old values.

## Task 2: Timed analysis publication

Files: create `Sources/Audio/AmpXMiniAudioSnapshot.swift`,
`Sources/Audio/AmpXMiniAudioTimeline.swift`,
`Tests/AmpXTests/AmpXMiniAudioTimelineTests.swift`; modify
`FFTSpectrumAnalyzer.swift`, `TapPCMStaging.swift`, `AudioFeatureBus.swift`,
`AudioPlayer.swift` only where publication/reset integrates.

- [x] Test within-batch advancement, sequence monotonicity, stopped silence,
  generation reset, PCM waveform correspondence, mono/LR measurements,
  44.1/48/96/192 kHz, oversized callbacks, and bounded capture overflow.
  A left constant 0.5 and right constant 0.25 must produce RMS/peak `(0.5, 0.25)`.
- [x] Run the new tests against the absent publication.
- [x] Publish spectrum hops and waveform windows at shared sample positions.
  Calculate 50 ms stereo RMS/peak from PCM on the analysis queue.
  Timestamp batches and use the existing playout convention.
  Expose `AudioFeatureBus.miniSnapshot(at:)`.
- [x] Make capture nonblocking and bounded; explicitly mark dropped input as a
  discontinuity. Preserve ENTHEA and spectrum callback behavior.
- [x] Reset the new timeline on track/seek/stop and reject stale generations.
- [x] Run timeline, analyzer, raw-bin, and audio-graph tests.

## Task 3: Pure display state

Files: create `Sources/Visualization/AmpXMiniVisualizerState.swift`,
`Tests/AmpXTests/AmpXMiniVisualizerStateTests.swift`.

- [x] Add tests for calibrated meters, impulse-preserving waveform reduction,
  finite/clamped output, time-based decay, repeated sequence deduplication,
  four-second bounded history, pause/stop, and generation resets.
  Assert meter full-scale at input 1 and zero at input 0, with unequal channels.
- [x] Run and observe the missing state implementation.
- [x] Implement the shared frame/state types and time-based spectrum/peak helpers,
  sanitize malformed input, and keep GPU/AppKit dependencies outside pure state.
- [x] Run display-state tests at multiple simulated frame rates.

## Task 4: Metal effects and captures

Files: create `Sources/Visualization/AmpXMiniVisualizerRenderer.swift`,
`Sources/Shaders/MiniVisualizerShaders.metal`,
`Tests/AmpXTests/AmpXMiniVisualizerMetalTests.swift`.

- [x] Add offscreen rendering tests for all style/palette combinations, dark silence,
  unequal stereo rows, and visually distinct modes. Use fixed signal/time fixtures.
- [x] Run the tests and observe the absent renderer.
- [x] Implement cached pipelines and bounded in-flight buffers. Encode the mode from
  prepared data with explicit palette uniforms. Reuse related spectrum effects;
  use a bounded particle draw and a history texture for their respective modes.
- [x] Share onscreen/offscreen encoding. Return initialization failure without
  crashing; throw capture errors rather than returning an uninitialized texture.
- [x] Run Metal validation and capture all eighteen combinations at 1×/2×.

## Task 5: Player integration

Files: modify `SpectrumWellView.swift`, `PlayerModuleContent.swift`, relevant
mini visualizer wiring/idle/accessibility tests; add
`Tests/AmpXTests/AmpXMiniVisualizerIntegrationTests.swift`.

- [x] Test mode cycling, double-click restoration, context menu selection/checkmarks,
  palette persistence without animation reset, paused redraw, fallback, and visibility.
- [x] Observe failed tests against the old three-mode host.
- [x] Host a manually driven paused MTKView inside the current spectrum rectangle.
  Use the existing display-link lifecycle as the only frame driver.
  Feed `miniSnapshot(at:)` into pure state; render the final settled frame then park.
- [x] Preserve existing deterministic reference presentation explicitly using its
  Retro/Classic data and existing label geometry.
- [x] Wire settings, accessible actions, and generation changes without mutating the
  old SwiftUI wrappers unless shared compatibility requires it.
- [x] Run integration and existing Player/visibility/reference tests.

## Task 6: Verification and review

Files: add `docs/superpowers/plans/2026-09-18-mini-visualizers-validation.md`;
update this checklist as work progresses.

- [x] Run `./scripts/run-tests.sh` after relevant focused suites pass.
- [x] Render and inspect captures at actual size; run `./scripts/shoot.sh`.
- [x] Measure CPU/GPU p95, visibility/idle frame submissions, and steady resource use.
  Record hardware/build settings and actual values; target p95 below 2 ms each.
- [x] Run installed format/lint tools on affected files.
- [x] Request a review of the feature diff including new files, fix supported findings,
  and rerun affected checks.
- [x] Report implementation, validation, and any measured limitation. Keep unrelated
  pre-existing work uncommitted; do not push or merge without authorization.

## Progress

- 2026-09-18: Design approved. Existing linked worktree verified. Baseline suite
  started; the repository runner required its normal uv/Xcode cache access.
- Plan review: Tasks 1/4/5 share the style and palette contracts above; Tasks 2/3/5
  share the audio snapshot; Tasks 3/4/5 share the prepared frame. All definitions
  use the same names and types. Files assigned to concurrent workers are disjoint.

- Implementation and review complete: all nine effects, both palettes, timed audio,
  bounded Metal resources, native interaction, and idle/visibility integration.
- State uses exact time-integrated envelopes because the existing Euler smoother
  caps deltas; this preserves the specified 30/60/120 Hz invariance. Source injection
  uses a closure rather than a one-method protocol.
- 36 effect captures inspected at actual size; live Player screenshot and native
  menu checked. Metal API/GPU validation passed the 19 focused capture/host tests.
- Review regressions include ordered waveform extrema, epoch ordering, hidden
  pause/resume history, callback coalescing, and MTKView drawable advancement.
- Measurements, final full-suite evidence, and limitations are recorded in
  [the validation report](2026-09-18-mini-visualizers-validation.md).

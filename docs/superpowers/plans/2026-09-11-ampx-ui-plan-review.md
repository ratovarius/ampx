# AmpX UI Implementation Plan — Review

**Date:** 2026-09-11
**Subject:** [AmpX UI Implementation Plan](./2026-09-11-ampx-ui.md)
**Spec:** [AmpX UI design](../specs/2026-09-11-ampx-ui-design.md)
**Status:** Findings for the plan author — not an execution authorization.

---

## Verdict

Strong plan. It is above average on the thing plans usually fail at: **every repository
seam it asserts was checked against the tree and all of them are correct.** EQ
normalization-by-12 and the dB/normalized asymmetry, `PlaybackClock.currentTime`,
`CatmullRomSpline` returning a SwiftUI `Path`, the five `EntheaWKHostView` adapter methods,
`shoot.sh` launching without arguments, filesystem-synchronized `Sources/` versus the
explicit `Fonts` PBXGroup. All nineteen Task 19 deletion targets and all four retired suites
exist. The arithmetic in the sample assertions checks out.

The issues below are what should be fixed before execution starts.

---

## Blocking — will fail during execution

### B1. Task 19 leaves the application with no entry point

Task 19 deletes both `Sources/AmpXMain.swift` (which Task 5 established as the only `@main`)
**and** `Sources/AmpXApp.swift`, while listing `Sources/AmpXAppDelegate.swift` only under
*modify*. After the task completes, nothing declares `@main` and there is no `main.swift`.

The checkbox text says "Transfer `main()` retention logic if needed; only one `@main`
remains." Zero remain.

**Fix:** state explicitly which of these happens —

- keep `AmpXMain.swift`, deleting only its `usesNewUI` branch and the `AmpXApp.main()` call; or
- move the entry point onto `AmpXAppDelegate` and say how (`@main` on the delegate with a
  `static func main()`, since `@NSApplicationMain` is deprecated under Swift 6).

Also correct the "Interfaces" line, which currently claims "Final app delegate is the only
entry point" — a delegate is not an entry point by itself.

### B2. Task 18's sample test constructs a live `AudioPlayer`

```swift
let player = AudioPlayer.shared   // ← in the plan
```

`AudioPlayer.init()` at `Sources/AudioPlayer.swift:134` calls `setupAudioEngine()` — which
starts an `AVAudioEngine` and installs the FFT spectrum tap — and `setupRemoteCommands()`,
which registers global `MPRemoteCommandCenter` handlers.

This contradicts the prose in the *same checkbox* ("Use the existing test-isolation pattern
for AudioPlayer; do not drive real audio for a menu test") and the established pattern in the
suite:

- `Tests/AmpXTests/AudioPlayerTests.swift:12` — `AudioPlayer(installRemoteCommands: false)`
- `Tests/AmpXTests/PlaybackIntegrationTests.swift:11` — same

Under subagent-driven execution the sample is copied verbatim, so the prose will not save it.

**Fix:** change the sample to `AudioPlayer(installRemoteCommands: false)`.

### B3. Task 1's modify list is incomplete

Task 1 lists `PlaylistListInteractions.swift`, `AmpXUIScale.swift`, and
`ClassicVisualizerPanelView.swift` as the files touched by the `AmpXMetrics` rename. The
actual reference set is larger:

| File | Sites |
|---|---|
| `Sources/AmpXPanelLayoutState.swift` | 3 (lines 56, 65, 67) |
| `Tests/AmpXTests/ClassicUITests.swift` | 2 (lines 128, 129) |

The rename does not compile without both. The `rg -n '\bAmpXMetrics\b' Sources Tests` step
mitigates *discovery*, but two plan conventions then conflict with it:

- "stage only that task's listed created/modified files" would exclude the files that make
  the build green;
- "No new tests for a mechanical move" sits beside a test file that must in fact change.

**Fix:** add both files to the task's modify list and note that `ClassicUITests.swift` is
edited here and deleted in Task 19.

---

## Factual error

### F1. There are 14 `AmpXSkin*` imagesets, not 15

Both the spec (line 206) and Task 19 say fifteen. Verified:

```
$ ls -d Resources/Assets.xcassets/AmpXSkin*.imageset | wc -l
14
```

`AmpXSkin`, `…Balance`, `…CButtons`, `…Eqmain`, `…Main`, `…Monoster`, `…Numbers`,
`…Playpaus`, `…Pledit`, `…Posbar`, `…Shufrep`, `…Text`, `…Titlebar`, `…Volume`.

Task 19 says "Delete **only** the 15 retired imagesets," so an executor hunting a fifteenth
will either stall or take `AmpXIcon.imageset` — the application icon.

**Fix:** correct the count to 14 in the plan and in the spec.

---

## Reuse the plan misses

### R1. `AmpXEQBands` is never mentioned

`Sources/Audio/AmpXEQBands.swift` is documented in-file as the "single source of truth for UI
labels and `AVAudioUnitEQ` setup":

- `bandCount = 10`
- `centerFrequenciesHz = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]` — exactly
  the spec's list
- a band→x helper, `(index + 0.5) / bandCount * width`, which is precisely what Task 14's
  Catmull-Rom curve needs for control-point placement

Task 14 as written would hardcode all ten labels and reinvent the x-mapping.

**Fix:** add `AmpXEQBands` to Task 14's interfaces and to the spec's reuse list, and state
that labels, count, and curve x-positions come from it.

### R2. JetBrains Mono is already bundled and registered

`Resources/Fonts/JetBrainsMono-{Regular,Bold}.ttf` exist, with both PBXGroup children
(`project.pbxproj:84-85`) and resource build-phase entries (`project.pbxproj:208-209`), and
are registered by `AmpXTypography.registerBundledFonts()`.

Task 19 deletes `AmpXTypography` but **not** the two `.ttf` files or their pbxproj entries, so
unused font resources keep shipping in the bundle. The plan also never states whether Roboto
Mono replaces JetBrains Mono or joins it.

**Fix:** decide replace-vs-keep in Task 3, and if replacing, add the two `.ttf` files plus
their four pbxproj entries to Task 19's deletion list.

### R3. `ATSApplicationFontsPath` already auto-registers `Resources/Fonts/`

`Resources/Info.plist:31` sets `ATSApplicationFontsPath` to `Fonts`, so anything in that
directory is registered by the system at launch — before any `CTFontManagerRegisterFontsForURL`
call runs.

Consequence: Task 3's process-scope registration can return `false` with
`kCTFontManagerErrorAlreadyRegistered`. An executor implementing the spec's "registration
failure falls back to `NSFont.monospacedSystemFont`" *literally* gets a silent fallback while
the font is present and usable — and Task 3's own test ("assert the actual family is Roboto
Mono rather than silently accepting fallback") then fails with a cause that is very hard to
read backwards.

The existing code already sidesteps this: `AmpXTypography.swift:16-22` passes `nil` for the
error out-parameter and determines availability with `NSFont(name:)`.

**Fix:** Task 3 should state that availability is decided by `NSFont(name:)`, not by the
register call's return value, and should call out the already-registered case by name.

### R4. No task touches `Resources/Info.plist`

The spec's migration section asks to "update `Resources/Info.plist` as needed." No task does.
Given R2 and R3, there is real plist-adjacent work (font path contents, possibly the document
types if Classic-era entries are retired).

---

## Spec coverage gaps

### S1. Over-wide centering is neither implemented nor tested

Spec line 115: "beyond `490 * 1.35`, the window grows while the composition remains **centered**
at scale 1.35."

No task produces the horizontal offset this requires. `AmpXLayoutResult.frames` is the only
geometry output in the plan, and the Task 4 and Task 9 assertions cover scale clamping only —
none checks a frame origin at a width above 661.5.

**Fix:** add a `calculate` assertion at, say, width 800 that pins `frames[.player]!.minX` to
`(800 - 490 * 1.35) / 2`.

### S2. Minimum window width is never applied

Spec line 115 sets a 416.5 pt minimum. Neither Task 5 (window creation) nor Task 9 (resizing)
sets `contentMinSize` / `minSize`. The clamp in `AmpXLayout.scale` prevents the *composition*
from shrinking further but does not stop the window.

### S3. Smaller omissions

| Item | Where | Note |
|---|---|---|
| Amber scrollbar arrows | spec:162 | Task 7's `AmpXScrollbar` interface exposes only `offset` / `contentLength` / `viewportLength` / `onScroll` — no arrow or step semantics |
| `ViewItem.visualizer = "Visualizer"` | Task 18 | The catalog's label says "Visualizer" while the module is ENTHEA, and the task forbids mutating the catalog to fix it |
| `selection` mutability | Task 15 | `PlaylistSelectionModel` is a **struct** with `mutating func selectOnly` (`Sources/Playlist/PlaylistSelectionModel.swift:15`), so the sample's `adapter.selection.selectOnly(b.id)` requires `var selection`, not `private(set)`. The interface block doesn't say so |
| kbps/kHz typography decision | spec:58 | Phase 1 is supposed to decide whether these need segment treatment; Task 6 never records it as a deliverable |
| AUTO-preamp round-trip | Task 14 | The hazard is correctly *anticipated* in prose but no assertion pins it |

---

## Against the writing-plans standard

### P1. Task granularity — the largest deviation

The skill asks for one action per step, 2–5 minutes each. Several checkboxes are multi-day:

- **Task 6, checkbox 2** — the complete Player composition *plus* EQ *plus* Playlist, all
  reference-matched, in one box.
- **Task 15, checkbox 4** — ADD / REM / SEL / MISC / LIST OPTS, five menu families, one box.
- **Task 19** — an entire cutover in five boxes.

This matters most because the plan header mandates `subagent-driven-development`: one
subagent owns one task with no prior context and no way to checkpoint inside a box.

**Fix:** split Task 6 into measurement → Player → EQ → Playlist; split Task 15's menu wiring
per family; split Task 19 into dependency-sweep → entry-point → file deletion → asset/test
deletion → documentation.

### P2. No Consumes / Produces blocks

Every task carries an "Interfaces:" section, but written as a declaration sketch rather than
the skill's Consumes/Produces split. A Task 13 subagent needs
`AmpXContinuousView.setEffectivelyVisible` / `tick` (Task 12), `AmpXSlider.onChange` and
`AmpXControlMath` (Task 7), and `AmpXSkin` (Task 3) — none restated where that subagent reads.

### P3. Implementation steps that describe without showing

Tasks 7, 10, 11, 15, and 16 carry long prose checkboxes whose only code blocks are test
assertions. The skill treats "implement hover/pressed/active/disabled drawing" and "implement
grip tracking, threshold 40 pt, insertion marker, and 150–200 ms settle" as plan failures.

**One fair caveat:** Task 6's geometry genuinely cannot be coded before measurement — the spec
itself defers it to Phase 1 discovery (spec:35). The remedy there is not inline code, it is
making measurement its own task that emits a concrete metrics table, which the composition
tasks then cite by name.

---

## Verified correct — keep as-is

These were checked against the tree and hold:

| Claim | Evidence |
|---|---|
| `eqBandValues` / `eqPreampValue` normalized; `setEQBand` takes dB, `setEQPreamp` takes normalized | `AudioPlayer.swift:668` (`gain / 12`), `:685-687` |
| AUTO overwrites `eqPreampValue` while `manualPreampValue` persists | `AudioPlayer.swift:729`, `:719` — the feedback hazard Task 14 flags is real |
| `PlaybackClock.currentTime` already sampled; `currentTime` forwards | `AudioPlayer.swift:17-31` |
| `CatmullRomSpline.path(through:)` returns SwiftUI `Path` | `Sources/Utilities/CatmullRomSpline.swift:5` |
| `EntheaWKHostView` exposes all five adapter methods | `Sources/Enthea/EntheaWebView.swift:78, 100, 109, 115, 131` |
| `shoot.sh` relaunches via bare `open -n "$APP_PATH"` | `scripts/shoot.sh` |
| `Sources/` filesystem-synchronized; `Fonts` an explicit PBXGroup | `project.pbxproj:32-51`, `:81-88` |
| `NSView.displayLink(target:selector:)` available | deployment target `MACOSX_DEPLOYMENT_TARGET = 26.4` |
| All 19 Task 19 deletion targets and 4 retired suites exist | filesystem check |
| `align(0.26, backingScale: 2) == 0.5` | `round(0.52)/2` — matches spec:63 |
| `strokeRect` → `minX 0.5`, `maxX 9.5` | half-`lineWidth` inset, self-consistent |
| `scale(416.5) == 0.85`, `scale(661.5) == 1.35` | exact clamp boundaries |
| Task 9's overflow assertions | hold for any value of the unmeasured playlist chrome constant — good robustness |
| `Track(title:artist:url:)`, `PlaylistManager(audioPlayer:restoreBookmarks:restorePlaylist:alertPresenter:)`, `MockAudioPlayer`, `SilentPlaylistAlertPresenter`, `AmpXMenuCatalog.FileItem`, `spectrumSnapshot(at:)`, `AmpXPlaylistKeyboard.Handling` | all exist with the shapes the samples use |

Also worth keeping: Task 16's fake-host test paired with "a fake alone cannot prove WebView
behavior"; and Task 20's explicit refusal to claim an untested 3× display.

---

## Suggested fix order

1. **B1, B2, B3** — correctness of execution; cheap edits.
2. **F1** — one number, two documents.
3. **R1, R2, R3, R4** — reuse and font correctness; R3 in particular prevents a confusing
   mid-execution failure.
4. **S1, S2** — add the two missing assertions and the `contentMinSize` line.
5. **P1** — resplit Tasks 6, 15, and 19 before dispatching any subagent.
6. **P2, P3, S3** — quality pass over the remaining task bodies.

# DJ Mode Automix (Delivery 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play the Playlist as a continuous, beat-matched set: two decks, mix points from rekordbox phrases or the beatgrid, Crossfade or Bass Swap, tempo kept after each blend, and MIXES WELL continuing the set when the Playlist runs out.

**Architecture:**
- **Pure planning in `Sources/DJ/`:** beatgrid maths, mix points, tempo, the blend curve and settings. These are all value types and fully unit-tested.
- **Audio graph:** `AudioGraph` gains a two-deck mode (`player → timePitch → eq → fade mixer → deckSum → effects`). `AudioPlayer` keeps a live deck and an idle deck, and on its audio queue runs a 10 ms blend ticker that applies the plan.
- **Coordination:** a MainActor `AutomixCoordinator` connects `PlaylistManager` (what plays next, `AUTO` picks), the library (grids, phrases, rows) and the settings, and arms one transition at a time.

**Tech Stack:** Swift 6 (strict concurrency `complete`), AVFoundation (`AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioUnitTimePitch`, `AVAudioUnitEQ`, `AVAudioMixerNode`), SwiftData through the existing `LibraryStore`/`LibraryIndex` actors, AppKit menus, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-11-dj-mode-design.md` (Revision 2, § Delivery 2: Automix, plus § Track classes and § Continue with MIXES WELL). Revision 1's two-deck notes are in git at `7354c81~1` (§ Two gain stages, § Position and transport).

**Branch:** `feature/dj-mode-automix`, cut from `feature/dj-mode-library-data` (PR #16; it needs Delivery 1's data). Rebase onto `develop` once PR #16 merges.

## Global Constraints

- Swift 6, strict concurrency `complete`; macOS 26; no new dependencies.
- The `AVAudioEngine` graph is touched only on `AudioPlayer.audioQueue`. `AudioGraph` stays `@unchecked Sendable` under that rule.
- **Automix off:** single-deck playback, exactly as today. `AudioPlayerTests`, `PlaybackIntegrationTests` and `AudioGraphTests` pass with no edits.
- Tempo clamp **±6%**. Plain crossfade: **6 s**, equal-power, no tempo change.
- Blend lengths: Last Phrase **8 · 16 · 32** bars (default 16); Intro / Outro longest blend **16 · 32 · 64** (default 32).
- Glide speed **0.05 · 0.1 · 0.2 BPM per 4 bars** (default 0.1); glide off by default.
- Phrase length **16 bars**; blends round down to **4 bars**.
- Bass Swap low cut: high-pass at **150 Hz** for the first half of the blend.
- Settings defaults:
  - Mix points **Intro / Outro**; Transition **Crossfade**; continuation **on**; Pick from **Current view**; Automix **off**.
- Menu copy, verbatim from the spec:
  - **Playback ▸ Automix**, **Playback ▸ Automix Options**.
  - `Last Phrase`, `Intro / Outro`, `Crossfade`, `Bass Swap`, `Whole library`, `Current view`, `AUTO`.
- Ramps follow audio time, not wall time. Pause freezes them.
- Never add `Co-Authored-By:` to commits. Swift formatting is automatic (hook); never run `swiftformat` by hand.
- Run tests per suite locally:
  ```
  xcodebuild test -project AmpX.xcodeproj -scheme AmpX -destination "platform=macOS,arch=$(uname -m)" -only-testing:AmpXTests/<Suite> 2>&1 | grep -E 'error: |failed \(|TEST (SUCCEEDED|FAILED)'
  ```
  Leave the full suite to CI.
- Do not launch the dev build against the real library (V3 migration); app checks use a copy (Task 12).

## Decisions this plan makes (not in the spec)

| Decision | Why |
|---|---|
| `AudioGraph(engine:source:)` stays a single-source graph. A new `AudioGraph.twoDeck(engine:)` builds the deck graph. `tapPoint` becomes `effects.last?.outputNode ?? upstream`, where `upstream` is `source` (single) or `deckSum` (two-deck). | `AudioGraphTests` assert `graph.source` feeds the first effect directly. The spec's "source becomes the live deck's player" would break them, and the spec also requires them to pass unmodified. |
| The blend ticker is a `DispatchSourceTimer` on `audioQueue`, not its own queue. | The graph may only be touched on `audioQueue`; a separate queue would hop there anyway. |
| Blend progress is taken from the **outgoing** deck's sample clock for the whole blend, including after the transport switch. | A plays until the blend ends; one clock gives one monotonic progress. |
| B is loaded onto the idle deck 10 s before mix-out ("prepare") and started with `play(at:)` using a **host time** computed 1 s before mix-out ("arm"). Glide is frozen from prepare. | A host time is shared by both decks, so output latency cancels. Freezing the glide keeps the computed start time valid. |
| Bass Swap's cut switch happens in one `audioQueue` block at the first tick past the switch bar (≤ 10 ms late), not in the same render quantum. | AVAudioEngine has no render-quantum-scheduled parameter changes for these units. |
| Turning Automix off mid-blend lets the running blend finish; no new transition is armed. | The spec covers mid-track only; cutting a blend short would be audible. |
| `AUTO` marks and the "removed AUTO" list live in memory only (not persisted). | They are steering for the current set. |
| Rekordbox PSSI beat numbers are 1-based indexes into the track's beatgrid (beat 1 = the grid's first beat). | Deep Symmetry's description. Task 2's tests pin this, so a wrong reading shows up in Task 12's listening check. |

## Review Focus

1. **Playlist edited while a transition is prepared or armed** (next track removed, moved, or a track inserted before it): B is unscheduled, the idle deck is stopped, and the next track is re-read. Up to 5 s before mix-out this re-arms; after that the plan stands. Test in Task 10.
2. **ReplayGain read finishing mid-blend** for the incoming track: the gain lands on B's player node and the fade envelope does not jump. Test in Task 8.
3. **Pause mid-blend, then seek:** pause freezes both decks and the ramp; the seek aborts the blend, stops the non-live deck, restores the live deck's fade to 1 with no cut, and seeks it. Test in Task 9.
4. **A track that is not in the library, or is unavailable** (dropped from Finder) next to a library track: no grid data, so a plain crossfade, never a crash or a beat-matched guess. Tests in Task 3 (planner) and Task 10 (coordinator).
5. **Playing position already past the mix-out when the plan is made** (a track started near its end, or a seek past it):
   - A plain crossfade at A's content end. It starts 6 s before the end, or now if that is later.
   - Under 1 s left, no transition: normal advance.
   - Test in Task 3.

---

### Task 1: Automix settings

**Files:**
- Create: `Sources/DJ/AutomixSettings.swift`
- Test: `Tests/AmpXTests/AutomixSettingsTests.swift`

**Interfaces:**
- Produces:
  - `enum MixPointMethod: String, Codable, CaseIterable { case lastPhrase, introOutro }`
  - `enum TransitionStyle: String, Codable, CaseIterable { case crossfade, bassSwap }`
  - `enum PickPool: String, Codable, CaseIterable { case wholeLibrary, currentView }`
  - `struct AutomixSettings: Codable, Equatable, Sendable` with:
    - `enabled = false`, `mixPoints = .introOutro`, `transition = .crossfade`
    - `lastPhraseBlendBars = 16`, `longestBlendBars = 32`
    - `glideBack = false`, `glideSpeed = 0.1`
    - `continueWithMixesWell = true`, `pickFrom = .currentView`
    - statics: `lastPhraseBlendChoices = [8, 16, 32]`, `longestBlendChoices = [16, 32, 64]`, `glideSpeedChoices = [0.05, 0.1, 0.2]`
  - `final class AutomixSettingsStore` (`@MainActor`, `ObservableObject`):
    - `init(defaults: UserDefaults)`
    - `@Published var settings: AutomixSettings`, which persists on `didSet` as JSON under the key `"AmpX.automixSettings"`
    - `var pickFilter: LibraryQuery?`, stored as JSON under `"AmpX.automixPickFilter"`

- [ ] **Step 1: Write the failing tests**
  - `testDefaultsMatchSpec`: every default listed above.
  - `testSettingsRoundTripThroughDefaults`: change all fields, create a new store on the same suite, and get equal settings back.
  - `testCorruptSettingsFallBackToDefaults`: write `Data("x".utf8)` under the key and get `AutomixSettings()`.
  - `testPickFilterRoundTrip`: a `LibraryQuery` with a search, a genre and a BPM range survives the round trip.
  - Use `UserDefaults(suiteName: UUID().uuidString)!`.
- [ ] **Step 2: Run** `-only-testing:AmpXTests/AutomixSettingsTests`. Expected: build fails, `AutomixSettings` is not defined.
- [ ] **Step 3: Implement** `Sources/DJ/AutomixSettings.swift` as above.
- [ ] **Step 4: Run again.** Expected: `TEST SUCCEEDED`.
- [ ] **Step 5: Commit** `feat(dj): Automix settings and persisted pick filter`.

### Task 2: Beatgrid maths

**Files:**
- Create: `Sources/DJ/MixGrid.swift`
- Test: `Tests/AmpXTests/MixGridTests.swift`

**Interfaces:**
- Consumes: `RekordboxBeat` (`start` s, `bpm`, `meter`, `beat` = position in bar 1–4 of the segment's first beat), `RekordboxBeatGrid.unpack(_:)`.
- Produces: `struct MixGrid: Equatable, Sendable`.
  - `init?(segments: [RekordboxBeat], duration: Double)`: nil for an empty grid or a non-positive BPM.
  - `func time(ofBeat index: Int) -> Double`: 0-based beat index from the grid's first beat. Segment *i* spans from its `start` to the next `start` (the last one to `duration`), with beats every `60 / bpm`.
  - `func beat(at time: Double) -> Double`: fractional inverse of `time(ofBeat:)`.
  - `var firstDownbeat: Int`: 0-based index, `(5 − segments[0].beat) % 4`.
  - `func time(ofBar bar: Int) -> Double`: bar 0 starts at `firstDownbeat`; bar *k* at beat `firstDownbeat + 4k`.
  - `func bar(at time: Double) -> Double`: fractional bar.
  - `func localBPM(at time: Double) -> Double`: the BPM of the segment containing `time`.
  - `func phraseBeatTime(_ oneBasedBeat: Int) -> Double`: `time(ofBeat: oneBasedBeat − 1)`.
  - `var lastFullBar: Int`: the last bar that ends at or before `duration`.

- [ ] **Step 1: Write the failing tests**
  - `testSteadyGrid`: one segment, start 0.5 s, 120 BPM, beat 1, duration 300.
    - `time(ofBeat: 4) == 2.5`, `firstDownbeat == 0`, `time(ofBar: 1) == 2.5`.
    - `bar(at: 4.5) == 2.0`, `lastFullBar == 148`: bar 148 ends at 0.5 + 149·2 = 298.5 ≤ 300.
  - `testFirstBeatMidBar`: segment `beat: 3` gives `firstDownbeat == 2`.
  - `testTwoSegments`: 0 s @ 120 and 10 s @ 125. Then `time(ofBeat: 20) == 10.0` and `time(ofBeat: 21) == 10.48`; `localBPM(at: 11) == 125`.
  - `testPhraseBeatIsOneBased`: `phraseBeatTime(1) == time(ofBeat: 0)`.
  - `testRejectsEmptyAndZeroBPM`.
- [ ] **Step 2: Run** `-only-testing:AmpXTests/MixGridTests`. Expected: FAIL (`MixGrid` is not defined).
- [ ] **Step 3: Implement** `MixGrid`. Precompute each segment's first beat index once in `init`.
- [ ] **Step 4: Run again.** Expected: `TEST SUCCEEDED`.
- [ ] **Step 5: Commit** `feat(dj): beatgrid maths for mix points`.

### Task 3: Mix points and tempo matching

**Files:**
- Create: `Sources/DJ/MixPoints.swift`, `Sources/DJ/TempoPlan.swift`
- Test: `Tests/AmpXTests/MixPointsTests.swift`, `Tests/AmpXTests/TempoPlanTests.swift`

**Interfaces:**
- Consumes:
  - From Task 2: `MixGrid`.
  - Existing: `TrackClass`, `RekordboxPhraseAnalysis` (`endBeat`, and `phrases` of `(beat, kind: .intro/.outro/.other)`).
  - From Task 1: `AutomixSettings`.
- Produces:
  - `struct AutomixTrack: Equatable, Sendable { let duration: Double; let trackClass: TrackClass; let grid: MixGrid?; let phrases: RekordboxPhraseAnalysis? }`
    - `static func unknown(duration: Double) -> AutomixTrack`: class `.noGrid`, no data.
  - `enum TempoPlan`:
    - `static let clamp = 0.06`
    - `static func octaveFactor(incoming: Double, outgoing: Double) -> Double`: the factor in {0.5, 1, 2} minimising `|incoming·f − outgoing|`.
    - `static func matchRate(outgoingEffectiveBPM: Double, incomingLocalBPM: Double) -> Double?`: equals `outgoing / (incoming · octaveFactor)`; nil when `|rate − 1| > clamp`.
    - `static func glideStep(currentBPM: Double, originalBPM: Double, nextBPM: Double?, speedPer4Bars: Double) -> Double`: the BPM after one bar; see Task 4.
  - `struct MixPlan: Equatable, Sendable`:
    - `enum Kind: Equatable, Sendable { case beatmatched(rate: Double, transition: TransitionStyle); case crossfade }`
    - Fields: `kind`, `outgoingStart: Double` (A file seconds), `incomingStart: Double` (B file seconds), `length: Double` (A file seconds), `blendBars: Int` (0 for a crossfade), `switchTime: Double` (A file seconds; Bass Swap bar nearest the midpoint, else the midpoint).
  - `enum MixPoints`:
    - `static func contentEnd(_ a: AutomixTrack) -> Double`: in order, the phrase end beat time, then the last full bar's end, then `duration`.
    - `static func plan(outgoing a: AutomixTrack, incoming b: AutomixTrack, outgoingRate: Double, outgoingPosition: Double, settings: AutomixSettings) -> MixPlan?`: nil means no transition (normal advance).

**Rules `plan` implements** (spec § Mix points, § Tempo; edge-case table):
1. Plain crossfade when:
   - either side's class is `.set`, `.changing` or `.noGrid`, or
   - `matchRate` is nil, using A's local BPM × `outgoingRate` at mix-out and B's local BPM at its mix-in.

   The crossfade: `length = 6`, `outgoingStart = contentEnd(a) − 6`, `incomingStart = 0`.
2. **Last Phrase:** `blend = settings.lastPhraseBlendBars`. `b` = the largest multiple of 16 bars with `b + blend ≤ endBar`, where `endBar` = A's content end in bars, floored. B comes in at bar 0.
3. **Intro / Outro**, when both have phrases:
   - B's intro = bars from bar 0 to the first phrase after the leading `.intro` run.
   - A's outro = bars from the first phrase of the trailing `.outro` run to `endBeat`.
   - `blend = min(intro, outro, longestBlendBars)`, rounded down to 4.
   - A mixes out at `endBar − blend`; B mixes in at bar `intro − blend`.
   - If either track has no phrases, or `blend < 4`, use Last Phrase.
4. **B shorter than the blend:** if `blend` bars at B's tempo exceed B's duration, `blend` becomes a third of B's duration in bars, rounded down to 4. Under 4 bars, plain crossfade.
5. **Already past the start** (the spec's "seek past it"): if `outgoingPosition > outgoingStart`, make a plain crossfade at A's content end.
   - `outgoingStart = max(outgoingPosition, contentEnd(a) − 6)`, and `length = contentEnd(a) − outgoingStart`.
   - If that length is under 1 s, return nil.
6. `length` in A file seconds = `time(ofBar: out + blend) − time(ofBar: out)`. `switchTime` = the time of bar `out + round(blend / 2)`.

- [ ] **Step 1: Write the failing tests** (fixture grids built with `MixGrid(segments:duration:)`; phrase fixtures built directly):
  - `testContentEndPrefersPhraseEndBeat`; `testContentEndFallsBackToLastFullBar`; `testContentEndWithoutGridIsDuration`.
  - `testLastPhrasePicksLast16BarBoundaryThatFits`: 128 BPM from 0 s, A content end at bar 200, blend 16 gives out at bar 176 and B in at bar 0.
  - `testIntroOutroUsesShorterOfIntroAndOutro`: B intro 32 bars, A outro 16 bars → blend 16; B mixes in at bar 16; A out at `endBar − 16`.
  - `testIntroOutro14BarIntroRoundsDownTo12`: the spec's 14-bar intro.
  - `testIntroOutroCappedByLongestBlend`: intro 64, outro 64, longest 32 → 32.
  - `testIntroOutroFallsBackToLastPhraseWithoutPhrases`; `testIntroOutroUnder4BarsFallsBack`.
  - `testSetChangingOrNoGridGivesPlainCrossfade`: each of the three, on either side; length 6.
  - `testUnknownTrackGivesPlainCrossfade`: `AutomixTrack.unknown`. This is Review Focus 4.
  - `testTempoOutsideClampGivesCrossfade`: 128 against 138.
  - `testHalfTempoTrackIsOctaveNormalised`: 174 against 87 → `.beatmatched(rate: 1.0, …)`.
  - `testShortIncomingShortensBlendToAThird`; `testVeryShortIncomingGivesCrossfade`.
  - `testPositionPastMixOutGivesCrossfadeAtContentEnd`: 20 s before the end gives start `end − 6`.
  - `testPositionInsideLastSixSecondsCrossfadesOverRemaining`.
  - `testUnderOneSecondLeftGivesNil`.
  - The last three are Review Focus 5.
  - `testBassSwapSwitchIsBarNearestMidpoint`.
  - `TempoPlanTests`:
    - `testMatchRateWithinClamp`: 126 → 128 gives rate 128/126.
    - `testMatchRateOutsideClampIsNil`.
    - `testOctaveFactor`: 87 vs 174 gives 2; 176 vs 88 gives 0.5.
- [ ] **Step 2: Run** `-only-testing:AmpXTests/MixPointsTests -only-testing:AmpXTests/TempoPlanTests`. Expected: FAIL (types are not defined).
- [ ] **Step 3: Implement** `MixPoints.swift` and the `octaveFactor`/`matchRate` part of `TempoPlan.swift`. `glideStep` comes in Task 4; until then it returns `currentBPM`.
- [ ] **Step 4: Run again.** Expected: `TEST SUCCEEDED`.
- [ ] **Step 5: Commit** `feat(dj): mix points and tempo matching`.

### Task 4: Glide back and the blend curve

**Files:**
- Modify: `Sources/DJ/TempoPlan.swift`
- Create: `Sources/DJ/BlendCurve.swift`
- Test: `Tests/AmpXTests/TempoPlanTests.swift`, `Tests/AmpXTests/BlendCurveTests.swift`

**Interfaces:**
- Produces:
  - `TempoPlan.glideStep(currentBPM:originalBPM:nextBPM:speedPer4Bars:)`:
    - It moves by `speedPer4Bars / 4` toward `originalBPM` only when that also moves toward `nextBPM`, octave-normalised with `octaveFactor`.
    - It never overshoots `originalBPM`, and returns `currentBPM` when `nextBPM` is nil.
    - It works in both directions.
  - `struct BlendCurve: Equatable, Sendable`:
    - `init(plan: MixPlan)`
    - `func progress(atOutgoingTime t: Double) -> Double`: clamped to 0…1 over `[outgoingStart, outgoingStart + length]`.
    - `func gains(at progress: Double) -> (outgoing: Float, incoming: Float)`: `(cos(p·π/2), sin(p·π/2))`.
    - `func lowCut(atOutgoingTime t: Double) -> (outgoing: Bool, incoming: Bool)`: Bass Swap only, `(t >= switchTime, t < switchTime)`; `(false, false)` otherwise.
    - `func isPastSwitch(atOutgoingTime:) -> Bool`: drives the transport switch.

- [ ] **Step 1: Write the failing tests**
  - `testGlideMovesTowardOriginalWhenNextLiesThatWay`: current 128, original 124, next 122, speed 0.1 → 127.975.
  - `testGlideHoldsWhenNextLiesTheOtherWay`: next 130 → 128.
  - `testGlideStopsAtOriginal`: current 124.01 → 124.
  - `testGlideUpward`; `testGlideHoldsWithoutNext`; `testGlideOctaveNormalisesNext`: next 62 against 124 counts as 124.
  - `BlendCurveTests`:
    - `testEqualPowerSumIsOne`: `g.outgoing² + g.incoming² ≈ 1` at 11 points.
    - `testProgressClampsAndIsLinearInOutgoingTime`.
    - `testBassSwapCutSwitchesOnce`: incoming cut before `switchTime`, outgoing cut after.
    - `testCrossfadeNeverCuts`.
- [ ] **Step 2: Run** `-only-testing:AmpXTests/TempoPlanTests -only-testing:AmpXTests/BlendCurveTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run again.** Expected: `TEST SUCCEEDED`.
- [ ] **Step 5: Commit** `feat(dj): glide back and equal-power blend curve`.

### Task 5: Library data for Automix

**Files:**
- Modify: `Sources/Library/LibraryIndex.swift`, `Sources/Library/LibraryStore+Rekordbox.swift`
- Create: `Sources/DJ/AutomixLibrary.swift`
- Test: `Tests/AmpXTests/AutomixLibraryTests.swift`

**Interfaces:**
- Consumes: from Task 3, `AutomixTrack`; existing `LibraryRow.trackClass`, `RekordboxBeatGrid.unpack`, `RekordboxAnalysisFile.unpack`, `LibraryQuery.evaluate`.
- Produces:
  - `LibraryIndex.row(url: URL) throws -> LibraryRow?`, matching the standardized file URL.
  - `LibraryIndex.rows(matching query: LibraryQuery) throws -> [LibraryRow]`.
  - `LibraryIndex.allRows() throws -> [LibraryRow]`.
  - `LibraryStore.mixData(rowID: UUID) throws -> (beatGrid: Data?, phrases: Data?)`.
  - `protocol AutomixLibrary: Sendable` (implemented by `LibraryEngineAutomixLibrary` over a `LibraryEngine`):
    - `func track(url: URL, duration: Double) async -> (row: LibraryRow?, track: AutomixTrack)`: `AutomixTrack.unknown` when the URL isn't in the library or the row is unavailable.
    - `func pool(_ pickFrom: PickPool, filter: LibraryQuery?) async -> [LibraryRow]`: available rows only; a nil filter means the whole library.

- [ ] **Step 1: Write the failing tests** (in-memory engine, same setup as the existing `LibraryEngine` tests; fixture rows with a packed grid and packed phrases):
  - `testTrackForLibraryURLHasGridPhrasesAndClass`.
  - `testTrackForUnknownURLIsUnknown`.
  - `testUnavailableRowIsUnknown`.
  - `testPoolCurrentViewAppliesFilter`: genre filter.
  - `testPoolWholeLibraryIgnoresFilter`.
  - `testPoolExcludesUnavailable`.
  - `testPoolWithoutPersistedFilterIsWholeLibrary`.
- [ ] **Step 2: Run** `-only-testing:AmpXTests/AutomixLibraryTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** `mixData` fetches one `LibraryTrack` by id on the store's context.
- [ ] **Step 4: Run again,** plus `-only-testing:AmpXTests/LibraryIndexTests`. Expected: `TEST SUCCEEDED`.
- [ ] **Step 5: Commit** `feat(dj): library lookups for Automix`.

### Task 6: Two-deck audio graph

**Files:**
- Modify: `Sources/Audio/AudioGraph.swift`
- Create: `Sources/Audio/AudioDeck.swift`
- Test: `Tests/AmpXTests/AudioGraphDeckTests.swift` (`AudioGraphTests` stays untouched)

**Interfaces:**
- Produces:
  - `final class AudioDeck: @unchecked Sendable` with:
    - nodes: `player: AVAudioPlayerNode`, `timePitch: AVAudioUnitTimePitch`, `lowCut: AVAudioUnitEQ` (one band, `.highPass`, 150 Hz), `fade: AVAudioMixerNode`
    - `func setRate(_ rate: Float)`: bypasses `timePitch` at exactly 1.
    - `func setLowCut(_ on: Bool)`: bypasses the EQ when off.
    - `func reset()`: rate 1, cut off, `fade.outputVolume = 1`.
  - `AudioGraph`:
    - `static func twoDeck(engine: AVAudioEngine = AVAudioEngine()) -> AudioGraph`
    - `let decks: [AudioDeck]` (empty in single-source mode)
    - `private(set) var liveDeckIndex = 0`; `func setLiveDeck(_ index: Int)`
    - `var source: AVAudioPlayerNode`: the live deck's player in two-deck mode, the given source otherwise.
    - `upstream: AVAudioNode`: `deckSum` or `source`.
    - `tapPoint = effects.last?.outputNode ?? upstream`; `reconnect()` wires `upstream`.

- [ ] **Step 1: Write the failing tests**
  - `testTwoDeckChainFeedsDeckSumIntoFirstEffect`: each deck's `fade` feeds `deckSum`; `deckSum` feeds `eq.inputNode`.
  - `testTwoDeckTapPointIsLastEffect`.
  - `testTwoDeckEmptyChainTapIsDeckSum`.
  - `testSourceFollowsLiveDeck`.
  - `testDeckResetRestoresUnityAndBypass`.
  - `testRateOneBypassesTimePitch`.
- [ ] **Step 2: Run** `-only-testing:AmpXTests/AudioGraphDeckTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Each deck is wired `player → timePitch → lowCut → fade → deckSum`.
- [ ] **Step 4: Run** `-only-testing:AmpXTests/AudioGraphDeckTests -only-testing:AmpXTests/AudioGraphTests`. Expected: both `TEST SUCCEEDED`, and `AudioGraphTests` unedited.
- [ ] **Step 5: Commit** `feat(audio): two-deck graph mode`.

### Task 7: AudioPlayer on two decks, single-deck behaviour unchanged

**Files:**
- Modify: `Sources/AudioPlayer.swift`
- Test: `Tests/AmpXTests/AudioPlayerDeckTests.swift`; existing `AudioPlayerTests` and `PlaybackIntegrationTests` stay unedited.

**Interfaces:**
- Consumes: Task 6's `AudioGraph.twoDeck`, `AudioDeck`.
- Produces:
  - `AudioPlayer` builds `AudioGraph.twoDeck()`. `playerNode` becomes `graph.source` (the live deck).
  - A per-deck state struct `DeckPlayback` on `audioQueue`:
    - `file: AVAudioFile?`, `segmentStart: TimeInterval`, `generation: Int`, `replayGain: ReplayGain`, `normalizationGain: Float`
    - the existing `audioFile` / `playbackSegmentStartTime` / `playbackGeneration` read from the live deck's entry.
  - `applyPlayerVolume()` writes each deck's own normalization gain to that deck's `player.volume`, and the fader to `mainMixer`. Pan is applied to both players.
  - `loadTrack` stops both decks, calls `reset()` on both, and cancels any armed transition (Task 9 fills that in). Manual play is therefore always at the original tempo.
  - Test hook: `testing_deckSnapshot(completion: @Sendable ([DeckSnapshot]) -> Void)`, where `DeckSnapshot` has `rate`, `lowCut`, `fade`, `playerVolume`, `isPlaying` and `isLive`.

- [ ] **Step 1: Write the failing tests**
  - `testLoadResetsBothDecksToUnity`: after `testing_` rate/fade changes on both decks.
  - `testSingleDeckPlaybackUsesLiveDeckOnly`: play a fixture, then the idle deck is not playing.
  - `testReplayGainAppliesToLiveDeckPlayer`.
  - `testBalanceAppliesToBothDecks`.
- [ ] **Step 2: Run** `-only-testing:AmpXTests/AudioPlayerDeckTests`. Expected: FAIL.
- [ ] **Step 3: Implement the refactor.** Keep every existing method's observable behaviour; only the storage moves to the live deck's `DeckPlayback`.
- [ ] **Step 4: Run** `-only-testing:AmpXTests/AudioPlayerDeckTests -only-testing:AmpXTests/AudioPlayerTests -only-testing:AmpXTests/PlaybackIntegrationTests -only-testing:AmpXTests/AudioGraphTests`. Expected: all `TEST SUCCEEDED` with the existing suites unedited.
- [ ] **Step 5: Commit** `refactor(audio): AudioPlayer keeps per-deck state on a two-deck graph`.

### Task 8: Transitions in AudioPlayer

**Files:**
- Create: `Sources/AudioPlayer+Automix.swift`, `Sources/DJ/DeckSync.swift`
- Modify: `Sources/AudioPlayer.swift` (completion routing, `loadTrack` cancel, seek abort, pause)
- Test: `Tests/AmpXTests/DeckSyncTests.swift`, `Tests/AmpXTests/AudioPlayerTransitionTests.swift`

**Interfaces:**
- Consumes: Tasks 3–4 (`MixPlan`, `BlendCurve`, `TempoPlan.matchRate`), Task 7 (`DeckPlayback`, `AudioDeck`).
- Produces:
  - `enum DeckSync`:
    - `static func startHostTime(nowHostTime: UInt64, outgoingNow: Double, outgoingTarget: Double, outgoingRate: Double, ticksPerSecond: Double) -> UInt64`
    - That is `now + (target − now) / rate · ticksPerSecond`.
  - `struct PreparedTransition: Sendable`:
    - `let token: UUID`, `track: Track`, `plan: MixPlan`
    - `incomingGrid: MixGrid?`, `outgoingGrid: MixGrid?` (for per-bar rate updates when either side is Drifting)
    - `outgoingOriginalBPM: Double?`
  - On `AudioPlayer`, all on `@MainActor`, each hopping to `audioQueue`:
    - `func prepareTransition(_ t: PreparedTransition, completion: @MainActor @Sendable (Bool) -> Void)`: loads B's file onto the idle deck and reads ReplayGain for that deck. It schedules nothing yet. `false` if the load fails, in which case A plays on and advances normally.
    - `func armTransition(token: UUID)`:
      - schedules B's segment from `plan.incomingStart` with `.dataPlayedBack` completion
      - sets B's rate from the plan, B's fade to 0, and B's cut from `BlendCurve.lowCut`
      - calls `player.play(at: AVAudioTime(hostTime: DeckSync.startHostTime(…)))`
      - starts the 10 ms ticker
    - `func cancelTransition()`: stops the idle deck, resets it, stops the ticker, and restores the live deck's fade to 1 with no cut.
    - `func completeTransitionNow() -> Bool`: during a blend, B goes to full gain, A stops, the transport switches if it hasn't yet, and the result is `true`. Otherwise `false`.
    - `func setLiveRate(_ rate: Double)`: used by the glide.
    - `func liveEffectiveState() -> (fileTime: Double, rate: Double)?`
    - `var onAutomixTrackChanged: (@MainActor @Sendable (Track) -> Void)?`: fires once, at `BlendCurve.isPastSwitch`.
    - `var onTransitionCancelled: (@MainActor @Sendable () -> Void)?`: fires when a seek, a load or a failed prepare drops a prepared or armed transition, so the coordinator re-plans.
    - `var isBlending: Bool` (published).
  - Ticker (`DispatchSourceTimer`, 10 ms, target `audioQueue`). It reads A's file time from A's `playerTime.sampleTime` and the segment start, then:
    - sets the fades from `gains(progress)` and the cuts from `lowCut`
    - for a Drifting grid, sets B's rate at each new A bar from the local BPMs
    - at the switch, makes B live: `currentTrack`, `duration`, `currentTime`, Now Playing and `onAutomixTrackChanged`, all exactly once
    - at progress 1, stops A, resets its deck and stops the ticker.
  - Completion routing:
    - The outgoing deck's completion never calls `onTrackFinished` while a transition is prepared, armed or blending.
    - The incoming deck's completion, once it is live, behaves as the single-deck completion does today. Each deck checks its own `generation`.
  - Transport during a blend:
    - `seek` → `cancelTransition()`, then seek the live deck.
    - `pause` pauses both players; resume plays both. The ramps freeze because A's sample clock freezes.
    - `loadTrack` → `cancelTransition()`.

- [ ] **Step 1: Write the failing tests**
  - `DeckSyncTests`:
    - `testStartHostTimeAtRateOne`
    - `testStartHostTimeScalesByRate`: at rate 1.05, 10.5 s of file is 10 s of host time.
    - `testTargetInThePastClampsToNow`
  - `AudioPlayerTransitionTests`, using two 30 s fixture tones and a `testing_tick(outgoingFileTime:)` hook that runs one ticker step with an injected A time:
    - `testPrepareLoadsIdleDeckWithoutPlaying`
    - `testArmedBlendRampsEqualPower`: ticks at 0, ¼, ½, ¾ and 1 of `length` match `cos`/`sin` within 0.001.
    - `testTransportSwitchesOnceAtSwitchTime`: `onAutomixTrackChanged` is called exactly once, and `currentTrack` is B after it.
    - `testOutgoingCompletionDoesNotCallOnTrackFinished`
    - `testBassSwapCutMovesFromIncomingToOutgoing`
    - `testSeekMidBlendAbortsAndRestoresLiveDeck`; `testPauseMidBlendThenSeekAborts` (Review Focus 3)
    - `testCompleteTransitionNowGivesIncomingFullGain`
    - `testPrepareFailureLeavesOutgoingPlaying`
    - `testReplayGainArrivingMidBlendKeepsFadeEnvelope` (Review Focus 2): B's `playerVolume` changes and its `fade` is unchanged.
    - `testLoadTrackCancelsArmedTransition`
- [ ] **Step 2: Run** `-only-testing:AmpXTests/DeckSyncTests -only-testing:AmpXTests/AudioPlayerTransitionTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the step 2 suites plus `AudioPlayerTests`, `PlaybackIntegrationTests` and `AudioPlayerDeckTests`. Expected: all `TEST SUCCEEDED`.
- [ ] **Step 5: Commit** `feat(audio): beat-aligned two-deck transitions`.

### Task 9: Playlist support

**Files:**
- Modify: `Sources/PlaylistManager.swift`, `Sources/Modules/Playlist/PlaylistRowsView.swift`, `Sources/Modules/Playlist/PlaylistRowLayout.swift`
- Test: `Tests/AmpXTests/PlaylistAutomixTests.swift`, `Tests/AmpXTests/PlaylistRowLayoutTests.swift` (one test added)

**Interfaces:**
- Produces, on `PlaylistManager`:
  - `func nextTrackIndex() -> Int?`: the index `advanceAfterTrackFinished` would play, without changing state. It follows the shuffle order; with Repeat on it wraps; with Repeat off it is nil after the last track.
  - `@Published private(set) var autoTrackIDs: Set<UUID>`
  - `func appendAutoTrack(_ track: Track)`
  - `private(set) var removedAutoURLs: Set<URL>`: recorded by every removal path (`removeTrack`, `removeTracks`, `cropToTracks`, `clearPlaylist`).
  - `func advanceToIncoming(index: Int)`: sets `currentIndex`, and `shuffleCurrentIndex` when shuffling, and persists. It does **not** call `loadTrack`.
  - `var nextInterceptor: (@MainActor () -> Bool)?`: `next()` calls it first and returns if it returns `true`.
  - `var playlistChanged: AnyPublisher<Void, Never>`: emits on any change to `tracks`, `currentIndex`, `shuffleEnabled` or `repeatEnabled`.
- `PlaylistRowsView` items gain `isAuto`. `PlaylistRowLayout.autoTagRect(in row: CGRect) -> CGRect` sits left of the duration. `AUTO` is drawn in `skin.green` at the row font.

- [ ] **Step 1: Write the failing tests** (with `MockAudioPlayer`):
  - `testNextTrackIndexSequential`; `testNextTrackIndexNilAtEndWithoutRepeat`; `testNextTrackIndexWrapsWithRepeat`
  - `testNextTrackIndexFollowsShuffleOrderWithoutMutating`: use `test_setShuffledIndices`.
  - `testAppendAutoTrackMarksIt`
  - `testRemovingAutoTrackRecordsURL`: test every removal path.
  - `testAdvanceToIncomingDoesNotLoad`: `loadTrackCalls` doesn't change.
  - `testNextInterceptorShortCircuits`
  - `testAutoTagRectSitsLeftOfDuration`
- [ ] **Step 2: Run** `-only-testing:AmpXTests/PlaylistAutomixTests -only-testing:AmpXTests/PlaylistRowLayoutTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** `nextTrackIndex` and `advanceSequential`/`advanceShuffle` share one pure helper, so the two cannot disagree.
- [ ] **Step 4: Run** the step 2 suites plus `PlaylistManagerTests`. Expected: `TEST SUCCEEDED`.
- [ ] **Step 5: Commit** `feat(playlist): next-track query, AUTO picks and Automix hooks`.

### Task 10: Automix coordinator

**Files:**
- Create: `Sources/DJ/AutomixCoordinator.swift`
- Modify: `Sources/AmpXApplicationController.swift` (create it and wire it), `Sources/AudioPlaybackControlling.swift` (an `AutomixDeckControlling` protocol for the Task 8 surface)
- Test: `Tests/AmpXTests/AutomixCoordinatorTests.swift`, with `Tests/AmpXTests/MockAutomixDeck.swift`

**Interfaces:**
- Consumes:
  - Task 1: `AutomixSettingsStore`
  - Task 5: `AutomixLibrary`
  - Task 8: `AutomixDeckControlling`, which mirrors `prepareTransition`, `armTransition`, `cancelTransition`, `completeTransitionNow`, `setLiveRate`, `liveEffectiveState`, `onAutomixTrackChanged`, `currentTrack`, `duration` and `isPlaying`
  - Task 9: `PlaylistManager` hooks
  - Tasks 3–4: `MixPoints.plan`, `TempoPlan.glideStep`; existing `MixesWell.nextPick`
- Produces: `@MainActor final class AutomixCoordinator: ObservableObject`
  - `init(settings: AutomixSettingsStore, playlist: PlaylistManager, deck: AutomixDeckControlling, library: @escaping () -> AutomixLibrary?, clock: AutomixClock = .live)`
    - `AutomixClock` wraps a 250 ms repeating MainActor timer, injectable for tests.
  - `@Published private(set) var effectiveTempo: Double?`: the live deck's local BPM × rate; nil when unknown.
  - `private(set) var playedRowIDs: Set<UUID>`: reset when Automix is turned on.
  - Behaviour on each clock tick while `settings.enabled` and playing:
    1. **What plays next:** `playlist.nextTrackIndex()`.
       - If it is nil, Repeat is off, continuation is on, and the live track just started (the first tick after a track change): ask `library.pool(settings.pickFrom, filter: settings.pickFilter)` and run `MixesWell.nextPick` with the reference = the live row, `tempo: effectiveTempo`, and exclusions = `playedRowIDs` ∪ the rows of `removedAutoURLs`. Then call `playlist.appendAutoTrack(row.makeTrack())`.
       - No pick → no transition; playback stops after the current track as today.
    2. **Plan:** `MixPoints.plan` (A and B via `library.track(url:duration:)`).
       - At `outgoingStart − 10 s`, call `prepareTransition`. Before that, re-plan on every tick and on every `playlistChanged`.
       - Between prepare and `outgoingStart − 5 s`, a different next track or a changed plan means `cancelTransition()` and prepare again.
       - At `outgoingStart − 1 s`, call `armTransition`. After that the plan stands.
    3. **Glide**, when `glideBack` is on and no transition is prepared: on each new bar of the live deck, `setLiveRate(newBPM / localBPM)` with `TempoPlan.glideStep`. `nextBPM` is the next track's BPM, else nil.
    4. **Advance:** `onAutomixTrackChanged` → `playlist.advanceToIncoming(index:)`, then insert into `playedRowIDs`.
    5. **Seek:** `onTransitionCancelled` → forget the prepared plan and re-plan on the next tick. A seek past the mix-out gets Task 3's crossfade at the content end.
  - `playlist.nextInterceptor = { deck.completeTransitionNow() }`.
  - Turning Automix off cancels a prepared or armed (not yet blending) transition; a running blend finishes.

- [ ] **Step 1: Write the failing tests** (mock deck and library; manual clock):
  - `testPreparesTenSecondsBeforeMixOutAndArmsAtOne`
  - `testPlaylistChangeBeforeFreezeReprepares` (Review Focus 1); `testPlaylistChangeAfterFreezeKeepsPlan`
  - `testRemovedNextTrackCancelsPreparedTransition` (Review Focus 1)
  - `testContinuationAppendsAutoPickWhenLastTrackStarts`
  - `testContinuationOffOrRepeatOnNeverPicks`
  - `testContinuationExcludesPlayedAndRemovedAuto`
  - `testContinuationUsesEffectiveTempo`: live rate 1.04 at 125 BPM picks a track near 130.
  - `testEmptyPoolStopsAfterCurrentTrack`
  - `testNonLibraryNextTrackGetsCrossfadePlan` (Review Focus 4)
  - `testGlideOnlyOnBarBoundariesAndNotWhilePrepared`
  - `testTrackChangeAdvancesPlaylistWithoutLoad`
  - `testTurningOffCancelsArmedButNotBlending`
  - `testNextDuringBlendCompletesInsteadOfSkipping`
  - `testSeekCancellationReplansFromNewPosition`
- [ ] **Step 2: Run** `-only-testing:AmpXTests/AutomixCoordinatorTests`. Expected: FAIL.
- [ ] **Step 3: Implement the coordinator** and wire it in `AmpXApplicationController`. The library closure returns `LibraryEngineAutomixLibrary` over `libraryController.engine` when one is open, else nil, in which case every track is `.unknown` and every transition is a plain crossfade.
- [ ] **Step 4: Run again,** plus `PlaylistAutomixTests`. Expected: `TEST SUCCEEDED`.
- [ ] **Step 5: Commit** `feat(dj): Automix coordinator`.

### Task 11: Menus, MIXES WELL tempo and the pick filter

**Files:**
- Modify:
  - `Sources/Utilities/AmpXMenuCatalog.swift`, `Sources/Utilities/AmpXMenuBuilder.swift`
  - `Sources/AmpXApplicationController.swift` (actions and `validateMenuItem`)
  - `Sources/Modules/Library/LibraryModuleContent.swift`, `Sources/Modules/Library/LibraryMixesSidebarView.swift`
- Test: the menu catalog/builder tests (find them with `grep -l AmpXMenuCatalog Tests/AmpXTests`), `Tests/AmpXTests/LibraryModuleContentTests.swift`

**Interfaces:**
- Produces:
  - `AmpXMenuCatalog.PlaybackItem.automix = "Automix"`, `.automixOptions = "Automix Options"`.
  - `AmpXMenuCatalog.AutomixOption` copy:
    - groups: `Mix Points`, `Transition`, `Blend (Last Phrase)`, `Longest Blend (Intro / Outro)`, `Glide Back to Original Tempo`, `Glide Speed`, `Continue with MIXES WELL When the Playlist Ends`, `Pick From`
    - values: `Last Phrase`, `Intro / Outro`, `Crossfade`, `Bass Swap`, `8 Bars`…`64 Bars`, `0.05 BPM per 4 Bars`…, `Whole Library`, `Current View`
  - Playback menu: a separator after Repeat, then the `Automix` toggle and the `Automix Options` submenu: radio groups with section headers, plus the two toggles. `validateMenuItem` sets each state from `AutomixSettingsStore`.
  - Library window:
    - Every filter change writes `settings.pickFilter`. This is the persisted copy; the window itself still opens unfiltered.
    - With PLAYING as the reference and Automix on, `MixesWell.matches` uses `coordinator.effectiveTempo`, and the reference card shows `@ 126.4 BPM`.
    - `LibraryMixesSidebarView.updateReference(_ row: LibraryRow?, tempo: Double?)`.

- [ ] **Step 1: Write the failing tests**
  - `testPlaybackMenuHasAutomixToggleAndOptions`
  - `testAutomixOptionsGroupsAndDefaultsChecked`: the spec's defaults are checked.
  - `testChoosingOptionPersists`
  - `testFilterChangeWritesPickFilter`
  - `testPlayingReferenceUsesEffectiveTempoWhenAutomixOn`
  - `testReferenceCardShowsTempo`
- [ ] **Step 2: Run the menu suite plus** `-only-testing:AmpXTests/LibraryModuleContentTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run again.** Expected: `TEST SUCCEEDED`.
- [ ] **Step 5: Commit** `feat(dj): Automix menus and live tempo in MIXES WELL`.

### Task 12: Listening check, spec status, PR

**Files:**
- Modify: `docs/superpowers/specs/2026-09-11-dj-mode-design.md` (Status line only, plus any ruling that changed the design)

- [ ] **Step 1:** Run every suite this plan touched in one `xcodebuild` call. Expected: `TEST SUCCEEDED`.
- [ ] **Step 2: Listening check, by the user.** The implementer prepares and hands over the steps; it does not launch the app against the real library.
  - Back up `~/Library/Containers/com.ampx.macos/Data/Library/Application Support/AmpX/Library`.
  - `./build.sh --run`; Playback ▸ Automix on.
  - Playlist of 6 steady house/techno tracks within ±6%, Intro / Outro, then repeat with Bass Swap and with Last Phrase. Check:
    - beats stay aligned through each blend
    - B's main part arrives as A ends
    - no level jump
    - the seek bar, time display, Now Playing and the spectrum switch once per blend
  - Glide on: the tempo drifts back with no audible step.
  - Playlist end with continuation on: an `AUTO` pick appears; remove it, and a different pick replaces it.
  - Next mid-blend: completes at once. Previous mid-blend: plays the previous track at its original tempo.
  - A set, a variable-tempo track, a track dropped from Finder (not in the library) and a half-tempo DnB track next: crossfades or a chapter change as the spec says.
- [ ] **Step 3:** Set the spec's Status to "Delivery 2 implemented on `feature/dj-mode-automix`". Commit `docs(dj-mode): Automix implemented`.
- [ ] **Step 4:** Finish with superpowers:finishing-a-development-branch.

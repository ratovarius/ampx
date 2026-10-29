# DJ Mode Delivery 1 (Library Data) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the data half of DJ mode: `LibrarySchemaV3`, cue import, track classes, MIXES WELL suggestions, rekordbox phrase import with its access grant, and opt-in writing of rekordbox data into standard file tags.

**Architecture:** Pure value logic (`TrackClass`, `MixesWell`, `RekordboxAnalysisFile`, `TagWritePlanner`) sits apart from I/O. The phrase import and tag writing are new actors owned by `LibraryEngine`. Each runs its work as an exclusive job in the scanner's FIFO (`LibraryScanner.performExclusive`), as `RekordboxSync` already does. TagLib, vendored as source, does the tag I/O behind an Objective-C++ bridge and a small Swift wrapper.

**Tech Stack:** Swift 6 (strict concurrency `complete`), macOS 26, SwiftData, AppKit custom drawing, XCTest, TagLib 2.x (C++), Objective-C++ bridge.

**Spec:** `docs/superpowers/specs/2026-09-11-dj-mode-design.md` (Revision 2), § Data model, § Track classes, § Delivery 1. It builds on `docs/superpowers/specs/2026-09-28-rekordbox-sync-design.md`.

## Global Constraints

- Branch: `feature/dj-mode-library-data` from `docs/dj-mode-rev2`. `feature/*` → `develop`.
- Never add `Co-Authored-By:` to commits. Never run `swiftformat` by hand; the PostToolUse hook formats edited Swift.
- Local tests: only the suites you touched, via `xcodebuild test -project AmpX.xcodeproj -scheme AmpX -destination "platform=macOS,arch=$(uname -m)" -only-testing:AmpXTests/<Suite> 2>&1 | grep -E 'error: |failed \(|TEST (SUCCEEDED|FAILED)'`. Run `./scripts/generate-fixtures.sh` once first, and again after Task 9 changes the generator. CI runs the full suite.
- `docs/superpowers` matches a gitignore rule: add new files under it with `git add -f`.
- Failures reach the console only (`Logger(subsystem: "com.ampx.macos", category: …)`). Categories: `RekordboxPhrases`, `TagWriter`. No alerts, except the tag summary the user asked for and the existing `showError` for a wrong folder.
- Nothing rekordbox-related appears in the UI for a library with no shown rekordbox source (sync spec rule).
- Tag fields written: BPM, key, label, remixer, composer and grouping only. Never rating, beatgrid, cues, play count or mix.
- BPM is written as a rounded integer string. The key is written exactly as rekordbox spells it (`Am`, `F#m`, `Dbm`).
- Thresholds, exactly: tempo window ±6%; Steady ≤ 0.5%; Drifting ≤ 8%; Set = genre `Sets & Mixes` (case-insensitive) or duration > 1800 s; half/double guard within 1%; read-back duration tolerance 10 ms.
- MIXES WELL tag strings, exactly: `SAME KEY`, `+1`, `−1` (U+2212), `REL`, `+n%` / `−n%` / `±0%`, `½×`, `2×`, `VAR`. Group header: `CHANGE CHAPTER`.

## Review Focus

1. **A file changes between the tag summary and Write Tags** (a rekordbox re-export, or a tag edit in another app): the write decision is recomputed from the file at write time, never from the summary. Test in Task 11.
2. **A root unmounts, or the engine stops, during a tag write:** the original stays byte-identical and no `.ampx-tagwrite` temp file is left behind. Test in Task 11.
3. **ANLZ paths with NFD accents or a `#`** match their rows exactly as XML locations do. Test in Task 8.
4. **Odd BPM tags** (`12497`, `128.00`, empty, `fast`) never count as half/double. `128.00` equals a rekordbox `128`; the others are overwritten. Test in Task 10.
5. **The playing track is filtered out of the Library view:** MIXES WELL still finds it as the reference and matches against the whole library. Test in Task 5.

---

### Task 1: `LibrarySchemaV3` and the tempo spread

**Files:**
- Create: `Sources/Library/LibrarySchemaV3.swift`
- Modify: `Sources/Library/LibrarySchemaV2.swift` (drop its typealiases; its nested types stay for the V1→V2 stage), `Sources/Library/LibrarySchemaV1.swift:103-122` (plan schemas and stages, `make(url:)` uses V3), `Sources/Library/Rekordbox/RekordboxCollection.swift` (`tempoSpread`)
- Rename: `Tests/AmpXTests/LibraryTestSchemaV3.swift` → `LibraryTestSchemaV4.swift` (type `LibraryTestSchemaV4`, version `4.0.0`, built on V3's models plus one optional field, stage from `LibrarySchemaV3`); update its three call sites
- Test: `Tests/AmpXTests/LibrarySchemaMigrationTests.swift`, `Tests/AmpXTests/RekordboxCollectionParserTests.swift`

**Interfaces:**
- Produces: `LibrarySchemaV3` with `LibraryRoot`, `LibraryTrack`, `RekordboxSource`. Typealiases `LibraryRoot`, `LibraryTrack` and `RekordboxSource` now point at V3. `LibraryTrack` gains `cues: Data?`, `tempoSpread: Double?`, `phrases: Data?`, `phrasesStamp: Data?`, `mixScan: Data?` and `tagsWrittenHash: Data?`; `init` sets `schemaVersion = 3`.
- Produces: `LibrarySchemaV3.migrateFromV2: MigrationStage`.
- Produces: `RekordboxBeatGrid.tempoSpread(_ grid: [RekordboxBeat]) -> Double?`: nil for an empty grid, otherwise `(max − min) / median × 100` of the BPMs.

- [ ] **Step 1: Write the failing tests**

```swift
func testTempoSpreadIsRangeOverMedianInPercent() {
    let grid = [128.0, 128, 130].map { RekordboxBeat(start: 0, bpm: $0, meter: "4/4", beat: 1) }
    XCTAssertEqual(RekordboxBeatGrid.tempoSpread(grid)!, 2.0 / 128 * 100, accuracy: 1e-9)
    XCTAssertNil(RekordboxBeatGrid.tempoSpread([]))
}

// LibrarySchemaMigrationTests: seed a V2 store (rows with bpm, camelotKey, beatGrid, rating) and reopen
// it with LibraryContainerFactory.make(url:).
func testV2StoreMigratesToV3KeepingValues() throws {
    // every V2 field equal before and after; schemaVersion == 3; cues, phrases, phrasesStamp, mixScan and tagsWrittenHash nil
}
func testV3MigrationComputesTempoSpreadFromBeatGrid() throws {
    // a row whose packed grid has BPMs [128, 128, 130] → tempoSpread ≈ 1.5625; a row without a grid → nil
}
```

The existing "newer store is refused" and "moves past the newest shipped schema" tests must pass with `LibraryTestSchemaV4`.

- [ ] **Step 2: Run them to make sure they fail**

Run the targeted command for `LibrarySchemaMigrationTests` and `RekordboxCollectionParserTests`. Expected: build errors for `LibrarySchemaV3` and `tempoSpread`.

- [ ] **Step 3: Implement**

- Copy V2's three models into `LibrarySchemaV3` and add the six fields.
- `migrateFromV2` is a `.custom` stage. Its `didMigrate` sets `schemaVersion = 3` and fills `tempoSpread` from `beatGrid` via `RekordboxBeatGrid.unpack` and `tempoSpread`.
- `LibraryMigrationPlan.schemas = [V1, V2, V3]` and `stages = [V2.migrateFromV1, V3.migrateFromV2]`.

- [ ] **Step 4: Run the tests and make sure they pass**

Run the same suites plus `LibraryModuleContentTests` and `LibraryControllerTests`, which use the test schema. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit** `feat(library): LibrarySchemaV3 with DJ mode fields and tempo spread`

---

### Task 2: Import cues and store the tempo spread on sync

**Files:**
- Modify: `Sources/Library/Rekordbox/RekordboxCollection.swift` (`RekordboxCue`, `RekordboxCues`, `RekordboxTrack.cues`), `RekordboxCollectionParser.swift` (`POSITION_MARK`), `RekordboxImportPlanner.swift` (snapshot and values carry `cues`), `Sources/Library/LibraryStore+Rekordbox.swift` (snapshot and `apply`)
- Modify fixture: `Tests/AmpXTests/Fixtures/rekordbox-collection.xml`. Add to the first `TRACK` `<POSITION_MARK Name="" Type="0" Start="0.165" Num="0"/>`. Add to the second `<POSITION_MARK Name="Drop" Type="0" Start="64.2" Num="-1"/>` and `<POSITION_MARK Name="Loop" Type="4" Start="96.0" End="99.75" Num="1"/>`.
- Test: `RekordboxCollectionParserTests`, `RekordboxImportPlannerTests`, `LibraryStoreRekordboxTests`

**Interfaces:**
- Consumes: Task 1's `LibraryTrack.cues` and `tempoSpread`, and `RekordboxBeatGrid.tempoSpread`.
- Produces: `struct RekordboxCue: Equatable, Sendable { let number: Int; let type: Int; let start: Double; let end: Double?; let name: String }`. `number` is −1 for a memory cue and 0–7 for a hot cue; `type` is 0 for a cue and 4 for a loop.
- Produces: `enum RekordboxCues { static func pack(_ cues: [RekordboxCue]) -> Data; static func unpack(_ data: Data) -> [RekordboxCue]? }`. Layout: version byte `1`, then per cue Int8 number, UInt8 type, Float64 LE start, UInt8 has-end flag, Float64 LE end (0 when absent), UInt8 name length and up to 255 UTF-8 bytes.
- Produces: `RekordboxTrack.cues: [RekordboxCue]`, `RekordboxRowSnapshot.cues: Data?`, `RekordboxRowValues.cues: Data?`.

- [ ] **Step 1: Write the failing tests**

```swift
func testParsesPositionMarks() throws {
    let tracks = try RekordboxCollectionParser.parse(fixtureData).tracks
    XCTAssertEqual(tracks[0].cues, [RekordboxCue(number: 0, type: 0, start: 0.165, end: nil, name: "")])
    XCTAssertEqual(tracks[1].cues, [
        RekordboxCue(number: -1, type: 0, start: 64.2, end: nil, name: "Drop"),
        RekordboxCue(number: 1, type: 4, start: 96.0, end: 99.75, name: "Loop"),
    ])
    XCTAssertEqual(tracks[2].cues, [])
}
func testCuesRoundTrip() { /* pack → unpack returns the same array; a wrong version byte → nil */ }
// Planner: a matched track with cues writes RekordboxCues.pack(cues); a re-run writes nothing; a track without cues writes nil.
// Store: applyRekordbox sets row.cues, and row.tempoSpread from the written grid (nil when the grid is nil).
```

- [ ] **Step 2: Run to make sure they fail** (the three suites; expected: compile errors for `cues`)
- [ ] **Step 3: Implement.** In the parser, `(4, "POSITION_MARK") where current != nil` appends when `Start` parses. `Num` defaults to −1, `Type` to 0, `Name` to `""`, and `End` is optional. The planner's target sets `values.cues = track.cues.isEmpty ? nil : RekordboxCues.pack(track.cues)`. `LibraryStore.apply` also writes `row.tempoSpread`.
- [ ] **Step 4: Run to make sure they pass**
- [ ] **Step 5: Commit** `feat(rekordbox): import cue points and store the tempo spread`

---

### Task 3: Track classes and the new row fields

**Files:**
- Create: `Sources/DJ/TrackClass.swift`
- Modify: `Sources/Library/LibraryValues.swift` (`LibraryRow`), `Sources/Library/LibraryIndex.swift:240-270`
- Test: create `Tests/AmpXTests/TrackClassTests.swift`; add cases to `LibraryQueryTests`, which build rows through the index

**Interfaces:**
- Consumes: Task 1's fields.
- Produces: `LibraryRow` gains `var tempoSpread: Double? = nil` and `var hasPhrases = false`, both defaulted so existing memberwise call sites compile. It also gains computed `var trackClass: TrackClass` and `var isSet: Bool`.
- Produces: `enum TrackClass: Equatable, Sendable { case set, steady, drifting, changing, noGrid; static func classify(genre: String?, duration: Double, tempoSpread: Double?) -> TrackClass }`. Set wins first, then `noGrid` when `tempoSpread == nil`, then ≤ 0.5 steady, ≤ 8 drifting, otherwise changing.

- [ ] **Step 1: Write the failing tests**

```swift
func testClassBoundaries() {
    XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 400, tempoSpread: 0.5), .steady)
    XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 400, tempoSpread: 0.51), .drifting)
    XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 400, tempoSpread: 8), .drifting)
    XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 400, tempoSpread: 8.01), .changing)
    XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 400, tempoSpread: nil), .noGrid)
}
func testSetRule() {
    XCTAssertEqual(TrackClass.classify(genre: "sets & mixes", duration: 225, tempoSpread: 0), .set)
    XCTAssertEqual(TrackClass.classify(genre: nil, duration: 1800.5, tempoSpread: 0), .set)
    XCTAssertEqual(TrackClass.classify(genre: "Techno", duration: 1710, tempoSpread: 0), .steady) // the 28½-min track
}
// LibraryQueryTests: a seeded row with tempoSpread 1.2 and phrases data → LibraryRow.tempoSpread == 1.2, hasPhrases == true.
```

- [ ] **Step 2: Run to make sure they fail**
- [ ] **Step 3: Implement** the enum, the row fields, and `LibraryIndex.row` filling `tempoSpread` and `hasPhrases: track.phrases != nil`.
- [ ] **Step 4: Run to make sure they pass** (`TrackClassTests`, `LibraryQueryTests`, `LibraryIndex`-backed suites)
- [ ] **Step 5: Commit** `feat(dj): classify tracks as set, steady, drifting, changing or no grid`

---

### Task 4: MIXES WELL matching and the continuation pick

**Files:**
- Create: `Sources/DJ/MixesWell.swift`
- Test: create `Tests/AmpXTests/MixesWellTests.swift`

**Interfaces:**
- Consumes: `LibraryRow.camelotKey`, `bpm`, `isAvailable`, `trackClass`.
- Produces:

```swift
enum KeyRelation: Equatable, Sendable { case same, plusOne, minusOne, relative }
enum TempoOctave: Equatable, Sendable { case normal, half, double }   // half: the candidate runs at half the reference tempo
struct MixesWellMatch: Equatable, Sendable {
    let row: LibraryRow
    let key: KeyRelation
    let octave: TempoOctave
    let bpmDeltaPercent: Double    // candidate BPM (×2 for half, ÷2 for double) against the reference tempo
    var tags: [String] { get }     // key tag, then tempo tag, then "½×"/"2×" when not normal, then "VAR" for .changing
}
struct MixesWellResult: Equatable, Sendable { let matches: [MixesWellMatch]; let chapter: [MixesWellMatch] }
enum MixesWell {
    static let tempoWindow = 0.06
    static func keyRelation(_ reference: String, _ candidate: String) -> KeyRelation?
    static func matches(reference: LibraryRow, tempo: Double, rows: [LibraryRow]) -> MixesWellResult
    static func nextPick(reference: LibraryRow, tempo: Double, pool: [LibraryRow], excluded: Set<UUID>) -> LibraryRow?
}
```

- **Key relation** works on Camelot codes. The same code is `same`. The same letter with the number +1 or −1 (12 wraps to 1) is `plusOne` or `minusOne`. The same number with the other letter is `relative`. Anything else is nil.
- **Excluded from `matches`:** the reference itself, unavailable rows, sets, and rows without a BPM or Camelot key.
- **Ranking:** same, then ±1 (tied), then relative. Then the smaller absolute delta, then title.
- **Tempo tag:** the rounded delta as `+2%`, `−3%`, or `±0%`.
- **`nextPick`:** the first `matches` entry that is not excluded and whose class is steady or drifting. Failing that, the pool row with the closest BPM to `tempo` (normal octave only, same exclusions, ignoring key). Failing that, nil.

- [ ] **Step 1: Write the failing tests**

```swift
func testKeyRelations() {
    XCTAssertEqual(MixesWell.keyRelation("8A", "8A"), .same)
    XCTAssertEqual(MixesWell.keyRelation("8A", "9A"), .plusOne)
    XCTAssertEqual(MixesWell.keyRelation("1A", "12A"), .minusOne)
    XCTAssertEqual(MixesWell.keyRelation("8A", "8B"), .relative)
    XCTAssertNil(MixesWell.keyRelation("8A", "10A"))
}
func testWindowAndRanking() {
    // reference 128 8A; candidates: 128 9A, 130 8A, 136 8A (6.25%: out), 120.4 8B (−5.9%: in)
    // → matches order: [130 8A (SAME KEY, +2%), 128 9A (+1, ±0%), 120.4 8B (REL, −6%)]
}
func testHalfAndDoubleGoToChapter() {
    // reference 140 8A; candidates 70 8A → chapter, tags ["SAME KEY", "±0%", "½×"]; 280 8A → chapter "2×"; none in matches
}
func testExclusions() { /* a set, an unavailable row, a row with no key, and the reference itself never appear */ }
func testChangingTrackListedWithVarTag() { /* tempoSpread 12 → in matches, tags end with "VAR" */ }
func testNextPickSkipsChapterChangingAndExcluded() { /* the top match excluded → the second; a .changing top → skipped */ }
func testNextPickFallsBackToClosestTempoIgnoringKey() { /* no key match; pool 126 3B and 140 3B with tempo 128 → 126 */ }
func testNextPickEmptyPool() { /* every pool row excluded → nil */ }
```

- [ ] **Step 2: Run to make sure they fail**
- [ ] **Step 3: Implement** `MixesWell` per the rules above.
- [ ] **Step 4: Run to make sure they pass**
- [ ] **Step 5: Commit** `feat(dj): MIXES WELL matching, chapter changes and continuation pick`

---

### Task 5: MIXES WELL sidebar list

**Files:**
- Modify: `Sources/Modules/Library/LibraryMixesSidebarView.swift`, `Sources/Modules/Library/LibraryModuleContent.swift:250-257` (reference and matches), `Sources/Library/LibraryBrowserModel.swift` (`allRows`, `append`)
- Test: create `Tests/AmpXTests/LibraryMixesSidebarViewTests.swift`; add cases to `LibraryModuleContentTests` and `LibraryBrowserModelTests`

**Interfaces:**
- Consumes: Task 4's `MixesWell.matches` and `MixesWellResult`.
- Produces: `LibraryBrowserModel.allRows() async -> [LibraryRow]`, which is `services.query(LibraryQuery(), 0)` rows (empty on error). Also `LibraryBrowserModel.append(_ rows: [LibraryRow]) async`, the availability-check, bookmark and `addTracks` path that `enqueue` now calls too.
- Produces: `LibraryMixesSidebarView.updateMatches(_ result: MixesWellResult?)`, `selectedMatchID: UUID?`, and `onQueue: ((LibraryRow) -> Void)?`.

Behaviour:
- **Placeholder:** `No track` without a reference. `This track has no BPM or key.` when the reference lacks either. `No matches.` when both groups are empty. The old DJ-mode placeholder goes.
- **List:** below the card. Each row is 34 pt: line 1 is `artist – title`, fitted; line 2 is the tags joined by two spaces, in `skin.textDim`. When `chapter` is non-empty, a `CHANGE CHAPTER` header of 22 pt precedes its rows. It scrolls with `AmpXScrollbar` when it overflows.
- **Actions:** click selects. Double-click, or + QUEUE with a selection, calls `onQueue`. + QUEUE is enabled only with a selection.
- **Content:** the reference row and the candidates both come from `model.allRows()`, not `table.rows`. Matches are recomputed when the reference changes or the model's rows publish, with the reference row's `bpm` as `tempo`. Delivery 3 passes the effective tempo. `onQueue` calls `model.append([row])`.

- [ ] **Step 1: Write the failing tests**

```swift
func testListsMatchesThenChapterHeader() { /* updateMatches with 2 matches + 1 chapter → drawn row order and header present (accessibility children labels) */ }
func testPlaceholders() { /* nil reference → "No track"; reference without key → "This track has no BPM or key."; empty → "No matches." */ }
func testQueueButtonEnabledOnlyWithSelection() { /* select a match → isEnabled; + QUEUE → onQueue(row) */ }
// LibraryModuleContentTests:
func testPlayingTrackOutsideFilterStillDrivesMatches() {
    // filter the table to genre "House"; the playing track is Techno 128 8A; a library row Techno 129 8A
    // → sidebar shows it as a match (Review Focus 5)
}
// LibraryBrowserModelTests:
func testAppendSkipsUnavailableRowsAndSavesRootBookmark() { /* same contract as enqueue(append: true) */ }
```

- [ ] **Step 2: Run to make sure they fail**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run to make sure they pass**, plus `./scripts/shoot.sh --no-build` after `./build.sh`: open the Library with a playing track and check the list draws within the 260 pt sidebar.
- [ ] **Step 5: Commit** `feat(library): MIXES WELL sidebar lists matches and chapter changes`

---

### Task 6: rekordbox ANLZ decoding

**Files:**
- Create: `Sources/Library/Rekordbox/RekordboxAnalysisFile.swift`
- Test: create `Tests/AmpXTests/RekordboxAnalysisFileTests.swift` and `Tests/AmpXTests/ANLZTestData.swift` (a test-only encoder)

**Interfaces:**
- Produces:

```swift
enum RekordboxPhraseKind: UInt8, Sendable { case other = 0, intro = 1, outro = 2 }
struct RekordboxPhrase: Equatable, Sendable { let beat: Int; let kind: RekordboxPhraseKind }
struct RekordboxPhraseAnalysis: Equatable, Sendable { let mood: Int; let endBeat: Int; let phrases: [RekordboxPhrase] }
enum RekordboxAnalysisFile {
    static func trackPath(dat: Data) -> String?               // PPTH, NFC, trailing NULs stripped
    static func phrases(ext: Data) -> RekordboxPhraseAnalysis? // PSSI
    static func pack(_ analysis: RekordboxPhraseAnalysis) -> Data   // version 1, UInt8 mood, UInt16 LE end beat, per phrase UInt16 LE beat + UInt8 kind
    static func unpack(_ data: Data) -> RekordboxPhraseAnalysis?
}
```

Format (big-endian throughout):
- The file's header length is a UInt32 at bytes 4–7, and the first section starts there.
- Each section is a 4-byte code, a UInt32 header length and a UInt32 total length. The next section starts at offset + total length.
- **`PPTH`:** UInt32 path byte length at section offset 12, then a UTF-16BE path.
- **`PSSI`:** the body starts at section offset 12. Entry count is a UInt16 at body offset 4.
  - **Mask:** if the UInt16 at body offset 6 is above 20, XOR every byte from body offset 6 on with `(key[(i − 6) % 19] + count) & 0xFF`, where `key = CB E1 EE FA E5 EE AD EE E9 D2 E9 EB E1 E9 F3 E8 E9 F4 E1`.
  - **After unmasking:** mood is at body offset 6 and the end beat at 14. Entries start at 20, 24 bytes each: index, beat and kind, as UInt16s at +0, +2 and +4.
  - **Kinds:** mood 1 maps 1 → intro and 6 → outro. Moods 2 and 3 map 1 → intro and 10 → outro. Everything else is other.
- **Rejected (nil):** a mood outside 1…3, zero entries, entries running past the section, or no PSSI section.

- [ ] **Step 1: Write the failing tests**

```swift
func testHighMoodUnmasked() {
    let ext = ANLZTestData.ext(mood: 1, endBeat: 836, entries: [(1, 1), (65, 2), (785, 6)], masked: false)
    XCTAssertEqual(RekordboxAnalysisFile.phrases(ext: ext),
                   RekordboxPhraseAnalysis(mood: 1, endBeat: 836, phrases: [.init(beat: 1, kind: .intro), .init(beat: 65, kind: .other), .init(beat: 785, kind: .outro)]))
}
func testMaskedEqualsUnmasked() { /* same input with masked: true decodes identically, for moods 1, 2 and 3 */ }
func testMidAndLowMoodOutroIsKindTen() { /* mood 2 and 3, kind 10 → .outro; kind 6 → .other */ }
func testRejectsCorruptSections() { /* count past the end → nil; mood 7 → nil; no PSSI → nil */ }
func testTrackPathIsNFC() { /* dat(path: NFD "/Users/x/Música/Ré.mp3") → NFC string; dat with "#" kept */ }
func testPackRoundTrip() { /* pack → unpack equal; wrong version byte → nil */ }
```

`ANLZTestData` writes a `PMAI` header (header length 28) and one section, and applies the mask exactly as described when `masked` is true.

- [ ] **Step 2: Run to make sure they fail**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run to make sure they pass**
- [ ] **Step 5: Commit** `feat(rekordbox): decode track paths and phrases from ANLZ files`

---

### Task 7: Access to the rekordbox analysis folder

**Files:**
- Create: `Sources/Library/Rekordbox/RekordboxAnalysisAccess.swift`
- Modify: `Sources/Modules/Library/LibraryModuleContent.swift` (`LibraryPanelPresenting.chooseFolder(title:directory:)` and its AppKit implementation; the menu action), `Sources/Modules/Library/LibraryRootsMenu.swift` (the rekordbox section)
- Test: create `Tests/AmpXTests/RekordboxAnalysisAccessTests.swift`; add cases to `LibraryRootsMenuTests` and `LibraryModuleContentTests` (the panel fake gains the new method)

**Interfaces:**
- Produces:

```swift
final class RekordboxAnalysisAccess: @unchecked Sendable {   // all state in UserDefaults; key "AmpX.rekordboxAnalysisBookmark"
    init(defaults: UserDefaults)
    var isGranted: Bool { get }
    static var suggestedFolder: URL { get }    // real home from getpwuid(getuid()) + "/Library/Pioneer/rekordbox"; the sandbox's home is the container
    static func analysisFolder(in folder: URL) -> URL   // folder/share/PIONEER/USBANLZ
    func grant(_ folder: URL) throws           // throws RekordboxAccessError.notAnAnalysisFolder unless analysisFolder(in:) exists
    func resolve() -> URL?                     // refreshes a stale bookmark; nil and a log line on failure
}
```

- Produces: `LibraryRootsMenu.Actions.allowRekordboxAnalysis: () -> Void`, and a `make(…, rekordboxAnalysisGranted: Bool)` parameter.
- **The rekordbox section** sits after the roots, behind a separator. It appears only when any source `isShown`. Its item is titled `Allow Access to rekordbox Analysis…`, or `Change rekordbox Analysis Folder…` once access is granted.
- **On selection:** the folder panel opens at `suggestedFolder`. A wrong folder triggers `panels.showError("That folder has no rekordbox analysis (share/PIONEER/USBANLZ).")`. Success calls `LibraryModuleContent.onRekordboxAnalysisGranted: (() -> Void)?`, which Task 8 wires to `engine.phraseSync.requestRun()`.

- [ ] **Step 1: Write the failing tests** (grant accepts a temp folder containing `share/PIONEER/USBANLZ` and rejects one without it; `isGranted` survives a new instance on the same defaults; `resolve` returns the folder; the menu section is absent without a shown source, and its title changes once granted)
- [ ] **Step 2: Run to make sure they fail**
- [ ] **Step 3: Implement** with `SecurityScopedBookmark.makeData` and `resolve`.
- [ ] **Step 4: Run to make sure they pass**
- [ ] **Step 5: Commit** `feat(rekordbox): one-time access grant for the analysis folder`

---

### Task 8: Phrase import job

**Files:**
- Create: `Sources/Library/Rekordbox/RekordboxPhraseSync.swift`, `Sources/Library/Rekordbox/RekordboxPathMatcher.swift`
- Modify: `RekordboxImportPlanner.swift` (pass 1 uses `RekordboxPathMatcher`, with no change in behaviour), `LibraryStore+Rekordbox.swift` (`phraseStamps`, `applyRekordboxPhrases`), `RekordboxSync.swift` (an `onImported` hook after a successful apply with `matched > 0`), `Sources/Library/LibraryEngine.swift` (owns, starts and stops `phraseSync`)
- Test: create `Tests/AmpXTests/RekordboxPhraseSyncTests.swift`; `RekordboxImportPlannerTests` must stay green; add an opt-in case to `RekordboxCollectionGateTests`

**Interfaces:**
- Consumes: Task 6's decoder and pack, and Task 7's `RekordboxAnalysisAccess.resolve()`.
- Produces:

```swift
struct RekordboxPathMatcher: Sendable { init(_ snapshot: RekordboxLibrarySnapshot); func rowID(for path: String) -> UUID? }
protocol RekordboxAnalysisSource: Sendable {
    func trackFolders() async throws -> [URL]          // every USBANLZ/*/* folder holding ANLZ0000.DAT
    func read(_ url: URL) async throws -> Data
    func stamp(_ url: URL) async throws -> RekordboxFileStamp
}
struct RekordboxPhraseWrite: Sendable, Equatable { let rowID: UUID; let phrases: Data?; let stamp: Data }   // stamp = JSON of RekordboxFileStamp
extension LibraryStore {
    func phraseStamps() throws -> [UUID: Data]
    func applyRekordboxPhrases(_ writes: [RekordboxPhraseWrite]) throws   // one commit; publishes .rowsChanged per touched root
}
actor RekordboxPhraseSync {
    init(store: LibraryStore, scanner: LibraryScanner, fileSystem: any LibraryFileSystem, source: @escaping @Sendable () -> (any RekordboxAnalysisSource)?)
    func requestRun()       // coalesces; at most one queued run
    func halt() async
    func waitUntilIdle() async
}
```

- **Run (exclusive job):** with no source, nothing happens. Otherwise, for each folder, read the DAT's path and match it to a row. Skip the folder when the EXT stamp equals the stored one. Otherwise read the EXT and decode it.
  - A decode failure writes `phrases: nil` with the new stamp, logged once per stamp at `.info`.
  - Folders whose path matches no row are skipped.
- **The live source** starts and stops the access URL's security scope around each run.
- **Triggers:** engine start (after `rekordbox.start()`), `RekordboxSync`'s `onImported`, and the grant from Task 7.
- **Stop:** `LibraryEngine.stop()` halts `phraseSync` before stopping the scanner, as it does for `rekordbox`.

- [ ] **Step 1: Write the failing tests**

```swift
func testImportsPhrasesForMatchedRows() async throws { /* fake source with 2 folders → both rows get packed phrases and stamps */ }
func testSkipsUnchangedStamp() async throws { /* second run reads no EXT (fake counts reads) */ }
func testDecodeFailureStoresNilWithStamp() async throws {}
func testNoAccessDoesNothing() async throws {}
func testMatchesNFDAndHashPaths() async throws { /* PPTH "/Music/DJ/Ре́mix #1.mp3" in NFD matches the NFC row (Review Focus 3) */ }
func testRequestsCoalesce() async throws { /* 3 requests during a run → exactly one follow-up run */ }
func testRunsAfterRekordboxImport() async throws { /* an applied import triggers one phrase run */ }
// Gate (TEST_RUNNER_AMPX_LIBRARY_GATE=1): with access to ~/Library/Pioneer/rekordbox, ≥ 95% of ~/Music/DJ rows get phrases; print the count.
```

- [ ] **Step 2: Run to make sure they fail**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run to make sure they pass** (`RekordboxPhraseSyncTests`, `RekordboxImportPlannerTests`, `RekordboxSyncTests`, `LibraryEngineTests`)
- [ ] **Step 5: Commit** `feat(rekordbox): import phrase analysis after each sync`

---

### Task 9: Vendor TagLib and the tag I/O bridge

**Files:**
- Create: `Sources/Vendor/TagLib/` holding the latest TagLib **2.x** release: `taglib/` limited to `toolkit`, `mpeg` (with `id3v1` and `id3v2`), `ape`, `riff` (`aiff`, `wav`, `info`), `flac`, `ogg` (`xiph`) and `mp4`, plus `3rdparty/utfcpp/source`. Leave out `fileref.cpp` and every other format.
- Also create: hand-written `taglib_config.h` and `config.h` replacing the CMake-generated ones, `VENDOR.md` (version, source URL, licence: LGPL-2.1 or MPL-1.1, used under MPL-1.1, and the list of excluded parts), and the TagLib licence files.
- Create: `Sources/TagLibBridge/AmpXTagFile.h`, `AmpXTagFile.mm`, `Sources/AmpX-Bridging-Header.h`, `Sources/DJ/TagFileIO.swift`
- Modify: `AmpX.xcodeproj/project.pbxproj` for the app target: `SWIFT_OBJC_BRIDGING_HEADER`, `HEADER_SEARCH_PATHS` (TagLib's include directories), `GCC_PREPROCESSOR_DEFINITIONS += TAGLIB_STATIC`, and `OTHER_LDFLAGS += -lz` with zlib on. Silence TagLib's own warnings for the vendor folder through a synchronized-group build-file exception (`-w`). Exclude `Sources/Vendor` from SwiftLint and SwiftFormat configs if they glob it.
- Modify: `scripts/ampx_fixtures/library.py`. Add `artwork-v24.mp3` (the full tags plus an `APIC` front cover of a 1×1 PNG from pillow) and `artwork.m4a` (the full tags plus `covr`). Record both in the manifest.
- Test: create `Tests/AmpXTests/TagFileIOTests.swift`

**Interfaces:**
- Produces (Objective-C):

```objc
@interface AmpXTagFile : NSObject
+ (nullable NSDictionary<NSString *, NSString *> *)readFieldsAtPath:(NSString *)path error:(NSError **)error;
+ (BOOL)writeFields:(NSDictionary<NSString *, NSString *> *)fields toPath:(NSString *)path error:(NSError **)error;
@end
```

- Produces (Swift, what everything else uses):

```swift
enum TagField: String, CaseIterable, Codable, Sendable { case bpm, key, label, remixer, composer, grouping }
enum TagFileIO {
    static func read(_ url: URL) throws -> [TagField: String]
    static func write(_ fields: [TagField: String], to url: URL) throws   // only the given fields; others untouched
}
```

**Mapping**, chosen by extension (case-insensitive):

| Container | BPM | Key | Label | Remixer | Composer | Grouping |
|---|---|---|---|---|---|---|
| mp3 (`MPEG::File`), wav (`RIFF::WAV::File` ID3v2), aif/aiff (`RIFF::AIFF::File`) | `TBPM` | `TKEY` | `TPUB` | `TPE4` | `TCOM` | `TIT1` |
| flac (`FLAC::File` Xiph comment) | `BPM` | `INITIALKEY` | `LABEL` | `REMIXER` | `COMPOSER` | `GROUPING` |
| m4a (`MP4::File`) | `tmpo` (int) | `----:com.apple.iTunes:initialkey` | `----:com.apple.iTunes:LABEL` | `----:com.apple.iTunes:REMIXER` | `©wrt` | `©grp` |

ID3 frames are replaced: remove the existing frames of that ID, then add one UTF-8 text frame. An ID3v2 file is saved in the major version it already has (v2.3 stays v2.3); a file without a tag gets v2.4. Unsupported extensions throw.

- [ ] **Step 1: Write the failing tests** (each copies a generated fixture into a temp folder)

```swift
func testReadsExistingFields() throws {
    for name in ["tagged-v23.mp3", "tagged-v24.mp3", "tagged.wav", "tagged.aiff", "tagged.flac", "tagged.m4a"] {
        let fields = try TagFileIO.read(copy(name))
        XCTAssertEqual(fields[.bpm], "130", name); XCTAssertEqual(fields[.key], "Am", name)
    }
}
func testWritesAllSixFieldsInEveryContainer() throws {
    let values: [TagField: String] = [.bpm: "128", .key: "F#m", .label: "Drumcode", .remixer: "Adam Beyer", .composer: "A. Beyer", .grouping: "Peak"]
    // for every container: write(values) then read() == values
}
func testWriteKeepsOtherTagsAndArtwork() throws {
    // after writing to artwork-v24.mp3 and artwork.m4a: TrackMetadataLoader still reads title, artist, album, comment from TAGS;
    // the artwork bytes from AVAsset metadata are identical to before
}
func testKeepsID3Version() throws { /* tagged-v23.mp3 → byte 3 of the file is still 3 after a write */ }
func testUnsupportedExtensionThrows() {}
```

- [ ] **Step 2: Run `./scripts/generate-fixtures.sh`, then the test, to make sure it fails** (build error: `TagFileIO` not found)
- [ ] **Step 3: Implement.** Vendor the sources, add the configs and settings, then write the bridge and the wrapper. The app must build with `./build.sh` before the tests run.
- [ ] **Step 4: Run to make sure they pass** (`TagFileIOTests`, plus `LibraryMetadataGateTests` unchanged)
- [ ] **Step 5: Commit** `build: vendor TagLib 2.x` (the vendor folder, configs and project settings), then `feat(dj): read and write standard DJ tags through TagLib` (bridge, wrapper, fixtures and tests)

---

### Task 10: Tag write planning

**Files:**
- Create: `Sources/DJ/TagWritePlanner.swift`
- Test: create `Tests/AmpXTests/TagWritePlannerTests.swift`

**Interfaces:**
- Consumes: Task 9's `TagField`.
- Produces:

```swift
struct TagWriteRow: Sendable, Equatable {
    let rowID: UUID; let rootID: UUID; let url: URL
    let bpm: Double?; let musicalKey, label, remixer, composer, grouping: String?
    let tagsWrittenHash: Data?
}
struct TagWriteDecision: Equatable, Sendable { let changes: [TagField: String]; let halfDouble: Bool }
enum TagWritePlanner {
    static func desired(_ row: TagWriteRow) -> [TagField: String]   // bpm rounded to an Int string; nil fields omitted
    static func hash(_ desired: [TagField: String]) -> Data          // SHA-256 of "field=value\n" lines sorted by field
    static func isDue(_ row: TagWriteRow) -> Bool                     // hash(desired(row)) != row.tagsWrittenHash
    static func decide(_ row: TagWriteRow, file: [TagField: String]) -> TagWriteDecision
}
```

`decide` rules:
- A field changes when the desired value differs from the file's value. BPM compares numerically after rounding, and other fields compare after trimming whitespace.
- **Half/double:** when the file's BPM parses as a number greater than 0 and `file / row.bpm` is within 1% of 0.5 or 2.0, set `halfDouble = true` and leave BPM out of `changes`.
- A field missing from `desired` is never in `changes`, so an empty value never clears a tag.

- [ ] **Step 1: Write the failing tests**

```swift
func testDesiredRoundsBPMAndOmitsNil() { /* bpm 127.6, key "Am", label nil → [.bpm: "128", .key: "Am"] */ }
func testHalfDoubleGuard() {
    // row bpm 174, file "87" → halfDouble, no .bpm change; row 87, file "174" → same; row 128, file "64.5" (0.504 ratio) → halfDouble
    // row 128, file "66" (0.516) → not halfDouble, .bpm "128" changes
}
func testOddBPMTags() {   // Review Focus 4
    // file "12497" → not halfDouble, change to "128"; file "128.00" → no change; file "" or "fast" → change, not halfDouble
}
func testOnlyDifferingFieldsChange() { /* file key "Am" equals desired "Am"; label differs → changes == [.label: …] */ }
func testHashStableAndOrderIndependent() {}
func testIsDue() { /* nil hash → due; hash of the same desired → not due; a changed label → due */ }
```

- [ ] **Step 2: Run to make sure they fail**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run to make sure they pass**
- [ ] **Step 5: Commit** `feat(dj): decide which rekordbox values to write into tags`

---

### Task 11: Tag write service

**Files:**
- Create: `Sources/DJ/TagWriteService.swift`
- Modify: `Sources/Library/LibraryStore+Rekordbox.swift` (`tagWriteRows`, `markTagsWritten`), `Sources/Library/LibraryEngine.swift` (owns `tagWriter`; hooks it to `RekordboxSync.onImported` and to a root becoming available; halts it on stop)
- Test: create `Tests/AmpXTests/TagWriteServiceTests.swift`

**Interfaces:**
- Consumes: Task 9's `TagFileIO`, Task 10's planner, and Task 8's `onImported` hook.
- Produces:

```swift
extension LibraryStore {
    /// Rows with analysisSource == .rekordbox in available roots, not missing; optionally limited to ids.
    func tagWriteRows(rowIDs: Set<UUID>?) throws -> [TagWriteRow]
    func markTagsWritten(_ hashes: [UUID: Data]) throws   // saves; publishes no LibraryChange (nothing displayed changes)
}
struct TagFileAccess: Sendable {
    var read: @Sendable (URL) throws -> [TagField: String]
    var write: @Sendable ([TagField: String], URL) throws -> Void
    var duration: @Sendable (URL) throws -> Double          // AVAudioFile length / sample rate
    var isWritable: @Sendable (URL) -> Bool                 // FileManager.isWritableFile on the file and its folder
    static let live: TagFileAccess
}
struct TagWriteSummary: Equatable, Sendable {
    var filesToUpdate = 0; var perField: [TagField: Int] = [:]
    var skippedReadOnly: [String] = []; var unreadable = 0; var halfDouble: [String] = []
}
struct TagWriteReport: Codable, Equatable, Sendable {
    var written = 0; var skippedReadOnly: [String] = []; var failed: [String] = []; var halfDouble: [String] = []
}
actor TagWriteService {
    init(store: LibraryStore, scanner: LibraryScanner, files: TagFileAccess = .live, defaults: UserDefaults)
    static let enabledKey = "AmpX.keepRekordboxTagsInFiles"
    static let reportKey = "AmpX.lastTagWriteReport"   // JSON of TagWriteReport
    func preview(rowIDs: Set<UUID>?) async -> TagWriteSummary
    func write(rowIDs: Set<UUID>?, onlyDue: Bool) async -> TagWriteReport   // exclusive job; saves the report under reportKey
    func lastReport() -> TagWriteReport?
    func syncFinished() async        // if enabled: write(rowIDs: nil, onlyDue: true)
    func halt() async
}
```

**Per row in `write`:**
1. Skip it when `onlyDue` is set and it isn't due.
2. Read the file's tags now and `decide`. Never reuse the preview's result (Review Focus 1).
3. Nothing to change: store the hash, unless `halfDouble`.
4. Not writable: add to `skippedReadOnly`.
5. **Otherwise:**
   - Copy the file to `<folder>/.<name>.ampx-tagwrite` and write `changes` to the copy.
   - Read the copy back. Every change must be present, and its duration must be within 0.01 s of the original's.
   - Then `FileManager.default.replaceItemAt(original, withItemAt: temp)`.
   - On any failure, delete the temp, add the path to `failed`, and log at `.error`.
6. Store the hash after success, unless `halfDouble`. Half/double rows stay due, so they are listed again on every run until the values agree.
7. Check `Task.isCancelled` and the halt flag between rows. A halt never leaves a temp file.

- [ ] **Step 1: Write the failing tests** (real temp files with a fake `TagFileAccess` that stores fields in a sidecar dictionary, plus one live-I/O case on a copied `tagged-v24.mp3`)

```swift
func testWritesAtomicallyAndStoresHash() async throws {}
func testFailedReadBackLeavesOriginalByteIdenticalAndNoTemp() async throws {}
func testReadOnlyFileIsSkipped() async throws {}
func testHalfDoubleListedEveryRunAndNeverHashed() async throws {}
func testUnchangedFileStoresHashWithoutWriting() async throws {}
func testOnlyDueSkipsRowsWithMatchingHash() async throws {}
func testDecisionUsesFileAtWriteTimeNotPreview() async throws {   // Review Focus 1
    // preview; change the file's key; write → the new key is compared, and the counts reflect the write-time state
}
func testHaltMidRunLeavesNoTempFiles() async throws {}            // Review Focus 2
func testUnavailableRootRowsAreNotCandidates() async throws {}
func testSyncFinishedWritesOnlyWhenEnabled() async throws {}
func testLiveWriteOnRealMP3() async throws { /* TagFileAccess.live; after write, TagFileIO.read shows the new key */ }
```

- [ ] **Step 2: Run to make sure they fail**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run to make sure they pass** (`TagWriteServiceTests`, `LibraryEngineTests`, `RekordboxSyncTests`)
- [ ] **Step 5: Commit** `feat(dj): write rekordbox data into file tags atomically`

---

### Task 12: Tag writing UI

**Files:**
- Create: `Sources/Modules/Library/LibraryTagSummaryView.swift`
- Modify: `Sources/Modules/Library/LibraryRootsMenu.swift` (two items), `Sources/Modules/Library/LibraryModuleContent.swift` (actions and overlay), `Sources/Modules/Library/LibraryRekordboxReportView.swift` (tag sections)
- Modify docs: in the spec header, set **Status** to `Delivery 1 implemented on feature/dj-mode-library-data`
- Test: create `Tests/AmpXTests/LibraryTagSummaryViewTests.swift`; add cases to `LibraryRootsMenuTests`, `LibraryModuleContentTests` and `LibraryChromeTests` (the report view)

**Interfaces:**
- Consumes: Task 11's `TagWriteService`, `TagWriteSummary` and `TagWriteReport`, and Task 7's rekordbox menu section.
- Produces: `LibraryRootsMenu.Actions.toggleTagWriting: () -> Void` and `writeTagsForSelection: () -> Void`, plus `make(…, tagWritingEnabled: Bool, hasSelection: Bool)`.
- Produces: `LibraryTagSummaryView.show(_ summary: TagWriteSummary)`, `onWrite: (() -> Void)?`, `onCancel: (() -> Void)?`.
- Produces: `LibraryRekordboxReportView.show(_ report: RekordboxSyncReport, tags: TagWriteReport?)`.

**Behaviour:**
- **Menu items** in the rekordbox section:
  - `Keep rekordbox Data in File Tags`, with a checkmark when enabled.
  - `Write rekordbox Tags to Selected Tracks`, enabled with a selection.
- **Turning it on:** `preview(rowIDs: nil)`, then show the summary.
  - **WRITE TAGS:** set `enabledKey`, then run `write(rowIDs: nil, onlyDue: false)`.
  - **CANCEL:** the setting stays off.
- **Turning it off:** immediate, with no overlay.
- **Per selection:** the same flow with `rowIDs: selection` and `onlyDue: false`. It never changes the setting.
- **Summary overlay:** drawn over the table, like the report. Lines:
  - `n files to update`
  - `BPM n · KEY n · LABEL n · REMIXER n · COMPOSER n · GROUPING n`
  - `Read-only, skipped: n`
  - `Not readable now: n`
  - Then a scrollable `TEMPO HALF OR DOUBLE: CHECK IN REKORDBOX` list of paths.
  - Buttons `WRITE TAGS` and `CANCEL`.
- **Report view:** when `tags` has entries, it adds the sections `TEMPO HALF OR DOUBLE: CHECK IN REKORDBOX` and `TAGS NOT WRITTEN`. The second lists read-only and failed paths.

- [ ] **Step 1: Write the failing tests** (the menu items and their states; the overlay's lines from a fixed summary; WRITE TAGS sets the default and calls write with `onlyDue: false`; CANCEL leaves it off; turning off writes nothing; the per-selection flow passes the selection's ids; the report sections appear only with entries)
- [ ] **Step 2: Run to make sure they fail**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run to make sure they pass**, then `./build.sh --run` and `./scripts/shoot.sh --no-build` to capture the summary overlay over the table.
- [ ] **Step 5: Commit** `feat(library): opt-in tag writing with a summary before the first write`

---

## Spec coverage

| Spec item (Delivery 1) | Task |
|---|---|
| `LibrarySchemaV3` fields, migration | 1 |
| Cues stored, not displayed | 2 |
| `tempoSpread`, track classes, `isSet`, `hasPhrases` | 1, 3 |
| MIXES WELL exclusions, ranking, chapter group, `VAR` | 4, 5 |
| Continuation pick (pure function) | 4 |
| Phrase access grant, decoder, import triggers, fallback to no phrases | 6, 7, 8 |
| Tag writing: setting, summary, automatic after sync, per track, fields, rounding, half/double guard, atomic write, read-only skip, unreachable retry | 9, 10, 11, 12 |
| Library gate: phrases imported for most tracks | 8 |

Delivery 2 (the scan) and Delivery 3 (Automix) are not covered, nor is the persisted pick filter, which Delivery 3 needs.

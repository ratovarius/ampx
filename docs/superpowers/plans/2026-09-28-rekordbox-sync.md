# rekordbox Collection Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The library keeps BPM, key, Camelot key, rating, beatgrid, play count and five text fields in sync with a linked rekordbox `collection.xml`, re-importing on its own whenever rekordbox re-exports.

**Architecture:**
- **Pure core.** `RekordboxCollectionParser` turns the XML into `RekordboxCollection`, and `RekordboxImportPlanner` matches it against a library snapshot to produce a `RekordboxImportPlan` (writes + report). Both are value types in, value types out, fully unit-tested.
- **Storage.** `LibrarySchemaV2` adds the fields and a `RekordboxLink` model. `LibraryStore.applyRekordbox` writes one plan in one token-checked transaction; the scanner stops overwriting rekordbox BPM and key.
- **Sync.** `RekordboxSync`, owned by `LibraryEngine`, watches the XML's folder through the existing `LibraryWatcher`, debounces, compares the file stamp, and runs parse → plan → apply as an exclusive job in the scanner's FIFO.
- **UI.** New columns, a footer indicator, a rekordbox section in the ROOTS and File menus, and a report overlay in the Library window.

**Tech Stack:** Swift 6, SwiftData (`VersionedSchema`, lightweight migration), Foundation `XMLParser`, FSEvents via `LibraryWatcher`, AppKit custom drawing, XCTest.

**Spec:** [rekordbox Collection Sync](../specs/2026-09-28-rekordbox-sync-design.md). Engine: [Music Library, Revision 7](../specs/2026-09-11-music-library-design.md); window: [Library Module](../specs/2026-09-27-library-module-design.md).

**Base:** `feature/music-library` (PR #15), in `.worktrees/music-library`.

## Global Constraints

- Nothing is ever written to rekordbox or to audio files. The XML is opened read-only.
- The sync never creates library rows or roots. Tracks outside every root are reported as unmatched.
- A missing rekordbox value never clears an existing BPM or key. Unlinking, or a track leaving the XML, keeps every imported value.
- Precedence: `rekordbox` over `fileTag`. The scanner writes tag BPM and key only when `analysisSource != .rekordbox`.
- The first link shows the report and writes nothing until **Import**. Later syncs apply silently. Zero matches is an error and is never applied.
- Debounce: a check runs **2 s** after the last folder event. An unchanged `(size, modificationDate)` does nothing.
- Syncs and scans never run at the same time.
- Rating: `Rating` 0–255 → `Int((Double(r) / 51).rounded())`, clamped to 0…5. Updated only while `ratingSource` is nil or `.rekordbox`.
- Location: strip the `file://localhost` prefix, percent-decode (`#` stays literal), standardise, resolve symlinks, NFC-normalise. Root paths are NFC-normalised too.
- Library window rules still apply: no native controls (`NSTableView`, `NSScrollView`, `NSTextField`), `AmpXSkin` colours, `AmpXScrollbar`, `AmpXButton`, `AmpXLabel`. The default columns fit the 910 pt minimum window.
- Never add `Co-Authored-By:` lines. Never run `swiftformat` by hand (the hook formats files). `docs/superpowers/` is gitignored but tracked: add docs with `git add -f`.
- No test reads `~/Music` except the opt-in gate (`TEST_RUNNER_AMPX_LIBRARY_GATE=1`, skipped on CI).

## Review Focus

1. **A re-export that is still being written when the debounce fires** (rekordbox writes 40 MB): the parse fails, nothing is written, and the next event retries. The sync must not stick in ⚠ once a complete file lands. Test in Task 6 (`testTruncatedFileRetriesAndRecovers`).
2. **Linking a collection whose tracks sit under a symlinked or differently-cased root path** (`/Users/x/Music` vs a root added as `/Users/x/music` on a case-insensitive volume): the match must still be by path, not fall to the size fallback. Test in Task 4 (`testMatchesThroughSymlinkedRoot`, `testMatchesCaseInsensitivelyOnCaseInsensitiveRoot`).
3. **A scan and a re-export at the same moment** (the export lands in a watched root, since `collection.xml` sits in `~/Music/DJ`): the root scan ignores the non-audio file, and the sync waits for the scan instead of planning against rows the scan is replacing. Test in Task 6 (`testSyncWaitsForRunningScan`).
4. **Unlinking or relinking while a sync is running:** the running sync's token is revoked and it writes nothing; the new link starts clean. Test in Task 6 (`testUnlinkDuringSyncWritesNothing`).
5. **An unknown key spelling** (`Tonality="o"`, or a future rekordbox value such as `12A`): `musicalKey` stores it verbatim, `camelotKey` is nil, and it sorts last in CAMELOT. Test in Task 1 (`testUnknownSpellingIsNil`) and Task 3 (`testCamelotSortPutsUnknownLast`).

---

## Validation commands

**Run `<Suites>`** (one `-only-testing` per suite):

```bash
xcodebuild test -project AmpX.xcodeproj -scheme AmpX \
  -destination "platform=macOS,arch=$(uname -m)" \
  -only-testing:AmpXTests/<Suite> 2>&1 | grep -E 'error: |failed \(|TEST (SUCCEEDED|FAILED)'
```

*Expected FAIL* means compile errors naming the missing symbol, or `failed (` lines for the named tests. *Expected PASS* means `TEST SUCCEEDED`. Run `./scripts/generate-fixtures.sh` once first. Run the full suite once, at the end.

## File map

| File | Responsibility | Task |
|---|---|---|
| `Sources/Library/Rekordbox/CamelotKey.swift` | musical key → Camelot code, sort order | 1 |
| `Sources/Library/Rekordbox/RekordboxCollection.swift` | `RekordboxTrack`, `RekordboxBeat`, `RekordboxCollection` values | 1 |
| `Sources/Library/Rekordbox/RekordboxCollectionParser.swift` | streaming XML parse, Location decoding | 1 |
| `Tests/AmpXTests/Fixtures/rekordbox-collection.xml` | trimmed real export | 1 |
| `Sources/Library/LibrarySchemaV2.swift` | V2 models, `AnalysisSource`, `RatingSource`, `RekordboxLink` | 2 |
| `Sources/Library/LibrarySchemaV1.swift` | migration plan, container factory | 2 |
| `Sources/Library/LibraryStore.swift` | re-parse rule, Camelot derivation on write | 2 |
| `Tests/AmpXTests/LibraryTestSchemaV2.swift` → `LibraryTestSchemaV3.swift` | test-only successor, now 3.0.0 | 2 |
| `Sources/Library/LibraryValues.swift`, `LibraryIndex.swift`, `LibraryQuery.swift` | new `LibraryRow` fields, search, sorts | 3 |
| `Sources/Modules/Library/LibraryColumns.swift` | CAMELOT and five text columns | 3 |
| `Sources/Library/Rekordbox/RekordboxImportPlanner.swift` | matching, writes, report | 4 |
| `Sources/Library/LibraryStore+Rekordbox.swift` | snapshot, link persistence, `applyRekordbox`, sync token | 5 |
| `Sources/Library/LibraryScanner+Scheduling.swift` | exclusive jobs in the FIFO | 6 |
| `Sources/Library/Rekordbox/RekordboxSync.swift`, `LibraryEngine.swift` | watch, debounce, stamp check, link flow | 6 |
| `Sources/Modules/Library/LibraryRekordboxReportView.swift` | report overlay | 7 |
| `LibraryFooterView.swift`, `LibraryRootsMenu.swift`, `LibraryModuleContent.swift` | indicator, menu section, wiring | 7 |
| `Sources/Utilities/AmpXMenuCatalog.swift`, `AmpXMenuBuilder.swift`, `Sources/AmpXApplicationController.swift` | File menu items | 7 |

`Sources/` and `Tests/AmpXTests/` are synchronized groups; new files need no project edit. Check the fixture is in the test bundle's resources the same way the existing audio fixtures are.

---

## Task 1: Parser and Camelot key

**Files:**
- Create: `Sources/Library/Rekordbox/CamelotKey.swift`, `RekordboxCollection.swift`, `RekordboxCollectionParser.swift`, `Tests/AmpXTests/Fixtures/rekordbox-collection.xml`.
- Test: `Tests/AmpXTests/CamelotKeyTests.swift`, `RekordboxCollectionParserTests.swift`.

**Interfaces — produces:**

```swift
enum CamelotKey {
    static func from(musicalKey: String) -> String?     // "Am" → "8A", "C" → "8B"; unknown → nil
    static func sortOrder(_ camelot: String?) -> Int     // 1A=0, 1B=1 … 12B=23; nil/unknown = Int.max
}
struct RekordboxBeat: Codable, Equatable, Sendable { let start: Double; let bpm: Double; let meter: String; let beat: Int }
struct RekordboxTrack: Equatable, Sendable {
    let path: String                  // decoded, standardised, symlink-resolved, NFC absolute path
    let size: Int64?; let duration: Double?
    let bpm: Double?; let tonality: String?
    let rating: Int?                  // already 0…5
    let playCount: Int?
    let label, remixer, composer, grouping, mix: String?   // "" → nil
    let beatGrid: [RekordboxBeat]
}
struct RekordboxCollection: Equatable, Sendable {
    let productVersion: String?
    let tracks: [RekordboxTrack]
    let droppedWithoutLocation: Int
}
enum RekordboxParseError: Error, Equatable { case malformed(line: Int, message: String), notACollection }
enum RekordboxCollectionParser {
    static func parse(_ data: Data) throws -> RekordboxCollection
    static func path(fromLocation: String) -> String?
}
```

Camelot table (minor = A, major = B): 1A A♭m, 1B B; 2A E♭m, 2B F♯; 3A B♭m, 3B D♭; 4A Fm, 4B A♭; 5A Cm, 5B E♭; 6A Gm, 6B B♭; 7A Dm, 7B F; 8A Am, 8B C; 9A Em, 9B G; 10A Bm, 10B D; 11A F♯m, 11B A; 12A D♭m, 12B E. Normalise the input first: `♯`→`#`, `♭`→`b`, trim, and map enharmonics to one pitch class (G#=Ab, D#=Eb, A#=Bb, C#=Db, Gb=F#, Cb=B, Fb=E, E#=F, B#=C).

**Fixture.** Trim `~/Music/DJ/collection.xml` with a one-off `uv run python` script (not committed) to about 20 `TRACK`s plus one short `PLAYLISTS` node, keeping the `PRODUCT` element. Rewrite every `Location` prefix `file://localhost/Users/<user>/Music/` to `file://localhost/AmpXFixture/Music/`. Include: the entry whose path contains `#`, three entries whose names have accents (keep their bytes as rekordbox wrote them), one entry with several `TEMPO` elements, one entry outside `Music/DJ`, one entry with `Rating="255"`. Then hand-edit: remove `AverageBpm` and `Tonality` from one entry, set `Label=""` on one, and remove `Location` from one.

- [ ] **Step 1: Write failing tests:**
  - `CamelotKeyTests`: `testAllTwentyFourKeys` (table above), `testRekordboxSpellings` (`F#m`→`11A`, `Dbm`→`12A`, `Abm`→`1A`, `Bbm`→`3A`, `Db`→`3B`), `testEnharmonicsAndSymbols` (`G#m`→`1A`, `C♯m`→`12A`, `E♭`→`5B`), `testUnknownSpellingIsNil` (`""`, `"o"`, `"12A"`, `"H"`), `testSortOrder` (`1A` < `1B` < `2A` < `12B` < nil).
  - `RekordboxCollectionParserTests`:
    - `testParsesFixture`: `productVersion == "7.2.19"`, track count = fixture TRACKs minus 1, `droppedWithoutLocation == 1`.
    - `testHashInPathIsLiteral`: the `#` entry's `path` ends with its full file name.
    - `testPathsAreNFC`: every `path == path.precomposedStringWithCanonicalMapping`.
    - `testVariableTempoGrid`: the multi-TEMPO entry has `beatGrid.count > 1` with values from the fixture.
    - `testRatingScaled`: `Rating="255"` → 5; `Rating="0"` → 0.
    - `testMissingAttributesAreNil`: the edited entry has `bpm == nil`, `tonality == nil`, and still parses; `Label=""` → `label == nil`.
    - `testPlaylistsIgnored`: no track comes from `PLAYLISTS`.
    - `testTruncatedFileThrows`: the fixture cut at half its length → throws `.malformed`, no result.
    - `testNotACollection`: `<foo/>` → `.notACollection`.
- [ ] **Step 2: Run `CamelotKeyTests RekordboxCollectionParserTests`.** Expected FAIL.
- [ ] **Step 3: Implement.** `XMLParser` with a delegate class; read only `DJ_PLAYLISTS/PRODUCT`, `COLLECTION/TRACK` and its `TEMPO` children, and skip everything under `PLAYLISTS`. `path(fromLocation:)` strips the prefix, calls `removingPercentEncoding` (not `URL(string:)`, which would treat `#` as a fragment), then `URL(fileURLWithPath:).standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping`.
- [ ] **Step 4: Run `CamelotKeyTests RekordboxCollectionParserTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: parse rekordbox collection exports`.

## Task 2: `LibrarySchemaV2` and the re-parse rule

**Files:**
- Create: `Sources/Library/LibrarySchemaV2.swift`.
- Modify: `Sources/Library/LibrarySchemaV1.swift` (typealiases, `LibraryMigrationPlan`, `LibraryContainerFactory`), `Sources/Library/LibraryStore.swift` (`apply(_:to:)`).
- Rename: `Tests/AmpXTests/LibraryTestSchemaV2.swift` → `LibraryTestSchemaV3.swift`.
- Test: extend `LibrarySchemaMigrationTests.swift`, `LibraryStoreTests.swift`, `LibraryScannerTests.swift`.

**Interfaces — consumes:** `CamelotKey.from(musicalKey:)` (Task 1). **Produces:**

```swift
enum AnalysisSource: String, Codable, Sendable { case fileTag, rekordbox }
enum RatingSource: String, Codable, Sendable { case rekordbox, user }
enum LibrarySchemaV2: VersionedSchema {          // versionIdentifier 2.0.0
    // LibraryRoot: unchanged copy of V1.
    // LibraryTrack: V1 fields plus
    //   analysisSource: AnalysisSource?, camelotKey: String?, beatGrid: Data?,
    //   label, remixer, composer, grouping, mix: String?,
    //   ratingSource: RatingSource?, rekordboxPlayCount: Int (= 0)
    //   init sets schemaVersion = 2
    // RekordboxLink (new): id: UUID (unique), bookmark: Data, displayPath: String,
    //   stampSize: Int64?, stampModifiedAt: Date?, lastImportAt: Date?,
    //   firstImportConfirmed: Bool, lastReport: Data?, lastError: String?
}
typealias LibraryRoot = LibrarySchemaV2.LibraryRoot
typealias LibraryTrack = LibrarySchemaV2.LibraryTrack
typealias RekordboxLink = LibrarySchemaV2.RekordboxLink
```

`LibraryMigrationPlan.schemas = [V1, V2]`, with one `.custom(fromVersion: V1, toVersion: V2, willMigrate: nil, didMigrate:)` stage whose `didMigrate` sets `schemaVersion = 2` on every track and sets `analysisSource = .fileTag` and `camelotKey` where `bpm` or `musicalKey` is non-nil. The container factory opens `Schema(versionedSchema: LibrarySchemaV2.self)`. The test-only schema becomes `LibraryTestSchemaV3` (3.0.0), a copy of V2 plus its one extra field; its migration tests move from V1→test-V2 to V2→test-V3.

`LibraryStore.apply(_ write: LibraryParseWrite, to:)` (the scanner's write) changes only for BPM and key:

```swift
if row.analysisSource != .rekordbox {
    row.bpm = metadata.bpm
    row.musicalKey = metadata.musicalKey
    row.analysisSource = metadata.bpm == nil && metadata.musicalKey == nil ? nil : .fileTag
    row.camelotKey = metadata.musicalKey.flatMap(CamelotKey.from(musicalKey:))
}
```

- [ ] **Step 1: Write failing tests:**
  - `LibrarySchemaMigrationTests`:
    - `testV1StoreOpensAsV2KeepingValues`: write a V1 store on disk (existing helper) with a row that has `bpm = 124`, `musicalKey = "Am"`, `rating = 3`, `playCount = 2`; open with the factory. Every V1 value is equal; `schemaVersion == 2`; `analysisSource == .fileTag`; `camelotKey == "8A"`; `rekordboxPlayCount == 0`; the text fields, `beatGrid` and `ratingSource` are nil; no `RekordboxLink` exists.
    - `testLightweightMigrationToTestV3` and `testNewerStoreRefusesToOpenAndKeepsRows` (renamed from the V2 versions, now against test V3).
  - `LibraryStoreTests`: `testParsedWriteKeepsRekordboxBpmAndKey`: a row with `analysisSource = .rekordbox`, `bpm = 126`, `musicalKey = "Fm"`; apply a parse write with `bpm = 120`, `musicalKey = "Am"`, a new title → title updated, BPM and key unchanged. `testParsedWriteRefreshesFileTagValues`: same with `.fileTag` → `bpm == 120`, `camelotKey == "8A"`.
  - `LibraryScannerTests`: `testRescanAfterImportKeepsRekordboxValues`: fake file system; mark a row `.rekordbox`; bump its mtime; rescan → BPM and key unchanged, and the re-read title is stored.
- [ ] **Step 2: Run `LibrarySchemaMigrationTests LibraryStoreTests LibraryScannerTests`.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `LibrarySchemaMigrationTests LibraryStoreTests LibraryScannerTests LibraryEngineTests LibraryIdentityTests LibraryReconcilerTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: library schema V2 with rekordbox fields`.

## Task 3: Rows, search, sorts and columns

**Files:**
- Modify: `Sources/Library/LibraryValues.swift`, `LibraryIndex.swift`, `LibraryQuery.swift`, `Sources/Modules/Library/LibraryColumns.swift`, `LibraryTrackTableView.swift` (cell text for the new columns).
- Test: extend `LibraryQueryTests.swift`, `LibraryColumnsTests.swift`, `LibraryTrackTableViewTests.swift`.

**Interfaces — consumes:** Task 2's fields. **Produces:**

```swift
struct LibraryRow {                                   // additions, after musicalKey
    let camelotKey: String?
    let label, remixer, composer, grouping, mix: String?
}
enum LibrarySortColumn { /* existing */ case camelotKey, label, remixer, composer, grouping, mix }
enum LibraryColumn: CaseIterable {
    case number, artist, title, genre, time, bpm, key, camelot, kbps, format,
         label, remixer, composer, grouping, mix
}
```

- `searchKey` also folds in label, remixer, composer, grouping and mix.
- CAMELOT sorts by `CamelotKey.sortOrder`, then the existing tie-breakers. The five text sorts are case- and diacritic-insensitive with nil last, like GENRE.
- Columns: `camelot` title `"CAMELOT"`, minimum width 58, right-aligned false, weight 0. Text columns: titles `"LABEL"`, `"REMIXER"`, `"COMPOSER"`, `"GROUPING"`, `"MIX"`, minimum 70, weight 1.
- `LibraryColumnSet.default` = every column except `number` and the five text columns. The CAMELOT column fits: the default minimum widths must sum to ≤ the table's width at the 910 pt window (assert it in a test with `LibraryModuleLayout`'s table width).
- Decoding a stored `LibraryColumnSet` from L2 (no `camelot`) inserts `camelot` after `key`, so existing users see it.

- [ ] **Step 1: Write failing tests:**
  - `LibraryQueryTests`: `testSearchMatchesLabelAndRemixer`, `testCamelotSortOrder` (`1A, 1B, 8A, 12B, nil`), `testCamelotSortPutsUnknownLast`, `testLabelSortNilLast`.
  - `LibraryColumnsTests`: `testDefaultSetShowsCamelotHidesTextColumns`, `testDefaultColumnsFitMinimumWindow`, `testStoredL2SetGainsCamelotAfterKey`, `testNewColumnsMapToSorts`.
  - `LibraryTrackTableViewTests`: `testCamelotAndLabelCellsDrawValues` (cell text for a row with `camelotKey = "8A"`, `label = "Denature Records"`), `testEmptyCamelotDrawsBlank`.
- [ ] **Step 2: Run `LibraryQueryTests LibraryColumnsTests LibraryTrackTableViewTests`.** Expected FAIL.
- [ ] **Step 3: Implement,** letting the compiler list every `LibraryRow(...)` construction and exhaustive switch on `LibraryColumn`.
- [ ] **Step 4: Run `LibraryQueryTests LibraryColumnsTests LibraryTrackTableViewTests LibraryChangePublicationTests LibraryBrowserModelTests LibraryModuleContentTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: camelot and rekordbox text columns in the library`.

## Task 4: Import planner

**Files:** Create `Sources/Library/Rekordbox/RekordboxImportPlanner.swift`; test `Tests/AmpXTests/RekordboxImportPlannerTests.swift`.

**Interfaces — consumes:** `RekordboxCollection`, `RekordboxTrack`, `RekordboxBeat` (Task 1); `AnalysisSource`, `RatingSource` (Task 2). **Produces:**

```swift
struct RekordboxRootPath: Sendable, Equatable { let id: UUID; let path: String; let caseSensitive: Bool }  // path NFC, resolved
struct RekordboxRowSnapshot: Sendable, Equatable {
    let id: UUID; let rootID: UUID; let relativePath: String
    let fileSize: Int64; let duration: Double
    let bpm: Double?; let musicalKey: String?; let analysisSource: AnalysisSource?
    let rating: Int; let ratingSource: RatingSource?; let rekordboxPlayCount: Int
    let label, remixer, composer, grouping, mix: String?
    let beatGrid: Data?
}
struct RekordboxLibrarySnapshot: Sendable { let roots: [RekordboxRootPath]; let rows: [RekordboxRowSnapshot] }
struct RekordboxRowValues: Sendable, Equatable {       // the row's full target state; the store writes all of it
    var bpm: Double?; var musicalKey: String?; var analysisSource: AnalysisSource?
    var rating: Int; var ratingSource: RatingSource?; var rekordboxPlayCount: Int
    var label, remixer, composer, grouping, mix: String?
    var beatGrid: Data?
}
struct RekordboxRowWrite: Sendable, Equatable { let rowID: UUID; let rootID: UUID; let values: RekordboxRowValues }
struct RekordboxSyncReport: Codable, Sendable, Equatable {
    struct Ambiguity: Codable, Sendable, Equatable { let path: String; let candidates: [String] }
    struct RatingConflict: Codable, Sendable, Equatable { let path: String; let library: Int; let rekordbox: Int }
    var matched = 0, updated = 0, droppedWithoutLocation = 0
    var unmatched: [String] = []
    var ambiguous: [Ambiguity] = []
    var ratingConflicts: [RatingConflict] = []
    var noLongerInRekordbox: [String] = []
}
struct RekordboxImportPlan: Sendable, Equatable { let writes: [RekordboxRowWrite]; let report: RekordboxSyncReport }
enum RekordboxSyncError: Error, Equatable { case noMatches }
enum RekordboxImportPlanner {
    static func plan(_ collection: RekordboxCollection, library: RekordboxLibrarySnapshot) throws -> RekordboxImportPlan
}
```

Rules, per matched track, producing target values from the row's current ones:
- **BPM and key:** if rekordbox has either, set that field, and `analysisSource = .rekordbox`. A nil rekordbox field keeps the row's value.
- **Rating:** if `ratingSource != .user` and rekordbox has a rating, set it and `.rekordbox`. If `.user` and the values differ, add a `RatingConflict` and keep the row's.
- **Play count, text fields:** mirror rekordbox (nil stays nil). **Beat grid:** `JSONEncoder` with sorted keys of `beatGrid`, nil when empty.
- A write is emitted only when the target differs from the snapshot. `matched` counts matched tracks; `updated` counts writes.
- **Matching, in two passes so XML order never matters:**
  1. **Path pass**, over all tracks: if the track path has a root's path as a component prefix (compared case-insensitively when `!caseSensitive`), the remainder is the candidate `relativePath`, looked up with the same case rule. Two entries resolving to one row → both `ambiguous`.
  2. **Fallback pass**, only for tracks the path pass left unmatched, and only against rows the path pass did not claim: rows with equal `fileSize` and `abs(duration - track.duration) <= 1`. One candidate wins; several → `ambiguous` (candidates as `root path + relativePath`); none → `unmatched`. Two fallback tracks claiming one row → both `ambiguous`.

  Copies of a library file stored elsewhere (common in this collection: `MUSICA/…` vs `DJ/…`) therefore never displace the file's own path match.
- **No longer in rekordbox:** rows with `analysisSource == .rekordbox` that no track matched, listed as their full paths.
- `matched == 0` → throw `.noMatches`.

- [ ] **Step 1: Write failing tests** (hand-built snapshots and collections; no file system):
  - `testMatchesByPath`, `testMatchesThroughSymlinkedRoot` (root path given already resolved; track path resolved to the same), `testMatchesCaseInsensitivelyOnCaseInsensitiveRoot`, `testCaseSensitiveRootDoesNotFoldCase`.
  - `testFallbackBySizeAndDuration` (duration 300.4 vs 301.2 matches; 302.5 does not), `testFallbackIncludesUnavailableRootRows`, `testAmbiguousFallbackNotWritten`, `testDuplicateEntriesForOneFileAreAmbiguous`, `testFallbackCopyBeforePathMatchDoesNotStealRow` (an outside-root entry with the same size and duration listed **before** the row's own path entry → the path entry matches, the copy is unmatched).
  - `testOutsideRootsIsUnmatched`, `testNoMatchesThrows`.
  - `testRekordboxWinsOverFileTag`, `testMissingRekordboxValueKeepsExisting`.
  - `testRatingFromRekordbox`, `testUserRatingIsConflictNotOverwritten`.
  - `testTextFieldsAndPlayCountMirror`, `testBeatGridEncodedDeterministically`.
  - `testSecondPlanOfSameCollectionHasNoWrites` (apply the first plan's values to the snapshot, plan again → `writes.isEmpty`, `matched` unchanged).
  - `testNoLongerInRekordboxListed`.
- [ ] **Step 2: Run `RekordboxImportPlannerTests`.** Expected FAIL.
- [ ] **Step 3: Implement.** Build a `[rootID: [pathKey: row]]` map once; the plan must stay linear in tracks + rows (2,449 × 2,232 must not be quadratic).
- [ ] **Step 4: Run `RekordboxImportPlannerTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: plan rekordbox imports against the library`.

## Task 5: Store: snapshot, link and apply

**Files:** Create `Sources/Library/LibraryStore+Rekordbox.swift`; modify `LibraryValues.swift` (`LibraryChange`), `LibraryEngine.swift` and `LibraryIndex.swift` (exhaustive switches); test `Tests/AmpXTests/LibraryStoreRekordboxTests.swift`.

**Interfaces — consumes:** Task 4's types; `LibraryStore.commit(_:_:)`, `dependencies.bookmarks`, `dependencies.scope`, `dependencies.now`. **Produces:**

```swift
enum LibraryChange { /* existing */ case rekordboxLinkChanged }
struct RekordboxFileStamp: Codable, Sendable, Equatable { let size: Int64; let modifiedAt: Date }
struct RekordboxSyncToken: Hashable, Sendable { fileprivate let nonce: UUID }
struct RekordboxLinkSnapshot: Sendable, Equatable {
    let url: URL; let displayPath: String
    let stamp: RekordboxFileStamp?; let lastImportAt: Date?
    let firstImportConfirmed: Bool; let lastReport: RekordboxSyncReport?; let lastError: String?
}
extension LibraryStore {
    func rekordboxSnapshot() throws -> RekordboxLibrarySnapshot    // every root (available or not) and row
    func setRekordboxLink(url: URL) throws                         // replaces any link; bookmark + scope start
    func removeRekordboxLink() throws                              // stops scope; rows untouched
    func rekordboxLink() throws -> RekordboxLinkSnapshot?          // resolves the bookmark, refreshes if stale
    func beginRekordboxSync() -> RekordboxSyncToken
    func revokeRekordboxSync()
    func applyRekordbox(_ plan: RekordboxImportPlan, stamp: RekordboxFileStamp, confirmFirstImport: Bool,
                        token: RekordboxSyncToken) throws
    func recordRekordboxError(_ message: String?) throws
}
enum LibraryStoreError { /* existing */ case noRekordboxLink }
```

- `applyRekordbox`, in one `commit(nil)`: check the token equals the active one (else `.revokedToken`); write each `RekordboxRowWrite`'s values, and set `camelotKey = musicalKey.flatMap(CamelotKey.from)`; store `stamp`, `lastImportAt = now()`, `lastReport` (JSON), `lastError = nil`, and `firstImportConfirmed ||= confirmFirstImport`. Publish `.rowsChanged(rootID:)` once per affected root, and `.rekordboxLinkChanged`. Writes for a row that no longer exists are skipped.
- `setRekordboxLink` and `removeRekordboxLink` revoke the active sync token first, and publish `.rekordboxLinkChanged`.
- `LibraryIndex` and `LibraryEngine.follow` treat `.rekordboxLinkChanged` as no-op.

- [ ] **Step 1: Write failing tests** (in-memory store, `ScopeSpy`, fake bookmarking from `LibraryTestSupport`):
  - `testSnapshotIncludesUnavailableRoots`.
  - `testApplyWritesValuesAndDerivesCamelot`, `testApplyStoresStampReportAndConfirmation`, `testApplyPublishesPerRootChanges`.
  - `testRevokedTokenWritesNothing`, `testRelinkRevokesRunningToken`.
  - `testRemoveLinkKeepsRowValues`.
  - `testLinkBookmarkStartsAndStopsScope`.
  - `testApplySkipsDeletedRows`.
  - `testFailedSaveRollsBackRowsAndLink` (inject `saveContext` failure).
- [ ] **Step 2: Run `LibraryStoreRekordboxTests`.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `LibraryStoreRekordboxTests LibraryStoreTests LibraryChangePublicationTests LibraryEngineTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: store rekordbox links and imports`.

## Task 6: `RekordboxSync`

**Files:**
- Create: `Sources/Library/Rekordbox/RekordboxSync.swift`.
- Modify: `Sources/Library/LibraryScanner.swift` and `LibraryScanner+Scheduling.swift` (exclusive jobs), `Sources/Library/LibraryEngine.swift` (own, start, route events, stop).
- Test: `Tests/AmpXTests/RekordboxSyncTests.swift`; extend `LibraryScanSchedulingTests.swift`.

**Interfaces — consumes:** Tasks 1, 4, 5. **Produces:**

```swift
extension LibraryScanner {
    /// FIFO job alongside root scans: runs when no scan runs; returns when `work` finishes.
    func performExclusive(_ work: @escaping @Sendable () async -> Void) async
}
struct RekordboxFileAccess: Sendable {
    var stamp: @Sendable (URL) throws -> RekordboxFileStamp?   // nil = file missing
    var read: @Sendable (URL) throws -> Data
    static let foundation: RekordboxFileAccess
}
enum RekordboxSyncStatus: Equatable, Sendable {
    case unlinked
    case idle(lastSync: Date?)
    case syncing
    case awaitingConfirmation(RekordboxSyncReport)
    case failed(String)
}
actor RekordboxSync {
    static let watchID: UUID                  // fixed UUID used with LibraryWatcher.bind/unbind
    init(store: LibraryStore, scanner: LibraryScanner, watcher: LibraryWatcher,
         files: RekordboxFileAccess, debounce: Duration = .seconds(2),
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })
    func start() async                        // resolve link; bind the parent folder; check once
    func stop() async                         // revoke; unbind; wait for work
    func folderChanged()                      // (re)starts the debounce
    func link(url: URL) async throws -> RekordboxSyncReport     // stores link, plans, status .awaitingConfirmation
    func confirmFirstImport() async throws
    func cancelFirstImport() async throws     // removes the link
    func syncNow() async                      // ignores the stamp check
    func unlink() async throws
    func status() -> RekordboxSyncStatus
    func statuses() -> AsyncStream<RekordboxSyncStatus>   // current value first, then changes
    func lastReport() async -> RekordboxSyncReport?
}
actor LibraryEngine { /* existing */ nonisolated let rekordbox: RekordboxSync }   // stored, set in open(_:)
struct LibraryEngineConfiguration { /* existing */ var rekordboxFiles: RekordboxFileAccess = .foundation; var rekordboxDebounce: Duration = .seconds(2) }
```

Behaviour:
- **Check** (after debounce, at `start`, or `syncNow` without the stamp test): read the link. No link → `.unlinked`. File missing → `.failed("rekordbox file missing")`, nothing written. Stamp equal to the stored one and confirmed → `.idle`. Otherwise run one job through `scanner.performExclusive`: `beginRekordboxSync` → read → parse → `rekordboxSnapshot` → plan → (confirmed) `applyRekordbox(confirmFirstImport: false)`, or (not confirmed) keep the plan and stamp in memory and go to `.awaitingConfirmation`.
- **Failures:** a parse error on the first attempt schedules one more check after another debounce, with no event needed. A second consecutive failure → `.failed(message)` and `recordRekordboxError`. `.noMatches` → `.failed("No tracks in this collection match the library")`, never applied. A later successful check clears the failure.
- **Collapse:** a check requested while one is queued or running sets a follow-up flag; at most one follow-up runs.
- **Engine:** `LibraryEngine.open` creates the sync and calls `start()` after roots are watched. `handle(.changed(RekordboxSync.watchID))` and `.rootChanged(RekordboxSync.watchID)` call `folderChanged()`. `stop()` stops the sync before the scanner.
- `confirmFirstImport` applies the kept plan with `confirmFirstImport: true`, but only if the file's stamp still equals the kept one; otherwise it re-plans and stays awaiting confirmation.

- [ ] **Step 1: Write failing tests** (in-memory store with one root and rows, `FakeLibraryFileSystem`, a fake `RekordboxFileAccess` serving fixture data and a controllable stamp, a `sleep` driven by `TestBarrier`):
  - `LibraryScanSchedulingTests`: `testExclusiveJobWaitsForRunningScan`, `testScanWaitsForExclusiveJob`, `testExclusiveJobsRunInOrder`.
  - `RekordboxSyncTests`:
    - `testLinkPlansButWritesNothing`, `testConfirmAppliesPlan`, `testCancelRemovesLinkAndWritesNothing`, `testConfirmAfterFileChangedReplans`.
    - `testBurstOfEventsSyncsOnce` (five `folderChanged()` within the debounce → one parse).
    - `testUnchangedStampDoesNothing`, `testChangedStampAppliesSilently`.
    - `testStartChecksOnce` (a stamp changed while stopped is applied at `start`).
    - `testSyncWaitsForRunningScan`.
    - `testTruncatedFileRetriesAndRecovers` (truncated data → retry → still truncated → `.failed`; then full data plus an event → `.idle`).
    - `testMissingFileFailsWithoutWriting`, `testNoMatchesNeverApplies`.
    - `testUnlinkDuringSyncWritesNothing`, `testStopRevokesAndWaits`.
    - `testStatusesStream` (`.unlinked` → `.awaitingConfirmation` → `.syncing` → `.idle`).
  - `LibraryEngineTests`: `testWatcherEventForSyncIDReachesSync`.
- [ ] **Step 2: Run `RekordboxSyncTests LibraryScanSchedulingTests LibraryEngineTests`.** Expected FAIL.
- [ ] **Step 3: Implement.** In the scanner, change the queue element from `UUID` to `enum Job: Hashable { case root(UUID), exclusive(UUID) }`, keeping every existing root rule (one pending entry per root, follow-up collapse, cancel). An exclusive job's id is fresh per call.
- [ ] **Step 4: Run `RekordboxSyncTests LibraryScanSchedulingTests LibraryEngineTests LibraryScannerTests LibraryWatcherTests LibraryEngineIntegrationTests LibraryControllerTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: watch and sync the linked rekordbox collection`.

## Task 7: UI: indicator, menus, report overlay

**Files:**
- Create: `Sources/Modules/Library/LibraryRekordboxReportView.swift`.
- Modify: `LibraryFooterView.swift`, `LibraryRootsMenu.swift`, `LibraryModuleContent.swift`, `LibraryModuleLayout.swift`, `Sources/Utilities/AmpXMenuCatalog.swift`, `AmpXMenuBuilder.swift`, `Sources/AmpXApplicationController.swift`.
- Test: extend `LibraryChromeTests.swift`, `LibraryRootsMenuTests.swift`, `LibraryModuleContentTests.swift`, `AmpXMenuTests` (whichever suite locks `AmpXMenuCatalog`).

**Interfaces — consumes:** `RekordboxSync`, `RekordboxSyncStatus`, `RekordboxSyncReport`, `RekordboxLinkSnapshot` (Tasks 5–6). **Produces:**

```swift
extension LibraryFooterView { func update(/* existing params */, rekordbox: RekordboxSyncStatus) }
enum LibraryFooterView.RekordboxText { static func text(for: RekordboxSyncStatus, calendar: Calendar) -> String? }
    // .unlinked → nil; .idle(d) → "REKORDBOX HH:mm" (today) or "REKORDBOX dd MMM"; .idle(nil) → "REKORDBOX";
    // .syncing and .awaitingConfirmation → "REKORDBOX SYNCING"; .failed → "REKORDBOX ⚠"
struct LibraryRekordboxMenuState: Equatable { let displayPath: String?; let lastSync: Date?; let isBusy: Bool }
extension LibraryRootsMenu.Actions {
    var linkRekordbox: () -> Void; var syncRekordbox: () -> Void; var viewRekordboxReport: () -> Void
    var unlinkRekordbox: () -> Void
}
static func LibraryRootsMenu.make(roots:, rekordbox: LibraryRekordboxMenuState, actions:) -> NSMenu
enum AmpXMenuCatalog.FileItem { /* existing */
    case linkRekordbox = "Link rekordbox Collection…", syncRekordbox = "Sync rekordbox Now",
         viewRekordboxSync = "View Last rekordbox Sync", unlinkRekordbox = "Unlink rekordbox Collection"
}
@MainActor final class LibraryRekordboxReportView: AmpXView {
    enum Mode { case confirm, review }
    var onImport: () -> Void; var onCancel: () -> Void; var onClose: () -> Void
    func show(_ report: RekordboxSyncReport, error: String?, mode: Mode)
    static func summary(_ report: RekordboxSyncReport) -> [String]
}
protocol LibraryPanelPresenting { /* existing */ func chooseRekordboxCollection() async -> URL? }
```

- **ROOTS menu:** after the roots, a separator and a "REKORDBOX" section. Unlinked: *Link Collection…*. Linked: disabled lines with the path and "Last sync 14:30" (or "Never synced"), then *Sync Now*, *View Last Sync*, *Relink…* (same as link) and *Unlink*. *Sync Now* is disabled while `isBusy`.
- **File menu:** the four items after *Add Library Folder…*. Link always enabled; the other three enabled only while linked. Each opens the Library window first (as *Add Library Folder…* does) and routes to the module content.
- **Report overlay:** covers the track table's frame. Summary lines, in this order: `"{matched} of {matched + unmatched + ambiguous} tracks matched"`, `"{updated} updated"`, then, when non-zero, `"{n} not in any library folder"`, `"{n} ambiguous"`, `"{n} rating conflicts"`, `"{n} no longer in rekordbox"`. Below, a scrollable list (`AmpXScrollbar`) of the path entries, grouped under those headings. A non-nil `error` is shown as the first line in the skin's warning colour. Buttons: `confirm` → **Import**, **Cancel**; `review` → **Close**. Esc = Cancel/Close; ↩ = Import/Close.
- **Flow in `LibraryModuleContent`:** *Link* → `panels.chooseRekordboxCollection()` (an `NSOpenPanel` limited to `.xml`) → `controller.ensureEngine()` → `engine.rekordbox.link(url:)` → overlay in `confirm` mode. A thrown error goes to `panels.showError`. *View Last Sync* → overlay in `review` mode with `lastReport()` and the current failure message. The footer indicator is clickable only in `.failed`, and opens the review overlay.
- The module content subscribes to `engine.rekordbox.statuses()` when it attaches to a model, and cancels on window close.

- [ ] **Step 1: Write failing tests:**
  - `LibraryChromeTests`: `testRekordboxIndicatorText` (every status, fixed calendar and dates), `testIndicatorHiddenWhenUnlinked`, `testReportSummaryLines`, `testReportButtonsPerMode`, `testReportShowsErrorFirst`.
  - `LibraryRootsMenuTests`: `testUnlinkedShowsLinkOnly`, `testLinkedShowsPathLastSyncAndActions`, `testSyncNowDisabledWhileBusy`.
  - `LibraryModuleContentTests` (fake panels, engine over the fixture): `testLinkShowsConfirmOverlayWithoutWriting`, `testImportAppliesAndHidesOverlay`, `testCancelLeavesLibraryUnchanged`, `testFailedIndicatorOpensReview`, `testLinkErrorShowsPanelError`.
  - Menu catalog suite: `testFileMenuListsRekordboxItems` (titles and order).
- [ ] **Step 2: Run `LibraryChromeTests LibraryRootsMenuTests LibraryModuleContentTests` and the menu suite.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the same suites plus `AmpXLibraryWindowTests LibraryWiringTests`.** Expected PASS.
- [ ] **Step 5: Visual check.** `./build.sh --run`, open the Library, link `~/Music/DJ/collection.xml`, then `./scripts/shoot.sh --no-build --index <library window>` for the confirm overlay, then again after Import (table showing BPM, KEY, CAMELOT, footer `REKORDBOX HH:mm`). Save both as `docs/superpowers/plans/rekordbox-sync/capture-confirm.png` and `capture-synced.png`.
- [ ] **Step 6: Commit** `feat: rekordbox sync controls and report in the library`.

## Task 8: Verification

**Files:** Create `Tests/AmpXTests/RekordboxCollectionGateTests.swift`; modify the spec (status, verification section) and `docs/superpowers/specs/2026-09-11-dj-mode-design.md` only if something moved.

- [ ] **Step 1: Write the gate test** (skipped unless `TEST_RUNNER_AMPX_LIBRARY_GATE=1`, using `LibraryGateSupport`): a real engine over a temp store with root `~/Music/DJ`; scan; link `~/Music/DJ/collection.xml`; confirm. Assert all 2,232 rows have non-nil `bpm`, `musicalKey` and `camelotKey` with `analysisSource == .rekordbox`, and `report.matched + report.unmatched.count + report.ambiguous.count == 2449 - report.droppedWithoutLocation`. Emit how many of the 217 outside entries fell back or went ambiguous. Then `syncNow()` on the unchanged file: zero writes, elapsed < 2 s. Emit the counts and timings with `emitGate`.
- [ ] **Step 2: Run it:** `TEST_RUNNER_AMPX_LIBRARY_GATE=1` with `-only-testing:AmpXTests/RekordboxCollectionGateTests`. Expected PASS. Record the numbers.
- [ ] **Step 3: Manual check of success criterion 2:** with AmpX open on the Library, re-export from rekordbox after changing one track's BPM there; the new value shows within 5 s with no clicks. Note the measured time.
- [ ] **Step 4: Run the full suite** with `./scripts/run-tests.sh`. Expected: all pass; any failure outside the rekordbox and library code is re-run alone and reported.
- [ ] **Step 5: Update the spec's status** to Implemented, add a *Verification* section with the gate numbers, the manual timing and links to the Task 7 captures. Commit `test: verify rekordbox sync` (docs with `git add -f`).
- [ ] **Step 6: Update PR #15's description** (`gh pr edit 15 -R ratovarius/ampx`): add a *rekordbox sync* subsection under Summary and its test-plan lines, and move "Direct `master.db` reading" into *Known limitations and follow-ups* as the `experimental/rekordbox-db` task. Push `feature/music-library`.

## Coverage audit

| Spec section | Task |
|---|---|
| Decisions: first link confirms, later silent; zero matches never applied | 6, 7 |
| Imported data list; key display in two columns | 2, 3, 4 |
| Removal and unlink keep values | 4 (`noLongerInRekordbox`), 5 (`testRemoveLinkKeepsRowValues`) |
| `LibrarySchemaV2` fields, `RekordboxLink`, migration | 2 |
| Scanner re-parse rule | 2 |
| Parser: Location, attributes, scope, errors | 1 |
| `CamelotKey` | 1 |
| Planner: matching, fallback, ambiguity, only-changed writes, report, zero matches | 4 |
| `applyRekordbox` one transaction, token, change publication | 5 |
| `RekordboxSync`: bookmark, folder watch, launch check, debounce, stamp, turn-taking, collapse, stop | 5, 6 |
| First link flow and File/ROOTS items | 6, 7 |
| UI: columns, search, CAMELOT sort, footer, report overlay | 3, 7 |
| Error handling table | 6 (missing, malformed, zero, revoked), 5 (scope), 7 (⚠ and Relink) |
| Testing table and gate | 1–8 |
| Success criteria 1–5 | 8 (1, 2, 4), 2 (3), 5 (5) |
| Future work: `experimental/rekordbox-db` | 8, step 6 (recorded in the PR; no code) |

## Execution handoff

Tasks are sequential: each consumes the previous task's Interfaces block. Tasks 1 and 4 are pure and can be reviewed alone; Tasks 5–6 carry the concurrency risk (tokens, exclusive jobs) and deserve the closest review.

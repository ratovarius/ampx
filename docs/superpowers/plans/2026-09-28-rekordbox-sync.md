# rekordbox Collection Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a library folder has a rekordbox collection export at its top level, the library imports its BPM, key, Camelot key, rating, beatgrid, play count and five text fields, and re-imports after every re-export. A folder without one shows nothing.

**Architecture:**
- **Pure core.** `RekordboxCollectionParser` turns the XML into `RekordboxCollection` (and sniffs whether a file is an export), and `RekordboxImportPlanner` matches it against a library snapshot to produce a `RekordboxImportPlan` (writes + report). Value types in, value types out.
- **Storage.** `LibrarySchemaV2` adds the fields and a per-root `RekordboxSource` model. `LibraryStore.applyRekordbox` writes one plan in one token-checked transaction; the scanner stops overwriting rekordbox BPM and key.
- **Sync.** `RekordboxSync`, owned by `LibraryEngine`, listens for finished root scans, discovers the export at that root's top level, compares its stamp, and runs parse → plan → apply as an exclusive job in the scanner's FIFO. No watcher of its own: root scans already follow FSEvents.
- **UI.** New columns, a footer indicator, a line per root in the ROOTS menu, and a read-only report overlay.

**Tech Stack:** Swift 6, SwiftData (`VersionedSchema`, custom migration stage), Foundation `XMLParser`, AppKit custom drawing, XCTest.

**Spec:** [rekordbox Collection Sync, Revision 3](../specs/2026-09-28-rekordbox-sync-design.md). Engine: [Music Library, Revision 7](../specs/2026-09-11-music-library-design.md); window: [Library Module](../specs/2026-09-27-library-module-design.md).

**Base:** `feature/music-library` (PR #15), in `.worktrees/music-library`.

## Global Constraints

- Nothing is ever written to rekordbox or to audio files. Exports are opened read-only.
- Discovery looks only at a root's **top level**: files whose extension is `xml` in any case, accepted only if their first **4 KB** contain `<DJ_PLAYLISTS` and a `PRODUCT` element with `Name="rekordbox"`. Newest modification date wins; ties go to the name that sorts first.
- **Nothing in the UI, ever, for failures:** no popup, alert, error indicator or error text. A missing, vanished, unmatched or unreadable export is silent in the UI. Failures are logged to the console with `Logger(subsystem: "com.ampx.macos", category: "RekordboxSync")`: a parse failure at `.info` the first time for a given `(size, modificationDate)`, `.error` when the same file fails again; unreadable files at `.info`.
- Always applies silently, the first discovery included. There is no file picker, manual link or confirmation.
- The sync never creates library rows or roots. A missing rekordbox value never clears an existing BPM or key. An export that disappears, and tracks that leave it, keep every imported value.
- Precedence: `rekordbox` over `fileTag`. The scanner writes tag BPM and key only when `analysisSource != .rekordbox`.
- Syncs and scans never run at the same time. Checks due together run oldest export first.
- Rating: `Rating` 0–255 → `Int((Double(r) / 51).rounded())`, clamped to 0…5. Updated only while `ratingSource` is nil or `.rekordbox`.
- Location: strip the `file://localhost` prefix, percent-decode (`#` stays literal), standardise, resolve symlinks, NFC-normalise. Root paths are NFC-normalised too.
- Library window rules still apply: no native controls (`NSTableView`, `NSScrollView`, `NSTextField`), `AmpXSkin` colours, `AmpXScrollbar`, `AmpXButton`, `AmpXLabel`. The default columns fit the 910 pt minimum window.
- Never add `Co-Authored-By:` lines. Never run `swiftformat` by hand (the hook formats files). `docs/superpowers/` is gitignored but tracked: add docs with `git add -f`.
- No test reads `~/Music` except the opt-in gate (`TEST_RUNNER_AMPX_LIBRARY_GATE=1`, skipped on CI).

## Review Focus

1. **A re-export that is still being written when its root's scan finishes** (rekordbox writes 40 MB): the parse fails and nothing is written. The write's completion triggers another scan and check, which must succeed, and no failure state ever reaches the UI. Test in Task 6 (`testTruncatedThenCompleteFileSyncs`).
2. **A root whose path reaches the tracks through a symlink or with different case** (`/Users/x/music` on a case-insensitive volume): the match must still be by path, not fall to the size fallback. Test in Task 4 (`testMatchesThroughSymlinkedRoot`, `testMatchesCaseInsensitivelyOnCaseInsensitiveRoot`).
3. **Copies of library files stored elsewhere, listed before the library's own entries in the XML** (this collection has `MUSICA/…` copies of `DJ/…` tracks): the copy must not claim the row by the size fallback. Test in Task 4 (`testFallbackCopyBeforePathMatchDoesNotStealRow`).
4. **Removing or relocating a root while its check runs:** that check writes nothing; checks for other roots are unaffected. Test in Task 6 (`testRemovingRootDuringCheckWritesNothing`, `testOtherRootCheckSurvivesRemoval`).
5. **An unknown key spelling** (`Tonality="o"`, or a future `12A`): `musicalKey` stores it verbatim, `camelotKey` is nil, and it sorts last in CAMELOT. Test in Task 1 (`testUnknownSpellingIsNil`) and Task 3 (`testCamelotSortPutsUnknownLast`).

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
| `Sources/Library/Rekordbox/RekordboxCollectionParser.swift` | streaming parse, export sniff, Location decoding | 1 |
| `Tests/AmpXTests/Fixtures/rekordbox-collection.xml` | trimmed real export | 1 |
| `Sources/Library/LibrarySchemaV2.swift` | V2 models, `AnalysisSource`, `RatingSource`, `RekordboxSource` | 2 |
| `Sources/Library/LibrarySchemaV1.swift` | migration plan, container factory | 2 |
| `Sources/Library/LibraryStore.swift` | re-parse rule, Camelot derivation on write | 2 |
| `Tests/AmpXTests/LibraryTestSchemaV2.swift` → `LibraryTestSchemaV3.swift` | test-only successor, now 3.0.0 | 2 |
| `Sources/Library/LibraryValues.swift`, `LibraryIndex.swift`, `LibraryQuery.swift` | new `LibraryRow` fields, search, sorts | 3 |
| `Sources/Modules/Library/LibraryColumns.swift`, `LibraryTrackTableView.swift` | CAMELOT and five text columns | 3 |
| `Sources/Library/Rekordbox/RekordboxImportPlanner.swift` | matching, writes, report | 4 |
| `Sources/Library/LibraryStore+Rekordbox.swift`, `LibraryStore+Roots.swift` | snapshot, sources, `applyRekordbox`, per-root tokens | 5 |
| `Sources/Library/LibraryFileSystem.swift`, `Tests/AmpXTests/LibraryScanTestSupport.swift` | top-level listing, prefix and full reads | 6 |
| `Sources/Library/LibraryScanner+Scheduling.swift` | exclusive jobs in the FIFO | 6 |
| `Sources/Library/Rekordbox/RekordboxSync.swift`, `LibraryEngine.swift` | discovery, checks, status | 6 |
| `Sources/Modules/Library/LibraryRekordboxReportView.swift` | report overlay | 7 |
| `LibraryFooterView.swift`, `LibraryRootsMenu.swift`, `LibraryModuleContent.swift` | indicator, ROOTS lines, wiring | 7 |

`Sources/` and `Tests/AmpXTests/` are synchronized groups; new files need no project edit. Check the fixture is in the test bundle's resources the same way the existing audio fixtures are.

---

## Task 1: Parser, export sniff and Camelot key

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
    static let sniffLength = 4096
    static func isCollectionExport(prefix: Data) -> Bool
    static func parse(_ data: Data) throws -> RekordboxCollection
    static func path(fromLocation: String) -> String?
}
```

Camelot table (minor = A, major = B): 1A A♭m, 1B B; 2A E♭m, 2B F♯; 3A B♭m, 3B D♭; 4A Fm, 4B A♭; 5A Cm, 5B E♭; 6A Gm, 6B B♭; 7A Dm, 7B F; 8A Am, 8B C; 9A Em, 9B G; 10A Bm, 10B D; 11A F♯m, 11B A; 12A D♭m, 12B E. Normalise the input first: `♯`→`#`, `♭`→`b`, trim, and map enharmonics to one pitch class (G#=Ab, D#=Eb, A#=Bb, C#=Db, Gb=F#, Cb=B, Fb=E, E#=F, B#=C).

`isCollectionExport` decodes the prefix as UTF-8, dropping an incomplete trailing sequence, and checks for `<DJ_PLAYLISTS` and a `<PRODUCT` tag whose `Name="rekordbox"`. It does not parse XML.

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
    - `testSniffAcceptsExport`: the fixture's first 4,096 bytes → true.
    - `testSniffRejectsOthers`: an iTunes `Library.xml` header (`<plist version="1.0">`), empty data, random bytes, and a `DJ_PLAYLISTS` header whose `PRODUCT Name="Other"` → false.
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
    // RekordboxSource (new): rootID: UUID (unique), fileName: String, isPresent: Bool,
    //   stampSize: Int64?, stampModifiedAt: Date?, lastImportAt: Date?,
    //   lastReport: Data?
}
typealias LibraryRoot = LibrarySchemaV2.LibraryRoot
typealias LibraryTrack = LibrarySchemaV2.LibraryTrack
typealias RekordboxSource = LibrarySchemaV2.RekordboxSource
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
    - `testV1StoreOpensAsV2KeepingValues`: write a V1 store on disk (existing helper) with a row that has `bpm = 124`, `musicalKey = "Am"`, `rating = 3`, `playCount = 2`; open with the factory. Every V1 value is equal; `schemaVersion == 2`; `analysisSource == .fileTag`; `camelotKey == "8A"`; `rekordboxPlayCount == 0`; the text fields, `beatGrid` and `ratingSource` are nil; no `RekordboxSource` exists.
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
- Columns: `camelot` title `"CAMELOT"`, minimum width 58, left-aligned, weight 0. Text columns: titles `"LABEL"`, `"REMIXER"`, `"COMPOSER"`, `"GROUPING"`, `"MIX"`, minimum 70, weight 1.
- `LibraryColumnSet.default` = every column except `number` and the five text columns. The default minimum widths must sum to ≤ the table's width at the 910 pt window (assert it with `LibraryModuleLayout`'s table width).
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
    var fileName = ""
    var matched = 0, updated = 0, droppedWithoutLocation = 0
    var unmatched: [String] = []
    var ambiguous: [Ambiguity] = []
    var ratingConflicts: [RatingConflict] = []
    var noLongerInRekordbox: [String] = []
}
struct RekordboxImportPlan: Sendable, Equatable { let writes: [RekordboxRowWrite]; let report: RekordboxSyncReport }
enum RekordboxImportPlanner {
    static func plan(_ collection: RekordboxCollection, fileName: String, sourceRootID: UUID,
                     library: RekordboxLibrarySnapshot) -> RekordboxImportPlan
}
```

Rules, per matched track, producing target values from the row's current ones:
- **BPM and key:** if rekordbox has either, set that field, and `analysisSource = .rekordbox`. A nil rekordbox field keeps the row's value.
- **Rating:** if `ratingSource != .user` and rekordbox has a rating, set it and `.rekordbox`. If `.user` and the values differ, add a `RatingConflict` and keep the row's.
- **Play count, text fields:** mirror rekordbox (nil stays nil). **Beat grid:** `JSONEncoder` with `.sortedKeys` of `beatGrid`, nil when empty.
- A write is emitted only when the target differs from the snapshot. `matched` counts matched tracks; `updated` counts writes.
- **Matching, in two passes so XML order never matters:**
  1. **Path pass**, over all tracks: if the track path has a root's path as a component prefix (compared case-insensitively when `!caseSensitive`), the remainder is the candidate `relativePath`, looked up with the same case rule. Two entries resolving to one row → both `ambiguous`.
  2. **Fallback pass**, only for tracks the path pass left unmatched, and only against rows the path pass did not claim: rows with equal `fileSize` and `abs(duration - track.duration) <= 1`. One candidate wins; several → `ambiguous` (candidates as `root path + relativePath`); none → `unmatched`. Two fallback tracks claiming one row → both `ambiguous`.
- **No longer in rekordbox:** rows with `rootID == sourceRootID` and `analysisSource == .rekordbox` that no track matched, as full paths.
- Zero matches is not an error: the plan has no writes and a report with `matched == 0`.

- [ ] **Step 1: Write failing tests** (hand-built snapshots and collections; no file system):
  - `testMatchesByPath`, `testMatchesThroughSymlinkedRoot` (root path given already resolved; track path resolved to the same), `testMatchesCaseInsensitivelyOnCaseInsensitiveRoot`, `testCaseSensitiveRootDoesNotFoldCase`.
  - `testFallbackBySizeAndDuration` (duration 300.4 vs 301.2 matches; 302.5 does not), `testFallbackIncludesUnavailableRootRows`, `testAmbiguousFallbackNotWritten`, `testDuplicateEntriesForOneFileAreAmbiguous`, `testFallbackCopyBeforePathMatchDoesNotStealRow` (an outside-root entry with the same size and duration listed **before** the row's own path entry → the path entry matches, the copy is unmatched).
  - `testOutsideRootsIsUnmatched`, `testZeroMatchesIsEmptyPlan`.
  - `testRekordboxWinsOverFileTag`, `testMissingRekordboxValueKeepsExisting`.
  - `testRatingFromRekordbox`, `testUserRatingIsConflictNotOverwritten`.
  - `testTextFieldsAndPlayCountMirror`, `testBeatGridEncodedDeterministically`.
  - `testSecondPlanOfSameCollectionHasNoWrites` (apply the first plan's values to the snapshot, plan again → `writes.isEmpty`, `matched` unchanged).
  - `testNoLongerInRekordboxScopedToSourceRoot` (a `.rekordbox` row in another root is not listed).
- [ ] **Step 2: Run `RekordboxImportPlannerTests`.** Expected FAIL.
- [ ] **Step 3: Implement.** Build a `[rootID: [pathKey: row]]` map and a `[fileSize: [row]]` map once; the plan must stay linear in tracks + rows.
- [ ] **Step 4: Run `RekordboxImportPlannerTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: plan rekordbox imports against the library`.

## Task 5: Store: snapshot, sources and apply

**Files:** Create `Sources/Library/LibraryStore+Rekordbox.swift`; modify `LibraryStore+Roots.swift` (remove and relocate), `LibraryValues.swift` (`LibraryChange`), `LibraryEngine.swift` and `LibraryIndex.swift` (exhaustive switches); test `Tests/AmpXTests/LibraryStoreRekordboxTests.swift`.

**Interfaces — consumes:** Task 4's types; `LibraryStore.commit(_:_:)`, `dependencies.now`. **Produces:**

```swift
enum LibraryChange { /* existing */ case rekordboxSourcesChanged }
struct RekordboxFileStamp: Codable, Sendable, Equatable { let size: Int64; let modifiedAt: Date }
struct RekordboxSyncToken: Hashable, Sendable { let rootID: UUID; fileprivate let nonce: UUID }
struct RekordboxSourceSnapshot: Sendable, Equatable {
    let rootID: UUID; let fileName: String; let isPresent: Bool
    let stamp: RekordboxFileStamp?; let lastImportAt: Date?
    let lastReport: RekordboxSyncReport?
}
extension LibraryStore {
    func rekordboxSnapshot() throws -> RekordboxLibrarySnapshot    // every root (available or not) and row
    func rekordboxSources() throws -> [RekordboxSourceSnapshot]
    func beginRekordboxSync(rootID: UUID) throws -> RekordboxSyncToken   // throws .unknownRoot
    func revokeRekordboxSync(rootID: UUID)
    func applyRekordbox(_ plan: RekordboxImportPlan, fileName: String, stamp: RekordboxFileStamp,
                        token: RekordboxSyncToken) throws
    func markRekordboxSourceAbsent(rootID: UUID) throws           // no-op when there is no source or it is already absent
}
```

- `applyRekordbox`, in one `commit(nil)`: check the token equals the active one for its root (else `.revokedToken`) and the root exists (else `.unknownRoot`). Write each `RekordboxRowWrite`'s values, and set `camelotKey = musicalKey.flatMap(CamelotKey.from)`. Upsert the root's `RekordboxSource`: `fileName`, `isPresent = true`, the stamp, `lastImportAt = now()`, `lastReport` (JSON). Publish `.rowsChanged(rootID:)` once per affected root, and `.rekordboxSourcesChanged`. Writes for a row that no longer exists are skipped.
- `removeRoot` deletes the root's `RekordboxSource` in its own transaction, and `removeRoot` and `relocateRoot` call `revokeRekordboxSync(rootID:)` first.
- `LibraryIndex` and `LibraryEngine.follow` treat `.rekordboxSourcesChanged` as a no-op.

- [ ] **Step 1: Write failing tests** (in-memory store, two roots with rows):
  - `testSnapshotIncludesUnavailableRoots`.
  - `testApplyWritesValuesAndDerivesCamelot`, `testApplyUpsertsSourceWithStampAndReport`, `testApplyPublishesPerRootChanges` (a plan touching both roots → one `.rowsChanged` each, plus `.rekordboxSourcesChanged`).
  - `testRevokedTokenWritesNothing`, `testRemoveRootRevokesItsTokenOnly`, `testRelocateRootRevokesToken`.
  - `testRemoveRootDeletesSource`, `testMarkAbsentKeepsValuesAndReport`.
  - `testApplySkipsDeletedRows`.
  - `testFailedSaveRollsBackRowsAndSource` (inject `saveContext` failure).
- [ ] **Step 2: Run `LibraryStoreRekordboxTests`.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `LibraryStoreRekordboxTests LibraryStoreTests LibraryRootTests LibraryChangePublicationTests LibraryEngineTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: store rekordbox sources and imports`.

## Task 6: `RekordboxSync`

**Files:**
- Create: `Sources/Library/Rekordbox/RekordboxSync.swift`.
- Modify: `Sources/Library/LibraryFileSystem.swift` and `Tests/AmpXTests/LibraryScanTestSupport.swift` (`FakeLibraryFileSystem`), `Sources/Library/LibraryScanner.swift` and `LibraryScanner+Scheduling.swift` (exclusive jobs), `Sources/Library/LibraryEngine.swift` (own, start, stop).
- Test: `Tests/AmpXTests/RekordboxSyncTests.swift`; extend `LibraryScanSchedulingTests.swift`, `LibraryFileSystemTests.swift`.

**Interfaces — consumes:** Tasks 1, 4, 5; `LibraryScanner.progress()`. **Produces:**

```swift
struct LibraryTopLevelFile: Sendable, Equatable { let url: URL; let name: String; let stamp: RekordboxFileStamp }
protocol LibraryFileSystem {                      // additions
    func topLevelFiles(in root: URL, pathExtension: String) async throws -> [LibraryTopLevelFile]  // case-insensitive; regular files only
    func readPrefix(of url: URL, length: Int) async throws -> Data
    func readAll(of url: URL) async throws -> Data
}
extension LibraryScanner {
    /// FIFO job alongside root scans: runs when no scan runs; returns when `work` finishes.
    func performExclusive(_ work: @escaping @Sendable () async -> Void) async
}
enum RekordboxSyncStatus: Equatable, Sendable {
    case hidden                        // no present source
    case idle(lastSync: Date?)         // latest lastImportAt across present sources
    case syncing
}
struct RekordboxSyncState: Equatable, Sendable { let status: RekordboxSyncStatus; let sources: [RekordboxSourceSnapshot] }
actor RekordboxSync {
    init(store: LibraryStore, scanner: LibraryScanner, fileSystem: any LibraryFileSystem)
    func start() async                              // subscribes to scanner progress
    func stop() async                               // cancels the subscription; waits for a running job
    func requestCheck(rootID: UUID, force: Bool = false)
    func state() async -> RekordboxSyncState
    func states() -> AsyncStream<RekordboxSyncState>   // current value first, then changes
    func waitUntilIdle() async                          // test and teardown hook
}
actor LibraryEngine { /* existing */ nonisolated let rekordbox: RekordboxSync }   // stored, set in open(_:)
```

Behaviour:
- **Trigger:** on `ScanProgress.phase == .finished`, call `requestCheck(rootID:)`. `requestCheck` adds the root to a pending set; if no job is queued, it enqueues one `scanner.performExclusive` job. While a job runs, new requests stay pending and one follow-up job is enqueued when it ends.
- **Job:** take the pending set. For each root, if it is still available: `topLevelFiles(in: root.url, pathExtension: "xml")` → keep files where `readPrefix(length: RekordboxCollectionParser.sniffLength)` passes `isCollectionExport` (a read error = skip) → pick the newest (tie: name ascending). Then order the roots by their chosen file's `modifiedAt`, oldest first, and handle each:
  - **None found:** `markRekordboxSourceAbsent(rootID:)`.
  - **Unchanged:** same `fileName` and stamp as the stored source, not `force` → nothing.
  - **Otherwise:** `beginRekordboxSync(rootID:)` → `readAll` → parse → `rekordboxSnapshot()` → plan → `applyRekordbox`. A read error is treated as "none found". A parse error writes nothing and is logged: `.error` if the stamp equals the one that failed last time for this root (kept in memory), otherwise `.info`, remembering the stamp. A `.revokedToken` or `.unknownRoot` error is swallowed.
- **Logging:** as in *Global Constraints*. The sync keeps, per root in memory, the stamp that last failed to parse, only to choose `.info` or `.error`.
- **Status:** `.syncing` while a job is between `beginRekordboxSync` and its end; otherwise derived from `rekordboxSources()` after each job and on `.rekordboxSourcesChanged`.
- **Engine:** `LibraryEngine.open` creates the sync and calls `start()` **before** requesting the launch scans, so their `finished` events are seen. `stop()` stops the sync before the scanner.
- The existing root scan already ignores non-audio files; do not change the walk.

- [ ] **Step 1: Write failing tests** (in-memory store, `FakeLibraryFileSystem` extended to serve top-level files with stamps and data, the fixture's data rewritten to point at the fake root's path):
  - `LibraryFileSystemTests`: `testTopLevelFilesListsOnlyTopLevelXml` (temp dir with `a.xml`, `B.XML`, `sub/c.xml`, `d.txt` → `a.xml`, `B.XML`), `testReadPrefixReadsAtMostLength`.
  - `LibraryScanSchedulingTests`: `testExclusiveJobWaitsForRunningScan`, `testScanWaitsForExclusiveJob`, `testExclusiveJobsRunInOrder`.
  - `RekordboxSyncTests`:
    - `testNoXmlDoesNothingAndStaysHidden` (no source row, status `.hidden`, no parse).
    - `testNonRekordboxXmlIgnored`, `testXmlInSubfolderIgnored`, `testNewestExportChosen`.
    - `testAddingRootImports` (add root → scan → rows have rekordbox BPM, source present, status `.idle`).
    - `testUnchangedStampSkipsParse`, `testChangedStampReimportsAfterScan`, `testForceReimportsUnchangedFile` (zero writes).
    - `testExportDisappearsSilently` (source `isPresent == false`, values kept, status `.hidden`).
    - `testTruncatedThenCompleteFileSyncs` (truncated stamp S1 → nothing written, status stays `.hidden`; complete stamp S2 → imported, `.idle`).
    - `testRepeatedParseFailureChangesNoState` (same stamp fails twice → no writes, source unchanged, status unchanged).
    - `testZeroMatchesStoresReportSilently`.
    - `testChecksRunOldestExportFirst` (two roots whose exports share a track → the newer export's BPM wins).
    - `testRemovingRootDuringCheckWritesNothing`, `testOtherRootCheckSurvivesRemoval`.
    - `testStopWaitsForRunningJob`.
    - `testStatesStream` (`.hidden` → `.syncing` → `.idle`).
  - `LibraryEngineTests`: `testLaunchScanTriggersCheck`.
- [ ] **Step 2: Run `RekordboxSyncTests LibraryScanSchedulingTests LibraryFileSystemTests LibraryEngineTests`.** Expected FAIL.
- [ ] **Step 3: Implement.** In the scanner, change the queue element from `UUID` to `enum Job: Hashable { case root(UUID), exclusive(UUID) }`, keeping every existing root rule (one pending entry per root, follow-up collapse, cancel). An exclusive job's id is fresh per call.
- [ ] **Step 4: Run `RekordboxSyncTests LibraryScanSchedulingTests LibraryFileSystemTests LibraryEngineTests LibraryScannerTests LibraryWatcherTests LibraryEngineIntegrationTests LibraryControllerTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: sync rekordbox exports found in library folders`.

## Task 7: UI: indicator, ROOTS lines, report overlay

**Files:**
- Create: `Sources/Modules/Library/LibraryRekordboxReportView.swift`.
- Modify: `LibraryFooterView.swift`, `LibraryRootsMenu.swift`, `LibraryModuleContent.swift`, `LibraryModuleLayout.swift`.
- Test: extend `LibraryChromeTests.swift`, `LibraryRootsMenuTests.swift`, `LibraryModuleContentTests.swift`.

**Interfaces — consumes:** `RekordboxSync.states()`, `RekordboxSyncState`, `RekordboxSyncStatus`, `RekordboxSourceSnapshot`, `RekordboxSyncReport` (Tasks 5–6). **Produces:**

```swift
extension LibraryFooterView {
    func update(/* existing params */, rekordbox: RekordboxSyncStatus)
    static func rekordboxText(_ status: RekordboxSyncStatus, now: Date, calendar: Calendar) -> String?
    // .hidden → nil; .idle(d) → "REKORDBOX HH:mm" when d is today, "REKORDBOX d MMM" otherwise, "REKORDBOX" when nil;
    // .syncing → "REKORDBOX SYNCING"
    var onRekordboxClick: () -> Void
}
struct LibraryRootsMenu.Actions { /* existing */ var viewRekordboxReport: (UUID) -> Void }
static func LibraryRootsMenu.make(roots:, rekordboxSources: [UUID: RekordboxSourceSnapshot], actions:) -> NSMenu
static func LibraryRootsMenu.rekordboxLine(_ source: RekordboxSourceSnapshot, now: Date, calendar: Calendar) -> String
    // "rekordbox: collection.xml · synced 14:30" | "… · synced 3 Sep" | "… · not synced"
@MainActor final class LibraryRekordboxReportView: AmpXView {
    var onClose: () -> Void
    func show(_ report: RekordboxSyncReport)
    static func summary(_ report: RekordboxSyncReport) -> [String]
}
```

- **ROOTS menu:** in a root's submenu, only when it has a source with `isPresent`, after the status line: the disabled `rekordboxLine`, then **View rekordbox Report**.
- **Footer:** the indicator is hidden for `.hidden`. A click opens the report of the most recently synced present source.
- **Report overlay:** covers the track table's frame. Lines, in this order: `"{fileName}"`; `"{matched} of {matched + unmatched + ambiguous} tracks matched"`; `"{updated} updated"`; then, when non-zero, `"{n} not in any library folder"`, `"{n} ambiguous"`, `"{n} rating conflicts"`, `"{n} no longer in rekordbox"`. Below, a scrollable list (`AmpXScrollbar`) of the entries grouped under those headings. One **Close** button; Esc and ↩ close.
- **Wiring:** `LibraryModuleContent` subscribes to `engine.rekordbox.states()` when it attaches a model, keeps the latest state for the footer and the ROOTS menu, and cancels on window close.

- [ ] **Step 1: Write failing tests:**
  - `LibraryChromeTests`: `testRekordboxIndicatorText` (every status, fixed calendar and dates), `testIndicatorHiddenWithoutSources`, `testReportSummaryLines`, `testReportCloseOnEscape`.
  - `LibraryRootsMenuTests`: `testRootWithoutSourceHasNoRekordboxItems`, `testRootWithSourceShowsLineAndReportItem`, `testAbsentSourceHidden`, `testRekordboxLineFormats`.
  - `LibraryModuleContentTests` (engine over a fake file system with an export in the root): `testIndicatorAppearsAfterImport`, `testRootsItemOpensReport`, `testIndicatorClickOpensLatestReport`, `testNoExportShowsNothing`, `testParseFailureShowsNothing`.
- [ ] **Step 2: Run `LibraryChromeTests LibraryRootsMenuTests LibraryModuleContentTests`.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the same suites plus `AmpXLibraryWindowTests LibraryWiringTests`.** Expected PASS.
- [ ] **Step 5: Visual check.** `./build.sh --run`, open the Library with `~/Music/DJ` as a root, then `./scripts/shoot.sh --no-build --index <library window>`: the table with BPM, KEY and CAMELOT filled and the footer `REKORDBOX HH:mm`; then open the report and capture again. Save as `docs/superpowers/plans/rekordbox-sync/capture-synced.png` and `capture-report.png`.
- [ ] **Step 6: Commit** `feat: rekordbox sync status and report in the library`.

## Task 8: Verification

**Files:** Create `Tests/AmpXTests/RekordboxCollectionGateTests.swift`; modify the spec (status, verification section).

- [ ] **Step 1: Write the gate test** (skipped unless `TEST_RUNNER_AMPX_LIBRARY_GATE=1`, using `LibraryGateSupport`): a real engine over a temp store; add root `~/Music/DJ`; wait for the engine and the sync to be idle. Assert:
  - all 2,232 rows have non-nil `bpm`, `musicalKey` and `camelotKey`, with `analysisSource == .rekordbox`;
  - the source's `fileName == "collection.xml"`, and `matched + unmatched.count + ambiguous.count == 2449 - droppedWithoutLocation`;
  - `requestCheck` without `force` on the unchanged file parses nothing;
  - `requestCheck(force: true)` writes nothing and takes < 2 s.

  Emit the counts (including how many of the 217 outside entries fell back or went ambiguous) and the timings with `emitGate`.
- [ ] **Step 2: Run it:** `TEST_RUNNER_AMPX_LIBRARY_GATE=1` with `-only-testing:AmpXTests/RekordboxCollectionGateTests`. Expected PASS. Record the numbers.
- [ ] **Step 3: Manual checks:**
  - Success criterion 2: with AmpX open on the Library, change one track's BPM in rekordbox and re-export over `~/Music/DJ/collection.xml`; the new value shows within 5 s with no clicks. Note the time.
  - Success criterion 3: add a library folder with no export; nothing rekordbox-related appears in the UI.
  - Save a truncated copy as `collection.xml` in a test library folder: no popup or indicator; Console (`category:RekordboxSync`) shows the `.info` line.
- [ ] **Step 4: Run the full suite** with `./scripts/run-tests.sh`. Expected: all pass; any failure outside the rekordbox and library code is re-run alone and reported.
- [ ] **Step 5: Update the spec's status** to Implemented and add a *Verification* section with the gate numbers, the manual results and links to the Task 7 captures. Commit `test: verify rekordbox sync` (docs with `git add -f`).
- [ ] **Step 6: Update PR #15's description** (`gh pr edit 15 -R ratovarius/ampx`): add a *rekordbox sync* subsection under Summary and its test-plan lines, and add "Direct `master.db` reading, on `experimental/rekordbox-db`" to *Known limitations and follow-ups*. Push `feature/music-library`.

## Coverage audit

| Spec section | Task |
|---|---|
| Decisions: discovery, silent when absent, always silent import | 6 |
| Imported data list; key display in two columns | 2, 3, 4 |
| Removal keeps values | 4 (`noLongerInRekordbox`), 5 (`testMarkAbsentKeepsValuesAndReport`), 6 (`testExportDisappearsSilently`) |
| Discovery: when, what, choice, access, none found | 1 (sniff), 6 |
| `LibrarySchemaV2` fields, `RekordboxSource`, migration | 2 |
| Scanner re-parse rule | 2 |
| Parser: Location, attributes, scope, errors | 1 |
| `CamelotKey` | 1 |
| Planner: two-pass matching, only-changed writes, report scoped to root, zero matches | 4 |
| `applyRekordbox` one transaction, token, change publication; source removed with its root | 5 |
| `RekordboxSync`: trigger, turn-taking, collapse, oldest first, stop | 6 |
| UI: columns, search, CAMELOT sort, footer, ROOTS lines, report overlay | 3, 7 |
| Error handling table | 6 (absent, disappeared, mid-write, unreadable, zero, revoked, logging), 7 (nothing shown) |
| Testing table and gate | 1–8 |
| Success criteria 1–5 | 8 (1, 2, 3, 5), 2 (4), 5–6 (5) |
| Future work: `experimental/rekordbox-db` | 8, step 6 (recorded in the PR; no code) |

## Execution handoff

Tasks are sequential: each consumes the previous task's Interfaces block. Tasks 1 and 4 are pure and can be reviewed alone; Tasks 5–6 carry the concurrency risk (per-root tokens, exclusive jobs, launch ordering) and deserve the closest review.

# rekordbox Collection Sync

**Date:** 2026-09-28 · **Revised:** 2026-09-28 (Revision 2: discovery in library folders replaces manual linking)
**Status:** Proposed
**Ships in:** PR #15 (`feature/music-library`), with library L1 and L2.
**Takes over from:** [DJ mode](./2026-09-11-dj-mode-design.md) phase A: the rekordbox import, Camelot conversion, the `LibrarySchemaV2` migration and the scanner re-parse rule. Smart playlists, A-UI's MIXES WELL and phases B/B′ stay in DJ mode.
**Builds on:** [Music Library, Revision 7](./2026-09-11-music-library-design.md) (engine) and [Library Module](./2026-09-27-library-module-design.md) (window).

## Goal

Keep the library's BPM, key and other rekordbox data current with no setup. When a library folder has a rekordbox collection export at its top level, AmpX imports it, and imports it again whenever rekordbox re-exports. When a folder has none, nothing happens and nothing is shown.

## Why the XML

rekordbox keeps its analysis (BPM, key, beatgrid), ratings and play counts in its own database. It never writes them to the audio files: on 2026-09-28 a full analysis of `~/Music/DJ` changed no file. The tags alone give BPM and key for 391 of 2,232 tracks.

The database (`~/Library/Pioneer/rekordbox/master.db`) is encrypted with SQLCipher and its key is not published, so the supported way out is the XML export. Reading the database directly is recorded under *Future work*.

## Measured export (rekordbox 7.2.19, 2026-09-28)

`~/Music/DJ/collection.xml`: 40 MB, 2,449 entries, 217 of them outside `~/Music/DJ`.

| Against the 2,232 audio files in `~/Music/DJ` | Count |
|---|---|
| Matched by path | 2,232 |
| With BPM (`AverageBpm`) | 2,232 |
| With key (`Tonality`, musical notation: `Am`, `F#`, `Dbm`) | 2,232 |
| With a beatgrid (`<TEMPO>`) | 2,232, of which 165 have more than one tempo |
| With cue points | 0 |
| Rated | 5 |

Path matching reaches 2,232 only when both sides are NFC-normalised (53 accented names differ in normal form) and a `#` in `Location` is read as part of the path, not as a URL fragment (2 entries).

## Decisions (user, 2026-09-28)

| Topic | Choice |
|---|---|
| Landing | In PR #15, with the rest of the library |
| Where the XML comes from | **Discovered**, not linked: any `.xml` directly inside a library folder (not in subfolders) that is a rekordbox collection export. No file picker, no manual link |
| No XML found | **Silent.** No error, no warning, no indicator; the sync simply does not run for that folder |
| Applying changes | Always silent, including the first discovery. The last report stays viewable |
| Imported data | BPM, key, Camelot key (derived), rating, beatgrid, label, remixer, composer, grouping, mix, play count |
| Key display | Two columns: KEY (musical, `Am`) and CAMELOT (`8A`) |
| Architecture | A separate `RekordboxSync` component driven by the existing root scans |
| Removal | An XML that disappears, and tracks that leave it, keep their last imported values |
| Direct database access | Future work, on its own experimental branch |

## Non-goals

- Writing anything back to rekordbox or to audio files.
- Creating library rows or roots from the XML. Tracks outside every root are reported, never added.
- Looking for XMLs in subfolders, or outside library folders.
- rekordbox playlists, cue points (none exist in this collection), colours and My Tags.
- Smart playlists and the MIXES WELL recommendations (DJ mode).
- Reading label, remixer, composer, grouping or mix from file tags.

## Discovery

- **When:** after every root scan that reaches its end on an available root (the `finished` progress event), whatever the walk's coverage. Root scans already run when a folder is added, at launch for each available root, and after every FSEvents batch under the root. So a re-export, which changes a file at the root's top level, triggers discovery with no extra watcher.
- **What:** list the root's top-level entries whose extension is `xml` (any case). For each, read at most the first 4 KB and accept it only if it contains `<DJ_PLAYLISTS` and a `PRODUCT` element with `Name="rekordbox"`. Anything else, including files that cannot be read, is skipped without a trace.
- **Choice:** if several files qualify, the one with the newest modification date is used; ties go to the name that sorts first.
- **Access:** the root's security scope, which `LibraryStore` already holds, covers files at its top level. No bookmark is stored for the XML.
- **None found:** if the root had a source before, it is kept as it was (its values, report and stamp) but marked `isPresent = false`, and nothing runs. No status is shown for it.

## Data model: `LibrarySchemaV2`

A lightweight migration from `LibrarySchemaV1` under the existing `LibraryMigrationPlan`. Every new field is optional or defaulted.

`LibraryTrack` gains:

| Field | Source | Rule |
|---|---|---|
| `analysisSource: AnalysisSource?` | — | `.fileTag` or `.rekordbox`; nil when `bpm` and `musicalKey` are both nil. Precedence: `rekordbox` over `fileTag` |
| `bpm`, `musicalKey` (existing) | `AverageBpm`, `Tonality` | `musicalKey` stores the key as rekordbox writes it |
| `camelotKey: String?` | derived | Recomputed from `musicalKey` whenever it changes, whatever the source. nil for an unknown spelling |
| `beatGrid: Data?` | `<TEMPO Inizio Bpm Metro Battito>` | A Codable list of `(start, bpm, meter, beat)`, stored for DJ mode's auto-mix. Not displayed |
| `label`, `remixer`, `composer`, `grouping`, `mix: String?` | same-named attributes | rekordbox only; an empty attribute stores nil |
| `rating` (existing) | `Rating` 0–255 → 0–5 (`/ 51`, rounded) | See `ratingSource` |
| `ratingSource: RatingSource?` | — | `.rekordbox` or `.user`. A sync updates `rating` only while the source is nil or `.rekordbox`. AmpX has no rating UI yet; when it arrives it sets `.user`, and a differing rekordbox rating is then a reported conflict |
| `rekordboxPlayCount: Int` | `PlayCount` | Default 0, replaced on each sync. Kept apart from AmpX's `playCount` so re-syncs never double-count |

A new model, `RekordboxSource`, holds at most one record per root:
- `rootID` (unique), the chosen XML's `fileName`, and `isPresent`;
- the file's `(size, modificationDate)` at the last successful import, and when that import happened;
- the last report (see below), Codable, and the last error, if any.

Removing a root deletes its `RekordboxSource`; the rows go with the root, as today.

`LibraryRow` gains `camelotKey`, `label`, `remixer`, `composer`, `grouping` and `mix` for display and search.

### Scanner re-parse rule

The scanner re-parses a file when its `(size, mtime)` changes. From V2 it writes `bpm` and `musicalKey` from tags **only** when `analysisSource != .rekordbox`, and then sets `analysisSource = .fileTag` (or nil if both are empty). Without this rule, any external tag edit would put tag values back over imported ones.

## Components

### `RekordboxCollectionParser` (pure)

This streams the XML with Foundation's `XMLParser` and returns `[RekordboxTrack]`. The file is 40 MB, so it is never loaded as a DOM.

- **Location:** strip `file://localhost`, then percent-decode the remaining path literally, so a `#` stays part of the name. Then standardise, resolve symlinks and NFC-normalise it.
- **Attributes:** each is read on its own. A missing or malformed attribute makes that field nil, and the track still parses. A `TRACK` without a usable `Location` is dropped and counted.
- **Scope:** only `DJ_PLAYLISTS/COLLECTION/TRACK` is read. `PLAYLISTS` is skipped.
- **Errors:** an XML error aborts the parse with the parser's line and message. There is no partial result.

A second entry point, `isCollectionExport(prefix: Data) -> Bool`, implements the 4 KB sniff used by discovery.

### `CamelotKey` (pure)

This maps the 24 musical keys to Camelot codes (`Am` → `8A`, `C` → `8B`). It accepts the spellings rekordbox uses (`Abm`, `F#m`, `Db`, `Bbm`), their enharmonic equivalents, and `♯`/`♭`. Anything else maps to nil.

### `RekordboxImportPlanner` (pure)

Input: the parsed tracks, the source's root id, plus a snapshot of each row's key, the resolved root URLs and the current values of every imported field. Output: a `RekordboxImportPlan`, made of `writes` and `report`.

- **Matching, in two passes, so XML order never matters:**
  1. **Path pass:** the track's path is matched to a root plus `relativePath`, the library's row key. Root paths are NFC-normalised too, and compared case-insensitively on case-insensitive volumes.
  2. **Fallback pass:** only for tracks the path pass left unmatched, and only against rows it did not claim, match on `(fileSize, duration ±1 s)` across all rows, including rows in unavailable roots.
  3. More than one candidate, or two entries claiming one row, is **ambiguous** and is never written. No candidate means **unmatched**.
- **Writes** contain only fields that differ from the row, so running the same file twice writes nothing.
- **Precedence:** BPM and key are written when rekordbox has a value. A missing rekordbox value never clears an existing one.
- **Report:** matched, updated, unmatched (with path), ambiguous (with candidates) and rating conflicts. It also lists rows **in the source's root** that were imported before (`analysisSource == .rekordbox`) but are no longer in the XML, as "no longer in rekordbox". Those rows keep their values.
- **Zero matches** writes nothing. The report is kept, and nothing is shown: an export of an unrelated collection is not an error.

### `LibraryStore.applyRekordbox(_:rootID:stamp:token:)`

One transaction, saved only if the sync token is still valid (the scan-token rule). It writes the rows and updates the root's `RekordboxSource`, then publishes a `LibraryChange`, so `LibraryIndex` refreshes through the existing path.

### `RekordboxSync` (owned by `LibraryEngine`)

- It listens to the scanner's progress. On `finished` for an available root, it queues a check for that root.
- **Check:** discovery, as above. No qualifying file → mark the source not present (if one exists) and stop. A qualifying file whose `(fileName, size, modificationDate)` equals the stored source → nothing to do. Otherwise parse and plan off the main thread, then apply.
- **Turn-taking with scans:** a check is one more job kind in the scanner's FIFO (at most one pending per root). It never runs during a scan, and a scan never runs during it, so neither plans against a stale snapshot. Checks requested while one is queued or running for the same root collapse into one follow-up.
- **Several roots with exports:** each check matches its XML against the whole library. When checks for several roots are due together (at launch), they run in order of the files' modification dates, oldest first, so the newest export wins for tracks two exports share.
- **Stop:** `LibraryEngine.stop()` revokes the sync's token and waits for it, as it does for scans. Removing or relocating a root cancels its pending check.

## UI

In the Library window, custom-drawn like the rest of it. Nothing about rekordbox appears for a library with no rekordbox export.

- **Columns:**
  - KEY shows `musicalKey`. A new CAMELOT column is visible by default.
  - LABEL, REMIXER, COMPOSER, GROUPING and MIX are new and hidden by default.
  - CAMELOT sorts by number, then A before B, with empty values last.
  - Minimum widths keep the default set inside the 910 pt minimum window.
- **Search** also matches label, remixer, composer, grouping and mix.
- **Footer:** a rekordbox indicator next to the scan status, shown only while at least one present source exists. It reads `REKORDBOX 14:30` (latest sync), `REKORDBOX SYNCING` or `REKORDBOX ⚠`. Clicking it opens the report.
- **ROOTS menu:** in a root's submenu, only when it has a present source, a disabled line `rekordbox: collection.xml · synced 14:30`, and **View rekordbox Report**.
- **Report overlay:** it is drawn over the table, with the counts and a scrollable list (`AmpXScrollbar`) of unmatched, ambiguous, rating-conflict and "no longer in rekordbox" entries, plus the error when there is one. It has one button, **Close**.

## Error handling

| Case | Behaviour |
|---|---|
| No `.xml`, or no rekordbox export, at a root's top level | Silent: no sync, no indicator, no message |
| The export disappears later | Silent: the source is marked not present, values stay, the indicator goes away |
| Export still being written, or malformed XML | The parse fails and nothing is written. The write's completion triggers another FSEvents batch, scan and check. Only if the same `(size, modificationDate)` fails twice does the footer show ⚠, and the report shows the parser error |
| A qualifying file cannot be read (permission) | Treated like no file: silent |
| Engine stopping, or the root removed or relocated, during a check | The token is revoked and nothing is written |
| Track outside all library folders | Reported as unmatched |
| Zero matches | Nothing written; report kept; silent |
| Store from a newer schema | The existing L1 behaviour: the engine does not open and the Library shows its error state |

## Testing

| Suite | Covers |
|---|---|
| `RekordboxCollectionParserTests` | A fixture trimmed from the real 7.2.19 export (~20 tracks): the `#` path, NFD accented names, a variable-tempo grid, a track outside the roots, missing attributes, `PLAYLISTS` skipped, a truncated file failing with no result; `isCollectionExport` accepts the fixture's first 4 KB and rejects an iTunes `Library.xml` header, an empty file and a non-XML file |
| `CamelotKeyTests` | All 24 keys, rekordbox spellings, enharmonics, `♯`/`♭`, and unknown values → nil |
| `RekordboxImportPlannerTests` | Path match, the fallback, ambiguity, only-changed writes, a second run writing nothing, rating sources and conflicts, "no longer in rekordbox" scoped to the root, and zero matches writing nothing |
| `LibraryMigrationTests` | A V1 store opens as V2 with every value kept and the new fields defaulted |
| `LibraryScannerTests` (added cases) | After an import, a changed mtime re-parses tags without replacing rekordbox BPM and key; a `.fileTag` value is refreshed |
| `RekordboxSyncTests` | Fake file system: no XML → nothing and no status; a non-rekordbox XML ignored; the newest of two exports chosen; an XML in a subfolder ignored; an unchanged file → no parse; a changed file applied after its root's scan; a disappearing file marks the source not present silently; a truncated file retried and ⚠ only after two failures of one stamp; turn-taking with scans; checks for several roots in modification order; a revoked token writes nothing |
| `LibraryColumnsTests`, `LibraryTrackTableViewTests`, `LibraryChromeTests`, `LibraryRootsMenuTests` (added cases) | The new columns and their defaults, CAMELOT sort, the footer indicator states and its absence, the ROOTS lines, the report overlay |
| `RekordboxCollectionGateTests` (opt-in, `TEST_RUNNER_AMPX_LIBRARY_GATE=1`, skipped on CI) | Adding `~/Music/DJ` as a root discovers `collection.xml` and fills all 2,232 tracks; a re-check of the unchanged file parses nothing; a forced re-sync of the unchanged file writes nothing and takes < 2 s |

## Success criteria

1. Adding `~/Music/DJ` as a library folder fills BPM, KEY and CAMELOT for all 2,232 tracks, with no other step.
2. A re-export from rekordbox into `~/Music/DJ` is reflected in AmpX within 5 s, with no clicks.
3. A library folder without a rekordbox export shows nothing rekordbox-related, and logs no error.
4. Editing a file's tags in another app does not replace its imported BPM or key.
5. A re-sync of an unchanged export writes nothing, and deleting the export loses no imported value.

## Files expected to change

- **New:** `Sources/Library/Rekordbox/RekordboxCollectionParser.swift`, `CamelotKey.swift`, `RekordboxImportPlanner.swift`, `RekordboxSync.swift`; `Sources/Library/LibrarySchemaV2.swift`; `Sources/Library/LibraryStore+Rekordbox.swift`; the report overlay view in `Sources/Modules/Library/`; a test fixture `Tests/AmpXTests/Fixtures/rekordbox-collection.xml`.
- **Changed:** `LibrarySchemaV1.swift` (migration plan), `LibraryStore.swift` (the re-parse rule), `LibraryStore+Roots.swift` (remove the source with its root), `LibraryFileSystem.swift` (top-level XML listing and prefix read), `LibraryScanner+Scheduling.swift` (the check job kind), `LibraryEngine.swift`, `LibraryValues.swift` (`LibraryRow`), `LibraryIndex.swift` / `LibraryQuery.swift` (search fields, CAMELOT sort), `LibraryColumns.swift`, `LibraryFooterView.swift`, `LibraryRootsMenu.swift`, `LibraryModuleContent.swift`.
- **Docs:** the DJ mode spec notes that phase A's import, Camelot conversion, V2 migration and re-parse rule moved here.

## Future work: read rekordbox's database directly (experimental)

Tracked as a separate task, **not part of PR #15**.

- **Branch:** `experimental/rekordbox-db`, from `develop` after PR #15 merges. It does not merge into `develop` until it has proved stable across rekordbox updates, and then only behind a setting that is off by default.
- **What:** a `RekordboxDatabaseSource` that produces the same `[RekordboxTrack]` as the parser, so the planner, the writer and the UI are reused unchanged. Syncing would then need no export.
- **How:**
  - Bundle SQLCipher.
  - Copy `master.db` plus its `-wal` to a temporary folder and open the copy read-only. The live file is never opened.
  - Access to `~/Library/Pioneer/rekordbox` is granted once through an open panel, then bookmarked.
- **Risks:**
  - The key is not published by AlphaTheta; community tools such as `pyrekordbox` use an extracted one.
  - A rekordbox update can change the key or the schema without notice.
  - It may conflict with rekordbox's licence terms, which must be checked before any release.
  - The XML sync stays the supported path, and this source falls back to it on any failure.

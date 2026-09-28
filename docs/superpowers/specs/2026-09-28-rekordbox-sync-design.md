# rekordbox Collection Sync

**Date:** 2026-09-28
**Status:** Proposed
**Ships in:** PR #15 (`feature/music-library`), with library L1 and L2.
**Takes over from:** [DJ mode](./2026-09-11-dj-mode-design.md) phase A: the rekordbox import, Camelot conversion, the `LibrarySchemaV2` migration and the scanner re-parse rule. Smart playlists, A-UI's MIXES WELL and phases B/B′ stay in DJ mode.
**Builds on:** [Music Library, Revision 7](./2026-09-11-music-library-design.md) (engine) and [Library Module](./2026-09-27-library-module-design.md) (window).

## Goal

Keep the library's BPM, key and other rekordbox data current without manual steps. The user links rekordbox's `collection.xml` once. After that, each *File ▸ Export Collection in xml format* in rekordbox shows up in AmpX within seconds.

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
| Applying changes | The first link shows the report and waits for **Import**. Every later change applies silently; the last report stays viewable |
| Imported data | BPM, key, Camelot key (derived), rating, beatgrid, label, remixer, composer, grouping, mix, play count |
| Key display | Two columns: KEY (musical, `Am`) and CAMELOT (`8A`) |
| Architecture | A separate `RekordboxSync` component (not a scanner root, not launch-only polling) |
| Removal | Tracks that leave the XML, and unlinking, keep their last imported values |
| Direct database access | Future work, on its own experimental branch |

## Non-goals

- Writing anything back to rekordbox or to audio files.
- Creating library rows or roots from the XML. Tracks outside every root are reported, never added.
- rekordbox playlists, cue points (none exist in this collection), colours and My Tags.
- Smart playlists and the MIXES WELL recommendations (DJ mode).
- Reading label, remixer, composer, grouping or mix from file tags.

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

A new model, `RekordboxLink` (at most one), stores:
- the XML's security-scoped bookmark and display path;
- the file's `(size, modificationDate)` at the last successful import, and when that import happened;
- `firstImportConfirmed`;
- the last report (see below), Codable;
- the last error, if any.

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

### `CamelotKey` (pure)

This maps the 24 musical keys to Camelot codes (`Am` → `8A`, `C` → `8B`). It accepts the spellings rekordbox uses (`Abm`, `F#m`, `Db`, `Bbm`), their enharmonic equivalents, and `♯`/`♭`. Anything else maps to nil.

### `RekordboxImportPlanner` (pure)

Input: the parsed tracks, plus a snapshot of each row's key, the resolved root URLs and the current values of every imported field. Output: a `RekordboxImportPlan`, made of `writes` and `report`.

- **Matching:**
  1. The track's path is matched to a root plus `relativePath`, the library's row key. Root paths are NFC-normalised too.
  2. Otherwise it falls back to `(fileSize, duration ±1 s)` across all rows, including rows in unavailable roots.
  3. More than one candidate is **ambiguous** and is never written.
  4. No candidate means **unmatched**.
- **Writes** contain only fields that differ from the row, so running the same file twice writes nothing.
- **Precedence:** BPM and key are written when rekordbox has a value. A missing rekordbox value never clears an existing one.
- **Report:** matched, updated, unmatched (with path), ambiguous (with candidates) and rating conflicts. It also lists rows imported before (`analysisSource == .rekordbox`) whose track is no longer in the XML, as "no longer in rekordbox". Those rows keep their values.
- **Zero matches** is an error, never applied, so linking the wrong file can't pass silently.

### `LibraryStore.applyRekordbox(_:token:)`

One transaction, saved only if the token is still valid (the scan-token rule). It publishes a `LibraryChange`, so `LibraryIndex` refreshes through the existing path.

### `RekordboxSync` (owned by `LibraryEngine`)

- It resolves the `RekordboxLink` bookmark and holds its security scope while the engine is open.
- It watches the XML's **parent folder** with an FSEvents stream, the same code path as `LibraryWatcher`. rekordbox replaces the file on export, so a watch on the file alone would be lost.
- It checks once when the engine opens, to catch exports made while AmpX was closed.
- **Debounce:** a check runs 2 s after the last event. It compares the file's `(size, modificationDate)` with `RekordboxLink`. Equal means nothing to do.
- **Run:** parsing and planning run off the main thread. Unless it is the first link, the plan is applied with `applyRekordbox`.
- **Turn-taking with scans:** a sync is one more job kind in the scanner's FIFO (at most one pending). It never runs during a scan, and a scan never runs during it, so neither plans against a stale snapshot. Syncs requested during a sync collapse into one follow-up, like root rescans.
- **Stop:** `LibraryEngine.stop()` revokes the sync's token and waits for it, as it does for scans.

### First link

1. *File ▸ Link rekordbox Collection…* (also in the ROOTS menu) opens an `NSOpenPanel` limited to `.xml`. This opens the engine if it isn't open yet.
2. The sync runs parse and plan, then shows the report overlay with **Import** and **Cancel**.
3. **Import** applies the plan and sets `firstImportConfirmed`. **Cancel** discards the link.
4. After that, changes apply without asking.

## UI

In the Library window, custom-drawn like the rest of it.

- **Columns:**
  - KEY shows `musicalKey`. A new CAMELOT column is visible by default.
  - LABEL, REMIXER, COMPOSER, GROUPING and MIX are new and hidden by default.
  - CAMELOT sorts by number, then A before B, with empty values last.
  - Minimum widths keep the default set inside the 910 pt minimum window.
- **Search** also matches label, remixer, composer, grouping and mix.
- **Footer:** a rekordbox indicator next to the scan status, shown only while linked. It reads `REKORDBOX 14:30` (last sync), `REKORDBOX SYNCING` or `REKORDBOX ⚠`. Clicking ⚠ opens the report with the error.
- **ROOTS menu:** a rekordbox section with the linked path, the last sync time, *Sync Now*, *View Last Sync*, *Relink…* and *Unlink*. The same items appear under *File*.
- **Report overlay:** it is drawn over the table, with the counts and a scrollable list (`AmpXScrollbar`) of unmatched, ambiguous, rating-conflict and "no longer in rekordbox" entries. Buttons are **Import** and **Cancel** on the first link, and **Close** otherwise.

## Error handling

| Case | Behaviour |
|---|---|
| XML deleted or moved | The library is unchanged. ⚠ "file missing" is shown; the next event in the folder retries |
| Export still being written, or malformed XML | The parse fails and nothing is written. One retry runs after the next debounce; if it fails again, ⚠ shows the parser error |
| Bookmark stale or scope denied | ⚠ plus *Relink…* |
| Engine stopping, or a root removed, during a sync | The token is revoked and nothing is written |
| Track outside every root | Reported as unmatched |
| Zero matches | Error; nothing is applied, even after the first link |
| Store from a newer schema | The existing L1 behaviour: the engine does not open and the Library shows its error state |

## Testing

| Suite | Covers |
|---|---|
| `RekordboxCollectionParserTests` | A fixture trimmed from the real 7.2.19 export (~20 tracks): the `#` path, NFD accented names, a variable-tempo grid, a track outside the roots, missing attributes, `PLAYLISTS` skipped, and a truncated file failing with no result |
| `CamelotKeyTests` | All 24 keys, rekordbox spellings, enharmonics, `♯`/`♭`, and unknown values → nil |
| `RekordboxImportPlannerTests` | Path match, the fallback, ambiguity, only-changed writes, a second run writing nothing, rating sources and conflicts, "no longer in rekordbox", and zero matches as an error |
| `LibraryMigrationTests` | A V1 store opens as V2 with every value kept and the new fields defaulted |
| `LibraryScannerTests` (added cases) | After an import, a changed mtime re-parses tags without replacing rekordbox BPM and key; a `.fileTag` value is refreshed |
| `RekordboxSyncTests` | Fake file system and clock: a burst of events → one sync; an unchanged file → none; turn-taking with scans; a revoked token writes nothing; the launch check; the first link waits for confirmation |
| `LibraryColumnsTests`, `LibraryTrackTableViewTests`, `LibraryChromeTests` (added cases) | The new columns and their defaults, CAMELOT sort, the footer indicator states, the report overlay buttons |
| `RekordboxCollectionGateTests` (opt-in, `TEST_RUNNER_AMPX_LIBRARY_GATE=1`, skipped on CI) | The real `~/Music/DJ/collection.xml` matches 2,232 of 2,232; a re-sync of the unchanged file writes nothing and takes < 2 s |

## Success criteria

1. After linking `~/Music/DJ/collection.xml`, all 2,232 tracks in `~/Music/DJ` show BPM, KEY and CAMELOT.
2. A re-export from rekordbox is reflected in AmpX within 5 s, with no clicks.
3. Editing a file's tags in another app does not replace its imported BPM or key.
4. A re-sync of an unchanged export writes nothing.
5. Unlinking, or removing a track from rekordbox, loses no imported value.

## Files expected to change

- **New:** `Sources/Library/Rekordbox/RekordboxCollectionParser.swift`, `CamelotKey.swift`, `RekordboxImportPlanner.swift`, `RekordboxSync.swift`; `Sources/Library/LibrarySchemaV2.swift`; the report overlay view in `Sources/Modules/Library/`; a test fixture `Tests/AmpXTests/Fixtures/rekordbox-collection.xml`.
- **Changed:** `LibrarySchemaV1.swift` (migration plan), `LibraryStore.swift` (`applyRekordbox`, the re-parse rule), `LibraryScanner+Scheduling.swift` (the sync job kind), `LibraryEngine.swift`, `LibraryValues.swift` (`LibraryRow`), `LibraryIndex.swift` / `LibraryQuery.swift` (search fields, CAMELOT sort), `LibraryColumns.swift`, `LibraryFooterView.swift`, `LibraryRootsMenu.swift`, `AmpXMenuCatalog.swift`.
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

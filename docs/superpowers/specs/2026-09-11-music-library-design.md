# Music Library (Index, Scanner, Browser Module)

**Date:** 2026-09-11 · **Revised:** 2026-09-15
**Status:** Revision 5 — addresses the [Revision 4 review](./2026-09-11-music-library-design-review.md) (see *Revision log* at the end)
**Related:** [AmpX UI design, Revision 7](./2026-09-11-ampx-ui-design.md) (host for the browser module)
**Successor specs:** DJ mode ([2026-09-11-dj-mode-design.md](./2026-09-11-dj-mode-design.md)) depends on this one.

## Goal

Give the app a **persistent, searchable music library** so it can be the daily driver for a ~2,200-track curated collection (and an ~11,000-file archive) instead of a "open a folder, press play" playlist tool.

Today `Track` carries `title / artist / duration / fileSize / url` and nothing else; a grep for genre, album, BPM or key across `Sources/` returns only ReplayGain's album-gain handling. `PlaylistManager` is a flat `[Track]` with M3U + bookmark persistence. There is no index, no browse, no search, no re-scan.

## Non-goals

- BPM/key analysis, rekordbox import, smart playlists, crossfade — all deferred to the DJ-mode spec
- Replacing `PlaylistManager` or the M3U/bookmark persistence that already works
- **User-facing tag editing** — no UI for correcting an artist, no bulk retag (separate spec later). Write-back of *computed* BPM/key is owned by the DJ-mode spec; nothing in this spec ever opens an audio file for writing
- **Updating play history or ratings** — `playCount`, `lastPlayedAt` and `rating` are stored and preserved but nothing in this spec writes them (see *Reserved fields*)
- A Classic-skin (275 px) browser panel — the browser is built only for the new UI (see *Delivery phases*)
- Artwork browsing / album-grid view
- Tracking a file moved **between** two watched roots (it becomes a missing row plus a new row)
- Tracking renames that the rename rule cannot prove (see *Known limitations*)
- De-duplicating identical audio at different paths
- Network sources, streaming, cloud sync
- Any third-party SPM package, including tag parsers

## Delivery phases

The UI design (Revision 7) retires the Classic skin and lists Library as out of scope for the cutover. This spec therefore ships in two phases so the browser is never built twice:

| Phase | When | Contents | User-visible |
|---|---|---|---|
| **L1 — Engine** | Now, independent of the UI cutover | Metadata gate, bookmark primitive, SwiftData schema, store, scanner, reconciler, watcher, index/query, `LibraryBrowserModel`, all tests | **No.** Nothing in the app target instantiates `LibraryStore` until L2, so no scanning cost ships without a UI |
| **L2 — Browser module** | After the AmpX UI cutover lands | `Library` module in the AppKit/Core Graphics host, menu commands, key routing, root management UI, app wiring | Yes |

L2 requires an amendment to the UI design spec (listed under *Browser module*). L2 planning must not start until that amendment is accepted.

## Decisions (locked)

| Topic | Choice |
|---|---|
| Persistence | **SwiftData** (Apple framework, no SPM dependency). The macOS 26.4 deployment target is well past its availability floor, including `#Index` / `#Unique`. |
| Model split | `@Model` types are **storage only**. Views see `LibraryRow` snapshots; `PlaylistManager` sees `Track`. `Track` is **unchanged** by this spec. |
| Row identity | Each row has a stable `id: UUID`. A row belongs to exactly one root (`rootID`) and owns one `relativePath` within it. **Same path = same track**: a file found at a row's path is that row, even if its contents were replaced (re-download, tag editor atomic save). |
| Path comparison | Paths are compared by a **path key**: Unicode NFC, plus case folding when the root's volume is case-insensitive (`volumeSupportsCaseSensitiveNamesKey`). On a case-insensitive volume a case-only rename is a path match; on a case-sensitive volume it is an ordinary rename. |
| Rename detection | **Content-confirmed, decided only by complete walks.** A missing row and a new file are candidates when they share `(fileSize, contentModifiedAt)` — which a rename preserves on every file system — and that pair is unambiguous: exactly one file in the current walk and exactly one unmatched row carry it. The move happens only if the file's **content fingerprint** equals the row's stored one. No file-system identifiers are stored. |
| What a move guarantees | Reserved fields move only to a file with the same size, modification date and content fingerprint. A different file lifetime that is identical in all three is treated as the same track — consistent with "same path = same track". Every other case yields a missing row plus a new row. |
| Path uniqueness | **A scanner invariant, not a SwiftData constraint.** `#Unique`/`.unique` in SwiftData *upserts* on collision — it would silently overwrite a row and its rating/play count instead of rejecting the write. Only `id` is `.unique`. Broken invariants are repaired by an explicit merge (scan step 1). |
| Staleness | `(fileSize, contentModificationDate)` — tags and fingerprint are recomputed only when either changes. Availability (`isMissing`) is updated independently of staleness. |
| Coverage | A walk ends **complete**, **partial** (some folders unreadable) or **aborted** (cancelled, access lost). Missing flags are decided only for covered locations; **moves only on complete walks**; an aborted walk saves nothing further. |
| Scan tokens | Every scan run holds a store-issued token. Cancellation, unmount, access loss, relocation and removal **revoke** it, and the store rejects every save carrying a revoked token. Late saves are rejected by the store, not prevented by cooperative cancellation. |
| Change publication | `LibraryStore` publishes a typed `LibraryChange` after **every** committed save — scan batches, availability, relocation, removal — never only at scan completion. |
| Schema versioning | Every `@Model` lives under a `VersionedSchema`; the container is opened with a `SchemaMigrationPlan`. **`LibrarySchemaV1` ships with this spec** so the DJ-mode spec's added fields are a `V1 → V2` lightweight migration. |
| Key notation | `musicalKey` stores the key **as tagged** (classical, e.g. `Am`), normalised only for case/spacing. Camelot is added by the DJ-mode spec as `camelotKey`. |
| Bookmarks | Only **roots** have bookmarks. Creation/resolution/refresh moves into a shared internal primitive that `SecurityScopedBookmarkStore` also uses; the store's behaviour is unchanged. No second bookmark implementation. |
| Watched roots | A user-managed, persisted set (`LibraryRoot`). `~/Music/DJ` is the expected first root. Roots may not nest or overlap — enforced on **Add and Relocate**. A root does not cross into other volumes mounted beneath it. |
| Scan unit | **Always a full root.** A no-change root walk is `stat`-only (prefetched resource values) and reads no file contents, which fits the budget for the target collection sizes. Subtree-scoped scanning is deferred; if the L1 gate shows the 11k budget is missed, it returns as a spec amendment, not a planning-time improvisation. |
| Live updates | **FSEvents**, 2 s latency. Any event under a root requests a full scan of that root. |
| Query path | Search and facets run against an **in-memory row snapshot** on its own actor, never through the writer. Queries do not wait for scan commits. |
| Observation | `LibraryBrowserModel` is a `@MainActor` `ObservableObject` with `@Published` state, matching the codebase and the UI spec's per-module Combine subscription rule. |
| Genre source | The file's existing genre tag. No inference. |
| Missing files | Rows are **kept and flagged**, never silently deleted. Only an explicit, confirmed *Remove Root*, or the merge of rows that already share one path, deletes rows. |

## Problem (root cause)

`TrackMetadataLoader.load(from:)` asks `AVAsset` for four values and discards the rest. Nothing persists between launches, so every playlist is rebuilt from M3U paths and every launch re-parses whatever it is handed. There is no structure that can answer "show me Techno between 128 and 132 BPM at 320 kbps", which is the actual daily need.

A relevant free win: every file under `~/Music/DJ` already carries a genre tag equal to its crate name (17 crates). A scan that reads genre reproduces the entire crate structure as facets with no extra work.

## Architecture

### Layers

```
FSEvents / mount notifications ──► LibraryWatcher
                                         │ requestScan(rootID)
                                         ▼
                                  LibraryScanner (actor, .utility)
                                         │ walk (LibraryFileSystem) → LibraryReconciler → parse
                                         │ value-type change sets + scan token
                                         ▼
                                  LibraryStore (@ModelActor, sole writer, token validation)
                                         │ LibraryChange after every save (AsyncStream)
                                         ▼
                                  LibraryIndex (actor, own ModelContext, in-memory [LibraryRow])
                                         │ LibraryQuery → LibraryResult
                                         ▼
                             LibraryBrowserModel (@MainActor, ObservableObject)
                                         │ rows, facets, selection, progress, roots
                                         ▼
                             LibraryModuleContent (L2) ──enqueue──► PlaylistManager
```

`PlaylistManager` is downstream only: it receives `[Track]` built at enqueue time and does not know the library exists.

`LibraryFileSystem` is a protocol over enumeration, volume capabilities and fingerprint reads; the production implementation wraps `FileManager` and `FileHandle`. `LibraryReconciler` is a **pure function** from row keys, walk entries, coverage and a fingerprint provider to a plan. Together they let tests simulate hard links, copies with preserved dates, unreadable folders, interrupted batches and colliding size/date pairs that real test disks cannot produce on demand.

### Models (`LibrarySchemaV1`)

#### `LibraryRoot`

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | `.unique` |
| `bookmark` | `Data` | security-scoped folder bookmark; refreshed when resolution reports stale |
| `displayPath` | `String` | last resolved path, for UI |
| `isAvailable` | `Bool` | false when the bookmark does not resolve, access cannot start, the folder is absent, or its volume unmounted |
| `unreadableFolderCount` | `Int` | folders the last walk could not read; shown in root status |
| `addedAt` | `Date` |  |
| `lastCompletedScanAt` | `Date?` | set only by a **complete** walk |

#### `LibraryTrack`

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | `.unique`; stable row identity, used by `LibraryRow.id` and selection |
| `rootID` | `UUID` | owning root |
| `relativePath` | `String` | path within the root, as last spelled by the enumerator. Its path key is unique per `rootID` by scanner invariant. Kept while missing (last-known location) |
| `schemaVersion` | `Int` | stamped per row so a partially migrated container is detectable |
| `title`, `artist` | `String` | see *Metadata precedence*; never empty |
| `album`, `albumArtist` | `String` | `""` when untagged |
| `genre` | `String?` | crate name for `~/Music/DJ` files |
| `year` | `Int?` |  |
| `trackNumber` | `Int?` |  |
| `duration` | `Double` | seconds; 0 when unreadable |
| `fileSize` | `Int64` | staleness key; half of the rename candidate key |
| `contentModifiedAt` | `Date` | staleness key; half of the rename candidate key |
| `contentFingerprint` | `Data?` | SHA-256 (CryptoKit) over the file size as 8-byte little-endian, the first `min(64 KiB, size)` bytes and the last `min(64 KiB, size)` bytes. Computed whenever the file is parsed; nil when the read failed. A row with nil never moves |
| `bitrate` | `Int` | bits/sec, 0 when unknown |
| `bitrateIsDerived` | `Bool` | true when computed as `fileSize * 8 / duration` rather than reported — a VBR average, so thresholds near it need slack (the DJ-mode "Gig-ready" filter depends on this) |
| `sampleRate` | `Int` | 0 when unknown |
| `channels` | `Int` | 0 when unknown |
| `codec` | `String` | lowercased file type from the extension, `aif` normalised to `aiff`: `mp3` / `flac` / `wav` / `aiff` / `m4a` |
| `bpm` | `Double?` | read from TBPM if present; DJ-mode spec fills the rest |
| `musicalKey` | `String?` | read from TKEY if present, stored as tagged (`Am`, `F#m`) |
| `comment` | `String?` |  |
| `dateAdded` | `Date` |  |
| `lastPlayedAt` | `Date?` | reserved |
| `playCount` | `Int` | reserved |
| `rating` | `Int` | reserved; 0–5, 0 = unrated |
| `isMissing` | `Bool` | true when a walk that **covered** the row's location did not find the file |

Indexes: `#Index<LibraryTrack>([\.rootID], [\.rootID, \.relativePath])`. Facet and search indexes are unnecessary because queries run in memory; the DJ-mode V2 schema may add them.

**Effective availability** of a row is `!isMissing && root.isAvailable`. An unavailable root does **not** flip its rows' `isMissing`; that keeps "drive unplugged" distinct from "file deleted" and makes remounting free.

#### Reserved fields

`playCount`, `lastPlayedAt` and `rating` exist in V1 only so a later play-history/rating spec does not need its own migration. In this spec they are preserved across rename, content change, missing → found, root relocation and duplicate merge, and nothing in this spec writes them (tests aside). Their first writer is the DJ-mode spec's rekordbox import, which fills `rating` on unrated rows only.

### `LibraryRow` (the value crossing the store boundary)

```swift
struct LibraryRow: Identifiable, Hashable, Sendable {
    let id: UUID              // LibraryTrack.id — stable across refreshes
    let rootID: UUID
    let url: URL              // current root URL + relativePath
    let title, artist, album, albumArtist: String
    let genre: String?
    let trackNumber: Int?     // sort tie-breaker
    let duration: Double
    let fileSize: Int64       // carried into Track
    let bpm: Double?
    let musicalKey: String?
    let bitrate: Int
    let bitrateIsDerived: Bool
    let codec: String
    let isAvailable: Bool     // effective availability
    let searchKey: String     // folded title/artist/album/albumArtist, built once per snapshot
}
```

`LibraryRow.makeTrack() -> Track` builds `Track(title:artist:duration:fileSize:url:)` from the row's own fields, with no lookup. Each call produces a new `Track` occurrence identity, which is correct: enqueuing the same library song twice yields two independent playlist entries. `Track` itself is not widened.

### Metadata extraction

The AVAsset work lives in **`TrackMetadataLoader`** (`Sources/Track.swift`). Its `Metadata` struct is widened; `Track.load(from:)` keeps reading only the four fields it uses today. The content fingerprint is computed by `LibraryFileSystem` in the same parse step, not by the loader.

`TrackMetadataParser` (`Sources/TrackMetadataParser.swift`) — filename and path heuristics — is **unchanged**.

#### Metadata precedence

`title` and `artist` keep **exactly today's loader behaviour**, so the library and the playlist never disagree about the same file:

1. Common-metadata `title` / `artist` tags.
2. If **neither** tag is present → `TrackMetadataParser.parse(from:)` supplies both (e.g. `Artist - Song.mp3` → `Artist` / `Song`; its last resort is filename stem / `"Unknown Artist"`).
3. If only one tag is present, the other keeps the loader default: filename stem for `title`, `"Unknown Artist"` for `artist`.

All other fields:

| Value | Source | Absent value |
|---|---|---|
| album / albumArtist | `.commonKeyAlbumName` / album-artist key (TPE2, `aART`) | `""` |
| genre | `.id3MetadataKeyContentType` (TCON) / `.iTunesMetadataKeyUserGenre` | nil |
| year | `.commonKeyCreationDate`, else TDRC / TYER | nil |
| track no. | `.id3MetadataKeyTrackNumber` | nil |
| BPM | `.id3MetadataKeyBeatsPerMinute` (TBPM) | nil |
| key | `.id3MetadataKeyInitialKey` (TKEY) | nil |
| sampleRate / channels | audio track format description (`AudioStreamBasicDescription`) | 0 |
| bitrate | `AVAssetTrack.estimatedDataRate` when > 0 (`bitrateIsDerived = false`); else `fileSize * 8 / duration` when `duration > 0` (`bitrateIsDerived = true`) | 0 |

#### L1 gate — metadata, rename evidence and cost

Before any scanner code, a fixture-driven spike records:

- **Metadata**, per container (MP3 ID3v2.3, MP3 ID3v2.4, FLAC with Vorbis comments, WAV with an `id3 ` chunk, AIFF with an `ID3 ` chunk, M4A): which of the fields above AVFoundation actually returns. A field AVFoundation does not expose for a container takes **its declared absent value** (the table above) for that container in V1, recorded in this spec. Adding an in-house tag reader is a spec amendment, not a planning decision.
- **Playback:** `AudioPlayer` plays the AIFF and M4A fixtures before `M3UParser.supportedExtensions` is widened.
- **Rename evidence:** on APFS, HFS+, exFAT and SMB, a rename and a move within the volume preserve `fileSize` and `contentModificationDate` exactly as reported by the enumerator (including sub-second precision), and `volumeSupportsCaseSensitiveNamesKey` is readable inside the sandbox. A file system that fails this check has rename tracking disabled by rule in this spec.
- **Cost:** walk timings for a no-change walk of a 2,232-file and an 11,000-file tree, and first-scan time **including** fingerprint reads, on the internal SSD and on an external spinning drive, against the budgets below. A missed 11k budget reopens *Scan unit*; a fingerprint cost that breaks the first-scan budget reopens *Rename detection*.

### Scanning

A scan always covers one whole root. A scan run starts by obtaining a **token** from `LibraryStore`. Every save the run makes carries that token, and the store rejects the save — ending the run — if the token has been revoked or the root no longer exists.

0. **Access.** Resolve the root bookmark (refresh stale data) and read the root volume's case sensitivity.
   - On failure → save `isAvailable = false`, stop.
   - On success → save `isAvailable = true`, `displayPath` and `unreadableFolderCount` when they changed; capture the path-key rule; ensure the root's security scope is active.
1. **Integrity repair.** Load the root's row keys under the path-key rule from step 0. If two or more rows share a path key (the invariant was broken by a defect), merge them in one save before matching: the row with the oldest `dateAdded` (then smallest `id`) survives, keeping its metadata and fingerprint; it takes the maximum `playCount`, the latest `lastPlayedAt` and its own `rating`, or the first non-zero `rating` of the others by `dateAdded`. The other rows are deleted and a fault is logged. After this step the path key is unique, so matching can rely on it.
2. **Walk.** Enumerate through `LibraryFileSystem`, prefetching `.isRegularFileKey`, `.fileSizeKey`, `.contentModificationDateKey` and `.volumeIdentifierKey`. Skip `_extracted/`, `_library/`, dotfiles, package contents, and — by comparing the in-session `volumeIdentifierKey` with the root's — the descendants of any directory on another volume. Accept the extensions in `M3UParser.supportedExtensions`, the app's single audio extension set; this spec widens it from `mp3`, `flac`, `wav` to add `aif`, `aiff` and `m4a`, which also lets playlist file/folder import accept them (an intentional behaviour change, gated on playback). The walk reads no file contents.
   - When the error handler reports a URL, record its directory as an **uncovered folder** and continue: the walk is **partial**.
   - Cancellation or loss of access makes the walk **aborted**: the run saves nothing further and stops. Anything already saved (steps 0–1) stays valid.
3. **Match by path.** Each entry whose path key has a row is **matched** to it. When the enumerator's spelling differs from the row's `relativePath` (a case-only rename on a case-insensitive volume, or a normalization-only rename), the new spelling is recorded.
4. **Reconcile** with `LibraryReconciler`. Rows not matched in step 3 split into **set-aside rows** S (whose `relativePath` lies inside an uncovered folder — their files were never looked for) and **unmatched rows** U (everything else — their locations were covered, so their files are proven absent there). Entries not matched form N.

   **Moves are considered only when the walk is complete** (so S is empty). Ambiguity is judged only from values that step 6 can never change: the sizes and dates **just read by the walk**, and the stored sizes and dates of **unmatched rows** (which are never re-parsed). Stored values of matched rows are not consulted. A matched row is represented by its entry's walked values, which the entry count already includes. For a size/date pair K = `(fileSize, contentModifiedAt)`, a row in U and an entry in N are a **candidate** only if:
   - exactly **one entry in the whole walk** has walked K — counting matched and unmatched entries — and it is that entry in N; and
   - exactly **one row in U** has stored K — U includes rows flagged missing by earlier scans — and it is that row; and
   - the row's `contentFingerprint` is non-nil.

   For each candidate, `LibraryFileSystem` computes the entry's fingerprint (one head/tail read). **Equal → move. Different or unreadable → no move.** On a partial walk there are no candidates. Every entry in N that is not moved is **new**.
5. **Commit structure** (one save): moves (`relativePath` rewritten); spelling updates; `isMissing = false` for matched and moved rows; `isMissing = true` for the rows remaining in U; `unreadableFolderCount`. Set-aside rows are untouched. No row is inserted before this save.
6. **Parse.** For matched and moved rows whose `(fileSize, contentModifiedAt)` changed, re-parse and recompute the fingerprint. For new entries, parse, fingerprint and insert. Saves every 200 rows. Progress is published as `AsyncStream<ScanProgress>` (`phase: walking | reconciling | parsing`, `done`, `total`).
   - When a file cannot be read, the scanner first checks that the root is still reachable. If it is not, the run aborts without saving that row. Only a failure on a reachable root saves a row with whatever parsed (*Corrupt / unreadable file*).
7. **Finish.** A **complete** walk sets `lastCompletedScanAt`.

`LibraryStore` publishes a `LibraryChange` after each accepted save (see *Change publication*), so a run that ends early has already published everything it committed.

**Interruption.** Given the same file-system state and the same read results, an interrupted scan followed by a retry reaches the same final state as one uninterrupted scan:

- An aborted walk saves nothing beyond steps 0–1, so the retry starts from the same rows.
- An interruption during step 6 leaves the moves and missing flags of step 5 committed. On retry the walk yields the same entries, so **entry counts are identical**.
- U on retry is the first run's U minus the rows it moved, which now match by path. Rows in U are never re-parsed, so **their stored keys are identical**.
- Rows inserted or re-parsed in step 6 match by path on retry and are not in U, so partially committed metadata never enters the decision.
- Every pair not moved in the first run is therefore judged on the same counts and fingerprints and gets the same answer. A moved pair's entry is now matched, so it is not decided again. No other row in U can share a moved row's K, because a second such row would have made K ambiguous. Remaining entries are inserted exactly as they would have been; un-reparsed rows are still stale.

Examples:

- **Hard link.** Indexed A is renamed to B, and hard link C is added. The walk sees B and C with A's size and date, so two entries have K → no candidate; B and C are inserted, A is flagged missing. If the run stops after inserting B, the retry still walks B and C with K → still ambiguous → C is inserted. Identical result.
- **Update before insert.** Indexed A and X both have stored K. A is renamed to B (same size, date and content); X is modified, so its walked values are K2. The walk matches X by path and counts it under K2, so only B has walked K and only A in U has stored K → fingerprints equal → A moves to B in step 5 of the first run. If the run stops after saving X's re-parse, the retry makes no new decision, because B now matches A's row by path. Identical result.

**Known limitations (accepted):**

- Swapping the names of two indexed files leaves each row on its path (same path = same track), so ratings follow the path, not the audio.
- A rename is **not tracked** (missing row plus new row) when: the file was also modified before the next scan; the root had unreadable folders during that scan; another file in the root, or another missing row, has the same size and modification date (hard links, copies with preserved dates); the fingerprint could not be read; or the file system failed the rename-evidence gate.
- A different file that matches a missing row's size, modification date and head/tail content is treated as the same track.
- A file replaced at the same path with identical size and modification date keeps its previous metadata and fingerprint until either changes (the staleness rule).

### Scan scheduling

`LibraryScanner` runs **at most one scan at a time** across all roots, using a FIFO of root IDs with at most one pending entry per root.

- `requestScan(root)` while that root is **not queued or running** → enqueue.
- … while it is **queued** → no-op (the pending scan will see the change).
- … while it is **running** → mark `rescanRequested`; when the run finishes, enqueue it once more. Any number of requests during a run collapse into one follow-up, so a change inside a directory the walk has already passed is always picked up.
- `cancelScans(root)` removes the root's queued entry, **revokes the running scan's token in the store**, and cancels its task. Relocation, removal, unmount and access loss call it. A save already queued or suspended when the token is revoked is rejected whenever it arrives, including after a remount, because a remount starts a new run with a new token.

Full-root scans are triggered by: adding a root, relocating a root, library start-up (one catch-up scan per available root; event IDs are not persisted), any FSEvents batch under the root (including `MustScanSubDirs`, `UserDropped`, `KernelDropped`), `RootChanged` (re-resolve the bookmark first), and a volume mount (`NSWorkspace.didMountNotification`).

### Roots and security scope

All root operations go through `LibraryStore`, which saves first, then publishes the change, then rebinds the watcher and security scope.

| Operation | Behaviour |
|---|---|
| **Add** | User picks a folder (`NSOpenPanel`). Reject it if it is inside, equal to, or contains an existing root (compare standardized, symlink-resolved paths). Set the start-up marker, create a security-scoped bookmark, insert `LibraryRoot`, publish `rootsChanged`, start access, add it to the watcher, request a scan. |
| **Remove** | Confirmation that names the row count and warns that ratings/play counts are lost. `cancelScans`, delete the root and its rows in one save, publish `rootRemoved`, stop access, remove it from the watcher, clear the start-up marker if no roots remain. |
| **Unmount / access lost** | `cancelScans` (revoking the token), save `isAvailable = false`, publish `rootsChanged`, stop access. Rows are kept and drawn unavailable; `isMissing` is untouched. The module offers *Relocate…*. |
| **Relocate** | User picks the folder's new location. Validate it with Add's overlap rule, **excluding the root being relocated**. `cancelScans` (revoking the token). In one save, replace `bookmark` and `displayPath`. Publish `rootsChanged`, stop access to the old URL, start access to the new one, rebind the watcher, request a scan. `rootID` and every row's `relativePath` are kept, so files at the same relative paths match in step 3 and recover their reserved fields. |
| **Returns on its own** (remount) | Bookmark resolves → a new run's step 0 saves `isAvailable = true` and publishes. Unchanged files match in step 3, `isMissing` is cleared in step 5, nothing is re-parsed. |

**Start-up and cost.** A UserDefaults flag, `AmpXLibraryHasRoots`, decides whether the library starts at all, so no container is opened just to discover that there are no roots. Add sets it **before** inserting a root; Remove clears it only **after** the save that deletes the last root. A crash between the two therefore at worst opens the container once needlessly, never hides a root. At launch:

- flag false → nothing is instantiated: no container, no watcher, no snapshot;
- flag true → the library starts at `.utility`: open the container; if it holds no roots, clear the flag and stop; otherwise resolve roots, start access, start the watcher, and queue catch-up scans. The row snapshot is built lazily on the first query.

**Access lifetime.** `LibraryStore` holds each available root's security scope from start-up until the root is removed, becomes unavailable, is relocated (the old URL's scope), or the app quits. Files under the root are therefore readable for playback while the library runs.

**Playlist continuity across relaunch.** `PlaylistManager` restores its playlist in `init`, before the library starts. So playback does not depend on library start-up order:

- The app creates **one** `SecurityScopedBookmarkStore` and passes it to `PlaylistManager` through the existing `init(bookmarkStore:)` parameter. This changes how `PlaylistManager.shared` is constructed, not `PlaylistManager`'s public API.
- On enqueue, the library calls `saveBookmark(for: rootURL)` on that shared store (which already de-duplicates). `ensureAccess` already matches a file against an ancestor-folder bookmark, so restored tracks under the root regain access on relaunch.
- Removing or relocating a library root does not remove that playlist bookmark, because the playlist may still reference those files.

Roots under `~/Music` are also readable through the `com.apple.security.assets.music.read-only` entitlement. Verification must therefore use a root **outside** `~/Music`.

**Bookmark primitive.** The private statics in `SecurityScopedBookmarkStore` (`resolveBookmark`, `refreshBookmarkData`, bookmark creation, `ResolvedBookmark`) move into an internal `SecurityScopedBookmark` helper with `makeData(for:)`, `resolve(_:)` and `refreshedData(for:usesSecurityScope:)`. The store calls the helper and keeps its UserDefaults array, de-duplication, and drop-unresolvable restore policy unchanged. The library uses the helper and persists root bookmarks in SwiftData with its own keep-and-flag policy.

### Change publication

```swift
enum LibraryChange: Sendable {
    case rootsChanged(rootID: UUID)   // added, availability, location, status
    case rootRemoved(rootID: UUID)
    case rowsChanged(rootID: UUID)    // any save that inserted, updated, merged or deleted rows
}
```

- Published by `LibraryStore` **after** a save succeeds, never before and never for a rejected save.
- Every save that touches a root publishes `rootsChanged` or `rootRemoved`; every save that touches rows publishes `rowsChanged`. One save may publish both.
- `LibraryIndex` applies changes as follows, for any snapshot already built:

| Change | Index behaviour | Latency |
|---|---|---|
| `rootRemoved` | Evict every row with that `rootID` | Immediate |
| `rootsChanged` | Rebuild that root's rows, so `url` (from the root's current location) and `isAvailable` (from `root.isAvailable`) are current | Immediate |
| `rowsChanged` | Re-fetch that root's rows | At most one re-fetch per root per second, plus one trailing re-fetch after the last change |

- After applying a change, the index publishes a snapshot version; `LibraryBrowserModel` re-runs its current query under the usual generation rule, so facet counts, rows and selection update together.
- Enqueue re-checks `isAvailable` against the latest snapshot at action time, so an unmount that has been published cannot be enqueued from a stale result set.

### Index and query semantics

`LibraryIndex` holds `[LibraryRow]` for all roots, built on first query and maintained by *Change publication*. It reads through its own `ModelContext` on the shared container, so it never queues behind the writer. `searchKey` is the space-joined `title`, `artist`, `album` and `albumArtist`, folded with `[.caseInsensitive, .diacriticInsensitive]`.

`LibraryQuery` is a `Codable`, `Sendable` value type (so the DJ-mode spec's saved smart playlists can persist it):

| Aspect | Rule |
|---|---|
| Search | Split the folded input on whitespace; a row matches when **every** term is a substring of its `searchKey`. Empty search matches all. |
| Facets | Genre, Artist, Album. Values selected **within** a facet combine with OR; facets combine with AND. Nil genre → `(No Genre)`, empty album → `(No Album)`. |
| Facet counts | Each facet's counts are computed over rows matching the search **and every other facet's** selection, excluding its own, so selecting a genre does not collapse the genre list. Counts include unavailable rows. |
| Sort | One user-chosen column and direction, then the fixed tie-breakers `artist`, `album`, `trackNumber` (nil last), `title`, `id`. The full comparator is a total order, so results are stable regardless of sort algorithm. |
| Staleness of results | Each request carries a monotonically increasing generation. `LibraryBrowserModel` cancels the previous request's task and drops any result whose generation is not the latest. |
| Selection | `Set<LibraryRow.ID>`. After a refresh, IDs still present in the result stay selected; IDs no longer present are dropped. The focused row survives when present. |

### Actions

| Action | Effect |
|---|---|
| Enter / double-click | **Replace** the playlist with the selection's *available* rows (if the clicked row is outside the selection, just that row), in displayed order, and play the first. The existing `clearPlaylist()`, `addTracks(_:)` and `playTrack(at:)` are used; no new `PlaylistManager` API. |
| ⌘-Enter | **Append** the selection's available rows in displayed order. |
| Drag to Playlist | Append, same rule. |
| Selection containing only unavailable rows | No-op with `NSSound.beep()`. |

Every enqueue registers the involved roots with the shared bookmark store (see *Playlist continuity*).

### Browser module (L2)

Built in the AmpX UI host as `Sources/Modules/Library/`, following that spec's contracts: `AmpXModuleContent` drawing, custom rows (no `NSTableView`/`NSScrollView`/`NSTextField`), one Combine subscription set to `LibraryBrowserModel`, and effective-visibility rules for any continuous drawing (scan progress).

- **Layout at 490 pt:** header; a search well; a left facet column (~140 pt) with a Genre / Artist / Album selector and one value list with counts; a right track list with Artist – Title, Time, BPM, Key and kbps (22 pt rows, derived bitrates marked); a footer with scan progress and a **ROOTS** menu (Add Folder…, Remove, Relocate…, and a status line per root: unavailable, or *n folders unreadable*). Exact metrics are sampled in planning against the module reference idiom. Unavailable rows are drawn in `textDim`.
- **Commands:** `Window ▸ Library` (⌘L — currently unbound; `AmpXMenuCatalog.FileShortcut` uses bare `L` / `⇧L` for Add Files / Add Folder, so Library must keep the Command modifier) and `File ▸ Add Library Folder…`. ⌘F focuses search; Escape in search clears it and then leaves the field.
- **Accessibility:** a selectable row hierarchy with settable selection and selection-change notifications, as the Playlist module has; facet values expose their counts; the search field exposes its value.

**Required amendment to the UI design spec** (accept before L2 planning):

1. Register module ID `library`: it may collapse, close, detach and re-dock like Equalizer/Playlist, and it docks in the left column.
2. Library becomes a **second variable-height module**. Overflow rule: shrink the Library viewport first, then Playlist, each down to three rows.
3. Add a custom **text input component** (search) implementing `NSTextInputClient` for IME and marked text — the UI spec currently defines none and forbids `NSTextField`.
4. Add key-router priority **2b — Focused Library module**: arrows/Home/End/Page navigation and selection, Enter, ⌘-Enter, ⌘F.

## Error handling & edge cases

| Case | Behavior |
|---|---|
| Root bookmark stale but resolvable | Refresh the bookmark data; continue |
| Root unavailable (moved folder, unplugged drive, access failure) | Scan token revoked; `isAvailable = false` saved and published; the open browser immediately shows its rows unavailable and excludes them from enqueue; `isMissing` untouched |
| Save from a scan queued or suspended before unmount, delivered after it (or after remount) | Rejected — its token was revoked; nothing published |
| Volume vanishes while a file is being parsed | Reachability check fails → run aborts; no degraded row saved |
| Root returns / is relocated | New run; same-path files recover with rating and play count, without re-parse when `(size, mtime)` held |
| Relocation into, onto or around another root | Rejected with an explanation, as for Add |
| Relocation while a scan is running or suspended in parsing | Token revoked; any save it still attempts is rejected |
| File deleted on disk | The next walk covering its folder sets `isMissing = true`; row drawn unavailable and excluded from enqueue; never auto-deleted |
| Deleted file reappears at the same path | Matched by path; `isMissing = false`; re-parsed only if `(size, mtime)` changed |
| File renamed/moved within a root | Complete walk, size/date carried by exactly one walked file and one unmatched row, fingerprints equal → `relativePath` rewritten; row and reserved fields preserved; no duplicate |
| Rename the rule cannot prove (renamed and modified, unreadable folders present, size/date shared, fingerprint unreadable) | Missing row plus new row. Accepted limitation |
| Case-only rename | Case-insensitive volume: path match, spelling updated. Case-sensitive volume: ordinary rename under the rename rule |
| A different file takes a deleted file's size and date | Fingerprints differ → no move; missing row plus new row. Identical head/tail content → treated as the same track (accepted) |
| Hard links or date-preserving copies of a file | Share size and date → ambiguous → never a move target; each path is its own row |
| Folder inside a root unreadable | Walk is partial: rows inside set aside (neither missing nor moved); rows elsewhere flagged normally; no moves this scan; root status shows the count |
| Walk aborted (cancellation, access lost) | Nothing beyond steps 0–1 is saved; `lastCompletedScanAt` unchanged |
| Interrupted between insert batches | Retry reaches the same state as an uninterrupted scan (see *Interruption*) |
| Two rows share one path | Merged in scan step 1 with reserved fields combined; fault logged |
| File contents replaced at the same path | Same row (same path = same track); re-parsed and re-fingerprinted when `(size, mtime)` changed |
| Two indexed files swap names | Rows stay on their paths; both re-parsed if `(size, mtime)` differ. Accepted limitation |
| File moved to another root | Missing row in the old root, new row in the new one. Accepted limitation |
| Adding a nested or overlapping root | Rejected with an explanation |
| Remove a root with the browser open | Rows and facet counts disappear on the published `rootRemoved`; selection drops their IDs |
| Corrupt / unreadable file on a reachable root | Row inserted with whatever parsed; `duration == 0`; `contentFingerprint` nil if the read failed; logged once per file per scan; scan continues |
| Duplicate audio at two paths | Both indexed; no de-duplication |
| Container from an older schema | `SchemaMigrationPlan` handles V1 → Vn; an unknown *newer* version refuses to open and says so rather than dropping rows |
| Tags absent entirely | Loader precedence: `TrackMetadataParser` heuristics, final fallback filename stem / `"Unknown Artist"`; `genre` nil |
| App quits mid-scan | Index valid; the next start-up catch-up scan completes it |
| Changes arrive while a scan runs | Coalesced into exactly one follow-up full scan of that root |
| No roots configured | Start-up flag false: no container, watcher, or snapshot is created |
| Start-up flag true but no roots in the container | Flag cleared; library stops |

## Performance targets

Measured separately; each is a test or instrumented measurement, not an estimate.

| Target | Budget | Measured from → to |
|---|---|---|
| First scan, `~/Music/DJ` (2,232 files), including fingerprints | < 60 s, UI never stalls | scan start → completion |
| No-change rescan, 2,232 files | < 2 s, zero file-content reads | scan start → completion (**excludes** the 2 s FSEvents latency; file change → visible result is therefore ≤ ~4 s plus parsing of changed files, plus ≤ 1 s index throttle) |
| No-change rescan, 11,000 files | < 5 s, zero file-content reads | same; validated at the L1 gate |
| Search, 11,000-row index | < 100 ms | keystroke → published result set, **both idle and during a first scan**; no dropped frames on the main thread |
| Availability change → browser | < 100 ms | store save → module shows rows unavailable |

## Testing

| Area | Expectations |
|---|---|
| L1 gate | Metadata field-coverage matrix recorded per container; AIFF and M4A play through `AudioPlayer`; rename/move preserves size and modification date on APFS, HFS+, exFAT and SMB; case sensitivity readable in the sandbox; walk and first-scan timings including fingerprints on SSD and spinning drive |
| Extensions | `M3UParser` accepts `aif`/`aiff`/`m4a` case-insensitively; existing M3U tests green; folder import picks up AIFF/M4A fixtures |
| `TrackMetadataLoader` | Every field available per the gate matrix is extracted; unavailable fields take their declared absent value; `estimatedDataRate` vs derived bitrate sets `bitrateIsDerived` correctly |
| Metadata precedence | Untagged `Artist - Song.mp3` → `Artist` / `Song`; untagged `Song.mp3` in a common dir → stem / `Unknown Artist`; title-only tag → tagged title / `Unknown Artist`. Matches `Track.load(from:)` for the same fixtures |
| `TrackMetadataParser` | Unchanged — regression only |
| Bookmark primitive | Existing `SecurityScopedBookmarkStore` tests green unchanged after extraction; helper round-trip, stale refresh |
| Fingerprint | Deterministic for a file; changes with a tag edit; defined for files smaller than 128 KiB; nil on read failure; computed on insert and re-parse only |
| Staleness | Unchanged `(size, mtime)` → no parse and no content read (spy); changed mtime → re-parse and re-fingerprint |
| `LibraryReconciler` (pure) | Unambiguous size/date with equal fingerprint → move. Equal size/date, different fingerprint (**two distinct file lifetimes**) → no move. Row fingerprint nil → no move. Size/date shared with a matched entry, a second entry in N, or a second row in U (including a missing row from an earlier scan) → no move. A matched row whose **stored** size/date equals K but whose walked values differ does not count. Partial walk → no moves. **Batch interruption:** rows {A}, entries {B, C} sharing K → no move; after B is inserted, rows {A, B}, entries {B, C} → still no move; final state equals the uninterrupted result. **Update before insert:** rows A and X stored with K; A renamed to B, X modified to K2 → A moves to B in the first run; a run interrupted after saving X's re-parse and then retried reaches the same state, as does interruption at every other batch boundary. **Hidden link:** A's absence covered, B seen, C inside an unreadable folder → partial → no move |
| Identity (scanner) | Rename keeps row id and reserved fields with no insert before the structure save; path swap keeps rows on paths; content replacement at the same path keeps the row; case-only rename keeps the row on a case-insensitive volume (path match) and on a case-sensitive volume (rename rule) |
| Integrity repair | Two and three rows sharing one path → one survivor with oldest `dateAdded`, max `playCount`, latest `lastPlayedAt`, correct `rating`; fault logged; subsequent scan is a no-op |
| Interruption | Abort during the walk saves nothing beyond steps 0–1; cancel after the structure save and between every insert batch; each retry reaches the same final state as an uninterrupted scan, with no duplicates |
| Coverage | Unreadable folder: rows inside untouched, rows elsewhere flagged normally, no moves, `unreadableFolderCount` saved, `lastCompletedScanAt` unchanged |
| Scan tokens | A save suspended before unmount and delivered after it is rejected; the same save delivered after a remount is rejected; relocation and removal revoke likewise; a rejected save publishes nothing; a parse failure on a vanished volume aborts without saving a row |
| Availability | Unavailable root → rows untouched; unavailable → available with unchanged files clears unavailability with zero parses; reappearing file clears `isMissing` |
| Roots | Add rejects nested/overlapping roots; relocate rejects a destination inside, equal to or containing another root; relocate recovers rows by relative path with reserved fields; remove deletes only that root's rows |
| Change publication | With a populated snapshot and an open query: unmount, access failure, relocation and removal each update rows, availability, URLs and facet counts; a run that ends early has published its committed batches; `rowsChanged` re-fetches are throttled with a trailing re-fetch |
| Start-up marker | Flag false → no container opened; Add sets the flag before insert; Remove of the last root clears it after the save; flag true with an empty container self-clears |
| Scheduling | Requests while queued coalesce; a request while running produces exactly one follow-up; a change in a directory already walked is indexed after the follow-up; changes in two roots both get scanned; removal, relocation and unmount cancel the root's scan and revoke its token |
| `LibraryStore` | Insert / update round-trip; batch save boundary at 200 |
| Schema migration | A V1 container opens under a test V2 schema with rows and values intact; migration idempotent; `schemaVersion` stamped |
| `LibraryIndex` / `LibraryQuery` | Multi-term search; OR within / AND across facets; counts exclude own facet; `(No Genre)` bucket; total-order sort including `trackNumber`; late result for an older generation is dropped; query latency during an active scan |
| `LibraryBrowserModel` | Selection survives refresh; vanished IDs dropped; unavailable rows excluded from enqueue, re-checked at action time; `makeTrack()` carries `fileSize`; enqueuing the same row twice yields two distinct `Track`s; enqueue registers the root bookmark in the shared store |
| Playback continuity | Root outside `~/Music`: enqueue, relaunch, restored tracks play (manual/UI check in L2) |
| Regression | Existing `PlaylistManagerTests` and `AudioPlayerTests` untouched and green |

Fixtures go through the existing `scripts/` `uv` generation path; run via `./scripts/run-tests.sh`.

## Files expected to change

### L1 — Engine

- `Sources/Track.swift` — widen `TrackMetadataLoader.Metadata` and extraction; **`Track` unchanged**
- `Sources/Playlist/SecurityScopedBookmarkStore.swift` — delegate to the extracted helper; behaviour unchanged
- **New** `Sources/Playlist/SecurityScopedBookmark.swift` — shared create/resolve/refresh primitive
- `Sources/M3UParser.swift` — widen `supportedExtensions` with `aif`, `aiff`, `m4a` (after the playback gate passes)
- **New** `Sources/Library/LibrarySchemaV1.swift` — `LibraryRoot`, `LibraryTrack`, `LibraryMigrationPlan`
- **New** `Sources/Library/LibraryStore.swift` — `@ModelActor` writer, roots, scan tokens, change publication, start-up marker, security-scope lifetime
- **New** `Sources/Library/LibraryFileSystem.swift` — enumeration, case-sensitivity and fingerprint protocol plus the `FileManager` / `FileHandle` implementation
- **New** `Sources/Library/LibraryReconciler.swift` — pure path-key matching, coverage, walk-based ambiguity and fingerprint-confirmed move plan; integrity merge plan
- **New** `Sources/Library/LibraryScanner.swift` — scan steps, scheduling, cancellation, reachability checks, progress
- **New** `Sources/Library/LibraryWatcher.swift` — FSEvents and mount/unmount notifications, root rebinding
- **New** `Sources/Library/LibraryIndex.swift` — snapshot actor, `LibraryRow`, change application and throttling
- **New** `Sources/Library/LibraryQuery.swift` — query value type and evaluation
- **New** `Sources/Library/LibraryBrowserModel.swift` — `@MainActor` `ObservableObject`, selection, enqueue
- `scripts/` fixture generation — FLAC, ID3-in-WAV, ID3-in-AIFF, M4A and untagged fixtures
- **New** `Tests/AmpXTests/LibraryMetadataGateTests.swift`, `TrackMetadataLoaderTests.swift`, `SecurityScopedBookmarkTests.swift`, `LibraryFingerprintTests.swift`, `LibraryReconcilerTests.swift`, `LibraryStoreTests.swift`, `LibraryScanTokenTests.swift`, `LibraryScannerTests.swift`, `LibraryIdentityTests.swift`, `LibraryRootTests.swift`, `LibraryChangePublicationTests.swift`, `LibraryScanSchedulingTests.swift`, `LibrarySchemaMigrationTests.swift`, `LibraryQueryTests.swift`, `LibraryBrowserModelTests.swift`

### L2 — Browser module (after the UI cutover)

- `docs/superpowers/specs/2026-09-11-ampx-ui-design.md` — the amendment above
- **New** `Sources/Modules/Library/` — module content, row/facet/search subviews, root status, text input component (or `Sources/Components/` per the UI plan)
- App delegate — shared `SecurityScopedBookmarkStore`, `PlaylistManager` construction, library start-up gated on the start-up flag
- `AmpXMenuCatalog` — `Window ▸ Library`, `File ▸ Add Library Folder…`
- `AmpXKeyRouter` — Library focus context
- `AmpXLayoutStore` / module order — `library` module ID and viewport height

## Success criteria

1. **L1 gate recorded** in this spec — metadata coverage per container, rename evidence per file system, walk and first-scan timings — before scanner work begins.
2. A first scan of `~/Music/DJ` (2,232 files) completes without blocking the UI, and the index yields all 17 crates as genre facets with correct counts (L1: query test against the real folder; L2: visible in the module).
3. Relaunch does not re-parse or read the contents of unchanged files (spy).
4. The *Performance targets* are met, including search during a scan.
5. Double-click in the browser plays through the existing `AudioPlayer` path with no change to `PlaylistManager`'s public API and no change to `Track`.
6. Deleting a file flags its row; unplugging a root makes its rows unavailable in an open browser at once, and remounting recovers them without re-parse; relocating a root recovers rows with rating and play count; renaming a file keeps its row when a complete scan finds its size and date unambiguous in the root.
7. Reserved fields only ever move to a file with the same size, modification date and content fingerprint; an interrupted scan never produces a different result than an uninterrupted one on the same file-system state; no save from a cancelled run is ever accepted.
8. Tracks enqueued from a root outside `~/Music` still play after relaunch.
9. The shipped container is `LibrarySchemaV1` behind a `SchemaMigrationPlan`.
10. `./scripts/run-tests.sh` green, including all pre-existing tests.

## Risks

| Risk | Mitigation |
|---|---|
| SwiftData on a strict-concurrency Swift 6 target is fiddly | One writer `@ModelActor`; `@Model` instances never cross isolation boundaries — scanner and index exchange value types only |
| SwiftData `.unique` upserts rather than rejects | Only `id` is unique; path-key uniqueness is a scanner invariant with dedicated tests and an explicit merge if it is ever broken |
| A rename moves reserved fields to the wrong file | Moves require a complete walk, a size/date pair carried by exactly one walked file and one unmatched row, and an equal content fingerprint. The residual case — identical size, date and head/tail bytes — is declared as the same track |
| Fingerprint reads slow the first scan, especially on spinning drives | Two 64 KiB reads per parsed file only, never on no-change rescans; measured at the L1 gate against the first-scan budget |
| A file system does not preserve size/date on rename | Checked per file system at the L1 gate; rename tracking disabled by rule where it fails |
| AVFoundation does not expose FLAC Vorbis comments or ID3 inside WAV/AIFF | L1 gate before scanner work; gaps take the field's declared absent value or are escalated as an amendment, never patched with an ad-hoc parser |
| Change storms during a first scan | `rowsChanged` re-fetches throttled per root; root changes applied immediately because they gate enqueue |
| Full-root rescans too slow for the 11k archive | Gate measurement; subtree scoping returns as an amendment if the budget is missed. Watched roots are opt-in; `~/Music/DJ` alone is the expected default |
| L2 blocked on the UI cutover | L1 delivers and tests the entire engine independently; L2 is a UI-only change on top |
| Custom text input (IME, marked text, accessibility) is costly in a no-`NSTextField` UI | Listed as an explicit UI-spec amendment so it is scoped and estimated, not discovered mid-implementation |
| `Package.swift` build-smoke and SwiftData | Verify in the first L1 task; SwiftData and CryptoKit are system frameworks |
| Scope creep into DJ mode | BPM/key are read-only from tags; computing and writing them back is the next spec |
| Schema break when DJ mode widens `LibraryTrack` | `VersionedSchema` + `SchemaMigrationPlan` from day one, with a migration test |

## Revision log

**Revision 5 (2026-09-15)** — responds to the [Revision 4 review](./2026-09-11-music-library-design-review.md).

| Finding | Resolution |
|---|---|
| R4.1 — re-parsing can remove ambiguity between batches | Ambiguity is judged from the current walk's sizes/dates and the stored keys of unmatched rows only — neither can be changed by step 6. Matched rows' stored values are no longer consulted, so a partially committed re-parse cannot flip a decision. The interruption argument is restated on this basis, with the reviewer's update-before-insert case as a worked example and a reconciler test at every batch boundary. The guarantee also assumes the same read results |

**Revision 4 (2026-09-15)** — responds to the [Revision 3 review](./2026-09-11-music-library-design-review.md). Supersedes Revision 3's file-identifier matching, volume-UUID validity rule, deferral of entries, and `locationGeneration` fencing.

| Finding | Resolution |
|---|---|
| R3.1 — equal size and date do not rule out identifier reuse | File identifiers removed entirely. Candidates come from `(fileSize, contentModifiedAt)`; a move additionally requires an equal stored `contentFingerprint` (SHA-256 of size plus head/tail 64 KiB). The guarantee is narrowed to what this proves, and identical-content lifetimes are declared the same track. Reconciler test with two distinct lifetimes sharing size and date |
| R3.2 — partial coverage and batch interruption change hard-link reconciliation | Ambiguity is judged across the whole root inventory — matched and unmatched rows, matched and unmatched entries — so inserts can only make a pair more ambiguous *(ambiguity basis corrected in Revision 5)*. Moves happen only on complete walks. Tests for the batch-interruption and hidden-link counterexamples |
| R3.3 — unmount does not invalidate late saves | Store-issued scan tokens revoked by cancellation, unmount, access loss, relocation and removal; the store rejects revoked tokens. Parse failures check root reachability and abort instead of saving degraded rows |
| Advisory — case-only rename wording | Path match on case-insensitive volumes; ordinary rename under the rename rule on case-sensitive volumes |
| Simplification | `fileID`, `LibraryRoot.volumeUUID`, `LibraryRoot.locationGeneration`, the APFS/HFS+ enablement rule and entry deferral are removed; rename tracking now covers exFAT and SMB where the gate confirms size/date preservation |

**Revision 3 (2026-09-15)** — responded to the Revision 2 review.

| Finding | Resolution |
|---|---|
| R2.1 — persisted file IDs are not a durable identity | Volume-scoped, corroborated file IDs *(superseded by Revision 4)* |
| R2.2 — an incomplete walk cannot prove a rename | Complete / partial / aborted coverage; set-aside rows *(entry deferral superseded by Revision 4)* |
| R2.3 — root changes do not invalidate snapshots | Typed `LibraryChange` after every save; index eviction, rebuild and throttled re-fetch; enqueue re-checks availability |
| R2.4 — relocation bypasses validation and coordination | Overlap validation on Relocate; scan cancellation; watcher and scope rebinding *(generation fencing superseded by scan tokens in Revision 4)* |
| Advisories | `LibraryRow` fields; duplicate-path merge; start-up flag; declared absent values; DJ-mode names |

**Revision 2 (2026-09-14)** — responded to the original spec review and a follow-up check against source.

| Finding | Resolution |
|---|---|
| R1 — identity resolution inserted before reconciling; path swaps | Walk → match by path → reconcile → commit → parse. Nothing is inserted before reconciliation. "Same path = same track" is the declared rule; path swaps are a documented limitation |
| R2 — cleared `pathHint` unrepresentable | `pathHint` removed. Stable `id`, `rootID` + `relativePath` (kept while missing). Path uniqueness is a scanner invariant because SwiftData `.unique` upserts |
| R3 — incremental coverage and queued changes | Scan unit is always the full root; per-root queue with a single follow-up for changes during a run; explicit start-up, FSEvents-drop, `RootChanged` and mount triggers |
| R4 — root relocation and missing recovery | `LibraryRoot` model; add/remove/relocate/remount behaviour; availability separate from `isMissing`; `isMissing` cleared independently of staleness |
| R5 — bookmark store API and access lifetime | Only roots have bookmarks; primitive extracted from the store with its behaviour unchanged; library holds root scopes; shared store plus root registration on enqueue |
| R6 — stable browser identity and missing transport | `LibraryRow` with stable `id` and `isAvailable`; `Track` built at enqueue; selection survival and repeated-enqueue rules |
| R7 — contradictory untagged fallback | One precedence chain identical to today's loader |
| Advisories | Delivery phases L1/L2 per user decision; reserved fields; metadata gate; separate measurements; query semantics |
| Source checks | Deployment target 26.4; `ObservableObject`; snapshot actor for queries; `M3UParser.supportedExtensions` widened for AIFF/M4A behind a playback gate; ⌘L verified free |

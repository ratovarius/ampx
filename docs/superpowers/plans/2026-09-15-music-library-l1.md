# Music Library L1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Revised:** 2026-09-27. This revision resolves every finding in the [plan review](./2026-09-15-music-library-l1-plan-review.md) and targets spec **Revision 6**.

**Goal:** Build and verify the persistent library engine (store, scanner, reconciler, watcher, query index, browser model) without instantiating it anywhere in the shipping app until L2.

**Architecture:** One hand-written `ModelActor` (`LibraryStore`) is the only SwiftData writer and validates revocable scan tokens. `LibraryScanner` walks through a `LibraryFileSystem` protocol, asks the pure `LibraryReconciler` for a plan, and sends value types to the store. `LibraryIndex` keeps an in-memory `[LibraryRow]` snapshot on its own actor and evaluates `LibraryQuery`. `LibraryEngine` composes them behind an explicit `openIfConfigured` factory. `LibraryBrowserModel` is the `@MainActor` surface L2 will draw.

**Tech Stack:** Swift 6, macOS 26.0 deployment target, SwiftData, AVFoundation, CryptoKit, FSEvents (CoreServices), Combine, XCTest. Fixture tooling: Python via `uv` with `lameenc` and `mutagen`, plus the system `afconvert`.

**Spec:** [Music Library, Revision 6](../specs/2026-09-11-music-library-design.md), with its [approved review](../specs/2026-09-11-music-library-design-review.md). This plan implements **L1 only**.

**Base:** `develop`. Work happens on `feature/music-library` in `.worktrees/music-library`.

## Global Constraints

- "`Track` is **unchanged** by this spec." `Track.load(from:)` keeps consuming only title, artist, duration and fileSize.
- "Any third-party SPM package, including tag parsers" is a non-goal. `lameenc` and `mutagen` are fixture tooling under `scripts/`, never linked into the app.
- "Same path = same track": contents replaced at a path keep the row.
- "Moves are considered only when the walk is complete." Ambiguity uses the **current walk's** stats and the **stored** stats of unmatched rows U only (Revision 5). Stored stats of path-matched rows never enter it.
- "A different file that matches a missing row's size, modification date and head/tail content is treated as the same track." No inode identity, no full-file hash.
- Rename tracking is enabled only for volume types on `LibraryRenameTracking.verifiedVolumeTypes` (spec *Rename-tracking allowlist*).
- "L2 planning must not start until that amendment is accepted." No module UI, menus, key routing, app start-up wiring or `NSOpenPanel` in this plan.
- No production call site instantiates `LibraryStore`, `LibraryEngine` or `LibraryBrowserModel`.
- Files in users' roots are opened read-only. `playCount`, `lastPlayedAt`, `rating` are written only by the integrity merge (and tests).
- `PlaylistManager`'s public API is unchanged. Its one internal change is the Add Files panel's allowed types (Task 4).
- Never add `Co-Authored-By:` to commits. Never run `swiftformat` by hand; the PostToolUse hook formats edited Swift.

## Review Focus

Inputs the spec implies that are most likely to bite a real collection; each has a test in its owning task.

1. **Uppercase extensions** (`~/Music/DJ` has 22 `.MP3` files): accepted by the walk, `codec == "mp3"`. Test in Task 4 (`testUppercaseExtensionCodec`) and Task 7 (`testWalkAcceptsUppercaseExtensions`).
2. **NFD file names** (files copied from exFAT/SMB or macOS-decomposed accents) must path-match an NFC-stored row. Test in Task 7 (`testNFDSpellingMatchesNFCRow`).
3. **Crate folders with `&`, parentheses and spaces** (`Hard Groove (128k)`, `Drum & Bass`): URLs built with `appendingPathComponent`, never string concatenation; relative paths round-trip. Test in Task 7 (`testRelativePathRoundTripsPunctuation`).
4. **Zero-byte or truncated audio** on a reachable root: row inserted with `duration == 0`, `readFailed` logged once, scan continues. Test in Task 10 (`testCorruptFileInsertsDegradedRow`).
5. **A root chosen through a symlinked path**: relative paths are computed against the resolved root, so the next scan matches every row. Test in Task 7 (`testSymlinkedRootProducesStableRelativePaths`).

---

## Validation commands

Run once per session before any test:

```bash
./scripts/generate-fixtures.sh
```

**Run `<Suites>`** in any step means (one `-only-testing` per suite):

```bash
xcodebuild test -project AmpX.xcodeproj -scheme AmpX \
  -destination "platform=macOS,arch=$(uname -m)" \
  -only-testing:AmpXTests/<Suite> 2>&1 | grep -E 'error: |failed \(|TEST (SUCCEEDED|FAILED)'
```

- *Expected FAIL* means compile errors naming the missing symbol, or `failed (` lines for the named tests, then `TEST FAILED`.
- *Expected PASS* means only `TEST SUCCEEDED`.
- Missing fixtures, signing or tool installation is infrastructure, not the intended red. Fix it first.

Leave SwiftLint/SwiftFormat/Ruff and the full suite to CI (`gh pr checks`, `gh run view --log-failed`). The last task runs `./scripts/run-tests.sh` once.

## File map

| File | Responsibility | Task |
|---|---|---|
| `scripts/ampx_fixtures/library.py` | Deterministic tagged/untagged audio fixtures + `manifest.json` | 1 |
| `scripts/pyproject.toml` | Adds `lameenc`, `mutagen` | 1 |
| `Tests/AmpXTests/LibraryMetadataGateTests.swift` | Metadata matrix + AIFF/M4A playback probe | 1 |
| `Sources/Library/LibraryFingerprint.swift` | Size + head/tail SHA-256 | 2 |
| `scripts/library-gate-rename.swift` | Unsandboxed rename-evidence probe | 3 |
| `Sources/Library/LibraryRenameTracking.swift` | Volume-type allowlist from gate results | 3 |
| `Tests/AmpXTests/LibraryGateFileSystemTests.swift` | APFS rename evidence, case sensitivity, walk/first-scan cost | 3 |
| `Sources/Track.swift` | Widened `TrackMetadataLoader.Metadata` + extraction | 4 |
| `Sources/M3UParser.swift`, `Sources/PlaylistManager.swift` | Extension widening; panel types | 4 |
| `Sources/Playlist/SecurityScopedBookmark.swift` | Shared make/resolve/refresh | 5 |
| `Sources/Library/LibraryValues.swift` | Sendable value contracts | 6 |
| `Sources/Library/LibrarySchemaV1.swift` | `@Model`s, migration plan, container factory | 6 |
| `Tests/AmpXTests/LibraryTestSupport.swift` | Builders, fake file system, barriers, temp stores | 6 (extended later) |
| `Sources/Library/LibraryFileSystem.swift` | Protocol + `FoundationLibraryFileSystem` | 7 |
| `Sources/Library/LibraryReconciler.swift` | Pure path keys, plans, integrity merges | 7 |
| `Sources/Library/LibraryStore.swift` | Writer actor: tokens, saves, changes | 8 |
| `Sources/Library/LibraryStore+Roots.swift` | Root operations, scopes, start-up flag | 9 |
| `Sources/Library/LibraryScanner.swift` | One scan run (steps 0–7) | 10 |
| `Sources/Library/LibraryScanner+Scheduling.swift` | FIFO, coalescing, cancellation | 11 |
| `Sources/Library/LibraryQuery.swift`, `LibraryIndex.swift` | Query evaluation; snapshot actor | 12 |
| `Sources/Library/LibraryWatcher.swift` | FSEvents + mount notifications | 13 |
| `Sources/Library/LibraryEngine.swift` | Composition, `openIfConfigured`, event routing | 14 |
| `Sources/Library/LibraryBrowserModel.swift` | Published state, selection, enqueue | 15 |

`Sources/` and `Tests/AmpXTests/` are filesystem-synchronized groups: new Swift files need no project edit. `Tests/Fixtures/` is an explicit group: Task 1 edits `project.pbxproj`.

---

## Task 1: Library fixtures and the metadata/playback gate

**Files:**
- Create: `scripts/ampx_fixtures/library.py`, `Tests/AmpXTests/LibraryMetadataGateTests.swift`
- Modify: `scripts/ampx_fixtures/generate.py` (call `library.write_library_fixtures`), `scripts/pyproject.toml` (dependencies `lameenc>=1.8`, `mutagen>=1.47`), `scripts/uv.lock` (`uv lock`), `AmpX.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: bundle folder `Library/` with `manifest.json` and the fixtures below; the recorded metadata matrix (stdout lines prefixed `LIBRARY-GATE`).

Fixtures (all 2 s, 44.1 kHz stereo, 440 Hz sine). Tag values: title `Library Song`, artist `Library Artist`, album `Library Album`, album artist `Album Artist`, genre `Techno`, year `2024`, track `3/12`, BPM `130`, key `Am`, comment `Library fixture`.

| File | Encoding | Tags |
|---|---|---|
| `tagged-v23.mp3` | `lameenc` 192 kbps | ID3v2.3 (TYER) |
| `tagged-v24.mp3` | `lameenc` | ID3v2.4 (TDRC) |
| `tagged.flac` | `afconvert -f flac -d flac` | Vorbis: TITLE, ARTIST, ALBUM, ALBUMARTIST, GENRE, DATE, TRACKNUMBER, BPM, INITIALKEY, COMMENT |
| `tagged.wav` | Python `wave` | `mutagen.wave` ID3v2.3 chunk |
| `tagged.aiff` | `afconvert -f AIFF -d BEI16` | `mutagen.aiff` ID3v2.3 chunk |
| `tagged.m4a` | `afconvert -f m4af -d aac` | `©nam ©ART ©alb aART ©gen ©day trkn tmpo ©cmt` + freeform `----:com.apple.iTunes:initialkey` |
| `untagged/Library Artist - Library Song.mp3` | `lameenc` | none |
| `untagged/Library Song.mp3` | `lameenc` | none |
| `title-only.mp3`, `artist-only.mp3` | `lameenc` | TIT2 only / TPE1 only |

- [ ] **Step 1: Write `library.py`.** `write_library_fixtures(root: Path) -> None` writes the table above under `Tests/Fixtures/Library/`, calling `afconvert` through `subprocess.run([...], check=True)` (argument arrays, no shell). Tag with `mutagen` frame classes (`TIT2`, `TPE1`, `TALB`, `TPE2`, `TCON`, `TYER`/`TDRC`, `TRCK`, `TBPM`, `TKEY`, `COMM(lang="eng")`). Write `manifest.json`: per file, `container`, `expected` tags, `size`. Regenerating twice produces byte-identical MP3/WAV/AIFF/FLAC files (M4A may embed a timestamp; the manifest records its size after writing).
- [ ] **Step 2: Generate and check.** Run `cd scripts && uv lock && cd .. && ./scripts/generate-fixtures.sh && afinfo Tests/Fixtures/Library/tagged.m4a | grep 'File type'`. Expected: `File type ID:   m4af`.
- [ ] **Step 3: Register the folder.** In `project.pbxproj`, add a `PBXFileReference` for `Library` with `lastKnownFileType = folder;` in the `Fixtures` group (`B40000003`), and a `PBXBuildFile` in the AmpXTests Resources phase next to `short.wav` (`B10000009`). Keep existing IDs; pick unused `B1…`/`B2…` IDs.
- [ ] **Step 4: Write the probe tests.** In `LibraryMetadataGateTests`:
  - `testFixtureFolderIsBundled`: `Bundle(for: Self.self).resourceURL!.appendingPathComponent("Library/manifest.json")` exists.
  - `testRecordMetadataMatrix`: for each tagged fixture, load `.commonMetadata` and every format from `.availableMetadataFormats` via `loadMetadata(for:)`; for each spec field (album, albumArtist, genre, year, trackNumber, bpm, musicalKey, comment, sampleRate, channels, estimatedDataRate) record the identifier that yielded it or `absent`. `print("LIBRARY-GATE metadata \(json)")`. Asserts only that each file has a positive duration and one audio track.
  - `testAIFFAndM4APlay`: `AudioPlayer(installRemoteCommands: false)`, `loadTrack` with an `XCTestExpectation` fulfilled on `true`, then `play()` and `stop()`, following `PlaybackIntegrationTests`.
- [ ] **Step 5: Run `LibraryMetadataGateTests`.** Expected PASS. Collect the matrix: `grep 'LIBRARY-GATE' /tmp/ampx_gate.log` after re-running with `2>&1 | tee /tmp/ampx_gate.log | grep -E …`.
- [ ] **Step 6: Record** the matrix under spec *L1 gate results → Metadata* (field × container: identifier or `absent → <declared absent value>`) and the playback result. A playback failure removes that extension from Task 4's widening; record it.
- [ ] **Step 7: Commit** `test: generate library fixtures and record metadata gate` (scripts, pbxproj, test, spec).

## Task 2: Content fingerprint

**Files:** Create `Sources/Library/LibraryFingerprint.swift`, `Tests/AmpXTests/LibraryFingerprintTests.swift`.

**Interfaces:**
- Produces: `enum LibraryFingerprint { static func read(from url: URL) throws -> Data }`, `static let sampleLength = 65_536`.

- [ ] **Step 1: Write failing tests** with temp files the test writes. Expected digest:

```swift
func expected(_ bytes: [UInt8]) -> Data {
    var hasher = SHA256()
    withUnsafeBytes(of: UInt64(bytes.count).littleEndian) { hasher.update(bufferPointer: $0) }
    hasher.update(data: Data(bytes.prefix(65_536)))
    hasher.update(data: Data(bytes.suffix(65_536)))
    return Data(hasher.finalize())
}
```

Tests: `testEmptyFile`, `testSeventeenBytes`, `testExactly128KiB`, `testOverlappingHeadTail` (100 KiB), `testLargeFile` (1 MiB), `testChangedHeadChangesDigest`, `testChangedTailChangesDigest`, `testDeterministic`, `testMissingFileThrows`.
- [ ] **Step 2: Run `LibraryFingerprintTests`.** Expected FAIL (`cannot find 'LibraryFingerprint'`).
- [ ] **Step 3: Implement** with a read-only `FileHandle`, `defer { try? handle.close() }`, `seekToEnd()` for size, `read(upToCount:)` at 0 and `size - min(size, 65_536)`; a short read throws `CocoaError(.fileReadCorruptFile)`.
- [ ] **Step 4: Run `LibraryFingerprintTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: add library content fingerprint`.

## Task 3: File-system gate — rename evidence, case sensitivity, cost

**Files:** Create `scripts/library-gate-rename.swift`, `Sources/Library/LibraryRenameTracking.swift`, `Tests/AmpXTests/LibraryGateFileSystemTests.swift`. Modify the spec's *L1 gate results*.

**Interfaces:**
- Consumes: `LibraryFingerprint.read(from:)`, `TrackMetadataLoader.load(from:)`.
- Produces: `enum LibraryRenameTracking { static let verifiedVolumeTypes: Set<String>; static func isEnabled(volumeType: String) -> Bool }`, with the set holding exactly the `volumeTypeNameKey` strings that passed.

Prefetch keys used everywhere in this task (and by Task 7's walk): `.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .volumeIdentifierKey`.

- [ ] **Step 1: Write the rename probe script.** `swift scripts/library-gate-rename.swift <dir>` creates `gate-a.bin` (64 KiB), reads the prefetch keys plus `.volumeTypeNameKey` and `.volumeSupportsCaseSensitiveNamesKey` through `FileManager.enumerator(at:includingPropertiesForKeys:)`, renames it to `gate-b.bin`, moves it to `sub/gate-b.bin`, re-reads after each, deletes its files, and prints one JSON line: `{"volumeType", "caseSensitive", "renamePreserved", "movePreserved", "before", "afterRename", "afterMove"}` with dates as `timeIntervalSinceReferenceDate` doubles. Preserved means `fileSize` and `contentModificationDate` compare equal.
- [ ] **Step 2: Measure HFS+ and exFAT on disk images.**

```bash
G=$(mktemp -d)
hdiutil create -quiet -size 64m -fs HFS+ -volname gatehfs "$G/hfs.dmg"
hdiutil attach -nobrowse -quiet -mountpoint "$G/hfs" "$G/hfs.dmg"
swift scripts/library-gate-rename.swift "$G/hfs"
hdiutil detach -quiet "$G/hfs"
```

Repeat with `-fs ExFAT`. If an SMB share is mounted, run the script on a writable folder in it; otherwise SMB is *unmeasured*. Expected: one JSON line per file system.
- [ ] **Step 3: Write the sandboxed tests.**
  - `testAPFSRenameEvidenceInContainer`: same procedure as the script in `FileManager.default.temporaryDirectory`; assert `volumeTypeName == "apfs"`, case-sensitivity key non-nil, rename and move preserved; print `LIBRARY-GATE rename …`.
  - `testSyntheticNoChangeWalk11k`: create 11,000 1 KiB `.mp3` files in 110 folders (setup untimed), then time one full enumeration with the prefetch keys; `XCTAssertLessThan(elapsed, 5)`; print `LIBRARY-GATE walk11k …`.
  - `testRealCollectionCost` — skipped unless `ProcessInfo.processInfo.environment["AMPX_LIBRARY_GATE"] == "1"` (set by `TEST_RUNNER_AMPX_LIBRARY_GATE=1`). Real home is `String(cString: getpwuid(getuid())!.pointee.pw_dir)`, not `NSHomeDirectory()` (the container). Enumerate `~/Music/DJ` skipping `_library`, dotfiles and packages, keeping `aif aiff flac m4a mp3 wav` case-insensitively; assert count `2_232` and no-change walk `< 2` s; then time `TrackMetadataLoader.load` + `LibraryFingerprint.read` for every file, assert `< 60` s; count genre values and print them. If enumeration fails with a permission error, fail with `"Music entitlement does not cover ~/Music/DJ"`.
- [ ] **Step 4: Run** `LibraryGateFileSystemTests` normally (real-collection test skipped), then with `TEST_RUNNER_AMPX_LIBRARY_GATE=1` prefixed. Expected PASS both times.
- [ ] **Step 5: Write `LibraryRenameTracking`** with `verifiedVolumeTypes` equal to the passing file systems' reported strings (expected `["apfs", "hfs", "exfat"]` plus `"smbfs"` only if measured and passing).
- [ ] **Step 6: Record and decide.** Fill spec *L1 gate results* with: rename table (type, preserved, source), case sensitivity, the three timings with hardware (`sysctl -n machdep.cpu.brand_string`, macOS version), cache state (runs 1 and 2), genre counts. Mark SMB and spinning drive *unmeasured* with reason when absent. Apply the spec's gate exit rule. A failed **required** budget stops the plan here with a spec amendment.
- [ ] **Step 7: Commit** `test: record library file-system gate`.

## Task 4: Metadata extraction and extension widening

**Files:** Modify `Sources/Track.swift`, `Sources/M3UParser.swift`, `Sources/PlaylistManager.swift:660`. Create `Tests/AmpXTests/TrackMetadataLoaderTests.swift`, `Tests/AmpXTests/LibraryExtensionsTests.swift`.

**Interfaces:**
- Produces (in `Sources/Track.swift`):

```swift
struct Metadata: Sendable {
    var title: String
    var artist: String
    var duration: TimeInterval
    var fileSize: Int64
    var album = ""
    var albumArtist = ""
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var bitrate = 0
    var bitrateIsDerived = false
    var sampleRate = 0
    var channels = 0
    var codec = ""
    var bpm: Double?
    var musicalKey: String?
    var comment: String?
    var readFailed = false
}
```

`var` fields keep the memberwise initializer usable with only the first four arguments, so existing `Metadata(title:artist:duration:fileSize:)` call sites compile unchanged.

- [ ] **Step 1: Write failing tests** from Task 1's matrix. Per tagged fixture, each field the matrix says is exposed equals the manifest value; each absent field equals its declared absent value. Plus:
  - `testUntaggedArtistSongUsesParser` (`Library Artist` / `Library Song`), `testUntaggedStemUsesUnknownArtist`, `testTitleOnlyKeepsUnknownArtist`, `testArtistOnlyKeepsFilenameTitle`.
  - `testTrackLoadAgreesWithLoader` for all fixtures on title/artist/duration/fileSize.
  - `testCodecFromExtension`: `.aif` → `aiff`; `testUppercaseExtensionCodec`: copy of `tagged-v23.mp3` renamed `X.MP3` → `mp3`.
  - `testTrackNumberParsesSlash` (`3/12` → 3), `testDerivedBitrateWhenNoEstimate` (derived flag true only when computed), `testMissingFileSetsReadFailed` (`duration == 0`, `readFailed`).
- [ ] **Step 2: Run `TrackMetadataLoaderTests`.** Expected FAIL.
- [ ] **Step 3: Implement.** Keep the title/artist block exactly as today. Read the other fields with the identifiers Task 1 recorded. `readFailed` is true when `asset.load(.duration)` or `asset.loadTracks(withMediaType: .audio)` throws. Key normalization: trim, collapse spaces, uppercase the first letter, keep `m`/`#` as tagged. Derived bitrate:

```swift
let derived = duration.isFinite && duration > 0 ? Double(fileSize) * 8 / duration : 0
let bitrate = derived.isFinite && derived > 0 && derived < Double(Int.max) ? Int(derived.rounded()) : 0
```

- [ ] **Step 4: Run `TrackMetadataLoaderTests TrackTests TrackMetadataParserTests`.** Expected PASS.
- [ ] **Step 5: Write `LibraryExtensionsTests`** (`AIF`, `aiff`, `M4A` supported; `ogg` not; `PlaylistManager.addFilesPanelContentTypes` contains `.aiff`, `.mpeg4Audio`, and the `m3u` type). Run it: expected FAIL.
- [ ] **Step 6: Widen** (only extensions whose playback passed in Task 1) `supportedExtensions = ["mp3", "flac", "wav", "aif", "aiff", "m4a"]`. In `PlaylistManager`, add `static var addFilesPanelContentTypes: [UTType]` built from `M3UParser.supportedExtensions` plus `m3u` via `UTType(filenameExtension:)`, and use it in `showFilePicker()`.
- [ ] **Step 7: Run `LibraryExtensionsTests M3UParserTests PlaylistImportTests PlaylistManagerTests`.** Expected PASS.
- [ ] **Step 8: Commit** `feat: extract library metadata and accept AIFF/M4A`.

## Task 5: Shared bookmark primitive

**Files:** Create `Sources/Playlist/SecurityScopedBookmark.swift`, `Tests/AmpXTests/SecurityScopedBookmarkTests.swift`. Modify `Sources/Playlist/SecurityScopedBookmarkStore.swift` (remove private `ResolvedBookmark`, `resolveBookmark`, `refreshBookmarkData`; call the helper).

**Interfaces:**
- Produces:

```swift
struct ResolvedBookmark: Sendable { let url: URL; let isStale: Bool; let usesSecurityScope: Bool }
enum SecurityScopedBookmark {
    static func makeData(for url: URL, usesSecurityScope: Bool = true) throws -> Data
    static func resolve(_ data: Data) -> ResolvedBookmark?
    static func refreshedData(for url: URL, usesSecurityScope: Bool) -> Data?
}
```

- [ ] **Step 1: Write failing tests:** `testMalformedDataResolvesNil` (`Data([0, 1, 2])`), `testPlainRoundTrip` (standardized URLs equal), `testRefreshedDataResolvesAfterRename` (rename the temp folder, resolve, refresh, resolve again → new URL).
- [ ] **Step 2: Run `SecurityScopedBookmarkTests`.** Expected FAIL.
- [ ] **Step 3: Move the implementations** verbatim (security-scoped then plain fallback, `.withoutUI`, same creation options).
- [ ] **Step 4: Run `SecurityScopedBookmarkTests SecurityScopedBookmarkStoreTests PlaylistFileServiceTests`.** Expected PASS with the store tests unmodified.
- [ ] **Step 5: Commit** `refactor: share bookmark primitives with library roots`.

## Task 6: Value contracts, schema, container factory

**Files:** Create `Sources/Library/LibraryValues.swift`, `Sources/Library/LibrarySchemaV1.swift`, `Tests/AmpXTests/LibraryTestSupport.swift`, `Tests/AmpXTests/LibrarySchemaMigrationTests.swift`.

**Interfaces:**
- Produces (`LibraryValues.swift`): `LibraryRow` exactly as the spec's struct plus `func makeTrack() -> Track`, and:

```swift
struct LibraryStat: Hashable, Sendable { let fileSize: Int64; let contentModifiedAt: Date }
struct LibraryHistory: Equatable, Sendable { var playCount: Int; var lastPlayedAt: Date?; var rating: Int }
struct LibraryRowKey: Sendable {
    let id: UUID; let relativePath: String; let stat: LibraryStat; let fingerprint: Data?
    let dateAdded: Date; let history: LibraryHistory; let isMissing: Bool
}
struct LibraryRootSnapshot: Sendable, Equatable {
    let id: UUID; let url: URL; let displayPath: String; let isAvailable: Bool
    let unreadableFolderCount: Int; let lastCompletedScanAt: Date?
}
struct LibraryEntry: Sendable, Equatable { let relativePath: String; let stat: LibraryStat }
enum LibraryCoverage: Equatable, Sendable { case complete, partial(uncoveredFolders: Set<String>), aborted }
struct LibraryVolume: Sendable, Equatable { let caseSensitive: Bool; let typeName: String
    var renameTrackingEnabled: Bool { LibraryRenameTracking.isEnabled(volumeType: typeName) } }
struct LibraryWalk: Sendable { let entries: [LibraryEntry]; let coverage: LibraryCoverage; let volume: LibraryVolume }
struct LibraryParseWrite: Sendable {
    let id: UUID; let isInsert: Bool; let relativePath: String; let stat: LibraryStat
    let metadata: TrackMetadataLoader.Metadata; let fingerprint: Data?
}
enum LibraryChange: Sendable, Equatable { case rootsChanged(rootID: UUID), rootRemoved(rootID: UUID), rowsChanged(rootID: UUID) }
struct ScanProgress: Sendable, Equatable { enum Phase: Sendable { case walking, reconciling, parsing }
    let rootID: UUID; let phase: Phase; let done: Int; let total: Int }
```

- Produces (`LibrarySchemaV1.swift`): `enum LibrarySchemaV1: VersionedSchema` (version `1.0.0`) with nested `@Model final class LibraryRoot`, `LibraryTrack` carrying every spec field and default; `typealias LibraryRoot = LibrarySchemaV1.LibraryRoot`, `LibraryTrack = LibrarySchemaV1.LibraryTrack`; `LibraryMigrationPlan` with `schemas = [LibrarySchemaV1.self]`, `stages = []`; and

```swift
enum LibraryContainerFactory {
    /// nil URL = in-memory. Always applies LibraryMigrationPlan. Never deletes a store on failure.
    static func make(url: URL?) throws -> ModelContainer
    static var defaultURL: URL { get }   // Application Support/AmpX/Library/Library.store
}
```

- Produces (test support): `LibraryTestSupport.key(id:path:stat:fingerprint:history:missing:)`, `entry(path:stat:)`, `walk(entries:coverage:caseSensitive:renameTracking:)` (defaults: complete, case-sensitive, `typeName: "apfs"` when tracking on else `"test-disabled"`), `stat(_ size: Int64, _ seconds: TimeInterval)`, `temporaryDirectory()` with `addTeardownBlock` cleanup.

- [ ] **Step 1: Write `testV1OnDiskRoundTrip`:** insert one root and one track with nonzero `playCount`, `rating`, `lastPlayedAt`, every optional set; drop the container; reopen with `LibraryContainerFactory.make(url:)`; compare every field. And `testMakeTrackCarriesFileSizeAndURL` (two calls → different `id`, same `fileSize`, `url`).
- [ ] **Step 2: Run `LibrarySchemaMigrationTests`.** Expected FAIL.
- [ ] **Step 3: Implement** values and schema. Only `id` is `@Attribute(.unique)`. `#Index<LibraryTrack>([\.rootID], [\.rootID, \.relativePath])`. `schemaVersion` defaults to 1.
- [ ] **Step 4: Add `testLightweightMigrationToTestV2`.** A test-only `LibraryTestSchemaV2` (same class names nested in its own enum, one added optional `camelotKey: String?`) with a `.lightweight` stage from V1. Open a V1 store, migrate, assert every V1 value and reserved field, reopen once more (idempotent). A test-only `.custom` stage `didMigrate` stamps `schemaVersion = 2`; assert it.
- [ ] **Step 5: Run `LibrarySchemaMigrationTests`.** Expected PASS.
- [ ] **Step 6: Commit** `feat: define library values and versioned schema`.

## Task 7: File-system adapter and pure reconciler

**Files:** Create `Sources/Library/LibraryFileSystem.swift`, `Sources/Library/LibraryReconciler.swift`, `Tests/AmpXTests/LibraryReconcilerTests.swift`, `Tests/AmpXTests/LibraryFileSystemTests.swift`. Extend test support with `FakeLibraryFileSystem` (actor; scripted walks, stats, fingerprints; counters `walkCount`, `statCount`, `fingerprintCount`).

**Interfaces:**
- Produces:

```swift
protocol LibraryFileSystem: Sendable {
    func volume(at root: URL) async throws -> LibraryVolume
    func walk(root: URL, volume: LibraryVolume) async throws -> LibraryWalk
    func stat(at url: URL) async throws -> LibraryStat
    func fingerprint(at url: URL) async throws -> Data
    func isReachable(_ root: URL) async -> Bool
}
struct FoundationLibraryFileSystem: LibraryFileSystem { init() }

struct LibraryMove: Equatable, Sendable { let id: UUID; let relativePath: String }
struct LibraryIntegrityMerge: Equatable, Sendable { let survivorID: UUID; let deletedIDs: Set<UUID>; let history: LibraryHistory }
struct LibraryReconciliation: Equatable, Sendable {
    let moves: [LibraryMove]; let spellingUpdates: [LibraryMove]
    let foundIDs: Set<UUID>; let missingIDs: Set<UUID>
    let newEntries: [LibraryEntry]; let staleIDs: Set<UUID>
    static let empty: LibraryReconciliation
}
enum LibraryReconciler {
    static func pathKey(_ path: String, caseSensitive: Bool) -> String
    static func integrityMerges(rows: [LibraryRowKey], caseSensitive: Bool) -> [LibraryIntegrityMerge]
    static func candidatePaths(rows: [LibraryRowKey], walk: LibraryWalk) -> [String]
    static func reconcile(rows: [LibraryRowKey], walk: LibraryWalk, fingerprints: [String: Data]) -> LibraryReconciliation
}
```

`staleIDs` = matched or moved rows whose walked stat differs from the stored stat. Outputs are sorted (paths, then UUID strings) for deterministic tests.

- [ ] **Step 1: Write the reconciler tests** (use builders; fixed UUID literals). `testUpdateBeforeInsertMovesOnFirstRun`:

```swift
let k = LibraryTestSupport.stat(1_000, 10), k2 = LibraryTestSupport.stat(2_000, 20)
let rows = [key(id: a, path: "A.mp3", stat: k, fingerprint: fp), key(id: x, path: "X.mp3", stat: k, fingerprint: fp)]
let walk = walk(entries: [entry(path: "B.mp3", stat: k), entry(path: "X.mp3", stat: k2)])
let plan = LibraryReconciler.reconcile(rows: rows, walk: walk, fingerprints: ["B.mp3": fp])
XCTAssertEqual(plan.moves, [LibraryMove(id: a, relativePath: "B.mp3")])
XCTAssertEqual(plan.staleIDs, [x])
XCTAssertTrue(plan.newEntries.isEmpty)
```

Also: `testHardLinksNeverMove` (entries B, C with K → no move, A missing; and after B inserted, rows {A, B} → still no move), `testMatchedEntryWithSameStatBlocksMove`, `testMatchedRowStoredStatIsIgnored`, `testTwoUnmatchedRowsBlockMove`, `testMissingRowFromEarlierScanCountsInU`, `testNilRowFingerprintBlocksMove`, `testFingerprintMismatchBlocksMove`, `testUnreadableFingerprintBlocksMove`, `testRenameTrackingDisabledBlocksMove`, `testPartialWalkNeverMovesAndSetsAsideUncovered` (hidden link case), `testUncoveredPrefixIsComponentAware` (`crate` vs `crate2`), `testAbortedWalkIsEmpty`, `testCaseOnlyRenameOnCaseInsensitiveVolumeIsSpellingUpdate`, `testCaseOnlyRenameOnCaseSensitiveVolumeUsesRenameRule`, `testNFDSpellingMatchesNFCRow`, `testCandidatePathsMatchReconcileEligibility`, and integrity: `testMergeTwoDuplicates`, `testMergeThreeDuplicatesCombinesHistory` (oldest `dateAdded` then smallest UUID survives; max `playCount`; latest `lastPlayedAt`; survivor rating unless 0, else first non-zero by `dateAdded`, UUID).
- [ ] **Step 2: Run `LibraryReconcilerTests`.** Expected FAIL.
- [ ] **Step 3: Implement.** `pathKey` = NFC (`precomposedStringWithCanonicalMapping`), then `lowercased()` when case-insensitive. One private `eligibility(rows:walk:)` feeds both `candidatePaths` and `reconcile`:

```swift
// U = rows not path-matched and not inside an uncovered folder; N = unmatched entries.
guard walk.coverage == .complete, walk.volume.renameTrackingEnabled else { no candidates }
let walkedByStat = Dictionary(grouping: walk.entries, by: \.stat)   // all entries, matched or not
let unmatchedByStat = Dictionary(grouping: u, by: \.stat)           // stored stats of U only
// candidate(entry in N, row in U) iff walkedByStat[s]?.count == 1 && unmatchedByStat[s]?.count == 1
//   && row.fingerprint != nil; move iff fingerprints[entry.relativePath] == row.fingerprint
```

- [ ] **Step 4: Run `LibraryReconcilerTests`.** Expected PASS.
- [ ] **Step 5: Write `LibraryFileSystemTests`** on real temp trees: `testWalkReadsNoContents` (walk a tree whose files are unreadable `chmod 000` except directory listing → complete, all entries), `testUnreadableFolderMakesWalkPartial`, `testMissingRootThrows` (not an empty complete walk), `testExcludesDotfilesPackagesAndReservedFolders` (`_extracted`, `_library`, `.DS_Store`, `X.app/`), `testWalkAcceptsUppercaseExtensions`, `testRelativePathRoundTripsPunctuation` (`Hard Groove (128k)/Drum & Bass #1.mp3`), `testSymlinkedRootProducesStableRelativePaths`, `testVolumeReportsAPFS`, `testStatMatchesWalk`, `testCancellationAbortsWalk`.
- [ ] **Step 6: Run `LibraryFileSystemTests`.** Expected FAIL.
- [ ] **Step 7: Implement `FoundationLibraryFileSystem`.** Resolve the root with `resolvingSymlinksInPath()` before computing relative paths. Blocking enumeration runs in `Task.detached(priority: .utility)`, checking `Task.isCancelled` every 256 entries (cancelled → `.aborted`). `errorHandler` adds the failing URL's directory (relative) to uncovered folders and returns `true`. Skip descendants whose `volumeIdentifierKey` differs from the root's. Extensions: `M3UParser.isSupportedAudioExtension`. `fingerprint(at:)` = `LibraryFingerprint.read`. `isReachable` = directory exists and is readable.
- [ ] **Step 8: Run `LibraryFileSystemTests LibraryReconcilerTests`.** Expected PASS.
- [ ] **Step 9: Commit** `feat: reconcile library rows from walk evidence`.

## Task 8: Writer actor, scan tokens, change publication

**Files:** Create `Sources/Library/LibraryStore.swift`, `Tests/AmpXTests/LibraryStoreTests.swift`, `Tests/AmpXTests/LibraryScanTokenTests.swift`.

**Interfaces:**
- Produces:

```swift
protocol LibraryStartupFlag: Sendable { var hasRoots: Bool { get }; func setHasRoots(_ value: Bool) }
final class UserDefaultsLibraryStartupFlag: LibraryStartupFlag, @unchecked Sendable {
    static let key = "AmpXLibraryHasRoots"
    init(defaults: UserDefaults)
}
struct LibrarySecurityScope: Sendable {
    var start: @Sendable (URL) -> Bool
    var stop: @Sendable (URL) -> Void
    static let foundation: LibrarySecurityScope
}
struct LibraryBookmarking: Sendable {
    var make: @Sendable (URL) throws -> Data
    var resolve: @Sendable (Data) -> ResolvedBookmark?
    var refresh: @Sendable (URL, Bool) -> Data?
    static let securityScoped: LibraryBookmarking   // SecurityScopedBookmark with usesSecurityScope: true
}
struct LibraryStoreDependencies: Sendable {
    var startupFlag: any LibraryStartupFlag
    var scope: LibrarySecurityScope = .foundation
    var bookmarks: LibraryBookmarking = .securityScoped
    var saveContext: @Sendable (ModelContext) throws -> Void = { try $0.save() }
    var now: @Sendable () -> Date = { Date() }
}
struct LibraryScanToken: Hashable, Sendable { let rootID: UUID; fileprivate let nonce: UUID }
enum LibraryStoreError: Error, Equatable {
    case unknownRoot, revokedToken, overlappingRoot, unavailableRoot, pathCollision(String)
}

actor LibraryStore: ModelActor {
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer
    init(modelContainer: ModelContainer, dependencies: LibraryStoreDependencies)

    func changes() -> AsyncStream<LibraryChange>
    func beginScan(rootID: UUID) throws -> LibraryScanToken
    func revokeScan(rootID: UUID)
    func rowKeys(rootID: UUID) throws -> [LibraryRowKey]
    func applyIntegrityMerges(_ merges: [LibraryIntegrityMerge], token: LibraryScanToken) throws
    func applyStructure(_ plan: LibraryReconciliation, token: LibraryScanToken, unreadableFolderCount: Int) throws
    func applyParsed(_ writes: [LibraryParseWrite], token: LibraryScanToken) throws   // ≤ 200 writes
    func finishScan(token: LibraryScanToken) throws                                   // complete walks only
}
```

The single init is the only way to build the actor, so it is never usable half-configured. It creates `ModelContext(modelContainer)`, sets `autosaveEnabled = false`, and wraps it in `DefaultSerialModelExecutor(modelContext:)` — what `@ModelActor` would generate, plus the dependencies.

- [ ] **Step 1: Write token tests** with `LibraryContainerFactory.make(url: nil)`, a root seeded through a test-owned `ModelContext`, and `startupFlag` from an isolated suite. `testRevokedTokenRejectsStructureAndParse` (both throw `.revokedToken`, rows unchanged, no change emitted), `testReissuedTokenKeepsOldRejected`, `testDeletedRootRejectsToken`, `testLateWriteAfterReissueIsRejected` (write suspended on a `TestBarrier` actor, token reissued, barrier opened → rejected). No sleeps.
- [ ] **Step 2: Run `LibraryScanTokenTests`.** Expected FAIL.
- [ ] **Step 3: Implement** tokens and the transaction helper; every mutating method uses it:

```swift
private func commit(_ token: LibraryScanToken?, _ changes: [LibraryChange], _ mutate: () throws -> Void) throws {
    if let token { guard activeTokens[token.rootID] == token else { throw LibraryStoreError.revokedToken } }
    do { try mutate(); try dependencies.saveContext(modelContext) }
    catch { modelContext.rollback(); throw error }
    for change in changes { for continuation in subscribers.values { continuation.yield(change) } }
}
```

No `await` inside. `changes()` registers a new continuation per call and removes it `onTermination`. `commit`, `activeTokens`, `subscribers` and `dependencies` are internal (not `private`) so Task 9's `LibraryStore+Roots.swift` extension can use them.
- [ ] **Step 4: Run `LibraryScanTokenTests`.** Expected PASS.
- [ ] **Step 5: Write store tests:** `testInsertUpdateRoundTripPreservesHistoryAndDateAdded`, `testApplyParsedRejectsMoreThan200`, `testInsertCollidingPathKeyThrows` (`.pathCollision`, nothing saved), `testStructureSaveIsAtomic` (moves + spelling + found + missing + count in one save), `testIntegrityMergeAppliesHistoryAndDeletes`, `testFailedSaveRollsBackAndPublishesNothing` (injected `saveContext` throws once; next transaction clean), `testOneSaveCanPublishRootsAndRowsChanged`, `testTwoSubscribersBothReceive`, `testFinishScanSetsLastCompletedScanAt`.
- [ ] **Step 6: Run `LibraryStoreTests`.** Expected FAIL, then implement the remaining methods, then expected PASS.
- [ ] **Step 7: Commit** `feat: persist library changes behind revocable scan tokens`.

## Task 9: Roots, security scope, start-up flag

**Files:** Create `Sources/Library/LibraryStore+Roots.swift`, `Tests/AmpXTests/LibraryRootTests.swift`. Extend test support with `ScopeSpy` (actor-safe start/stop log) and `FlagSpy` (records `setHasRoots` order relative to saves via a shared event log).

**Interfaces:**
- Consumes: Task 8's store and dependencies.
- Produces (on `LibraryStore`):

```swift
func roots() throws -> [LibraryRootSnapshot]
func addRoot(url: URL) throws -> UUID                 // sets flag first; publishes rootsChanged; starts scope
func relocateRoot(id: UUID, to url: URL) throws       // revokes token; keeps rootID/relativePaths
func removeRoot(id: UUID) throws                      // revokes; deletes root + rows; clears flag after save if last
func markUnavailable(id: UUID) throws                 // revokes; isAvailable = false; rows untouched
func resolveRoot(token: LibraryScanToken) throws -> LibraryRootSnapshot
    // step 0: resolve/refresh bookmark, start scope, save availability/displayPath when changed;
    // failure saves isAvailable = false and throws .unavailableRoot
func startAccessForAvailableRoots() throws -> [LibraryRootSnapshot]   // engine start-up
func stopAllAccess()
```

Overlap uses standardized, symlink-resolved path components: equal, ancestor or descendant → `.overlappingRoot`; relocation excludes the root being relocated.

- [ ] **Step 1: Write failing tests:** `testAddRejectsEqualAncestorDescendantAndSymlinkAlias`, `testRelocateRejectsOverlapExcludingSelf`, `testMarkUnavailableRevokesRunningToken` (the spec example: `applyParsed([], token:)` after `markUnavailable` throws `.revokedToken`), `testUnavailableKeepsIsMissing`, `testRelocatePreservesRowsAndHistory`, `testRemoveDeletesOnlyThatRootsRows`, `testAddSetsFlagBeforeInsert`, `testRemoveLastRootClearsFlagAfterSave`, `testRemoveNonLastRootKeepsFlag`, `testScopeStartsOncePerRootAndStopsOnRemove`, `testStopAllAccessBalancesScopes`, `testResolveFailureSavesUnavailable`. Tests use `LibraryBookmarking` with `usesSecurityScope: false` data and a `ScopeSpy`.
- [ ] **Step 2: Run `LibraryRootTests`.** Expected FAIL.
- [ ] **Step 3: Implement** in `LibraryStore+Roots.swift` using Task 8's `commit`. The store keeps `activeScopes: [UUID: URL]`.
- [ ] **Step 4: Run `LibraryRootTests LibraryStoreTests LibraryScanTokenTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: manage library roots, scopes and start-up flag`.

## Task 10: One scan run

**Files:** Create `Sources/Library/LibraryScanner.swift`, `Tests/AmpXTests/LibraryScannerTests.swift`, `Tests/AmpXTests/LibraryIdentityTests.swift`.

**Interfaces:**
- Consumes: store (Tasks 8–9), `LibraryFileSystem`, `LibraryReconciler`.
- Produces:

```swift
typealias LibraryMetadataLoading = @Sendable (URL) async -> TrackMetadataLoader.Metadata
struct LibraryScanOutcome: Sendable, Equatable { let coverage: LibraryCoverage; let needsFollowUp: Bool }
actor LibraryScanner {
    init(store: LibraryStore, fileSystem: any LibraryFileSystem,
         loadMetadata: @escaping LibraryMetadataLoading = { await TrackMetadataLoader.load(from: $0) },
         batchSize: Int = 200)
    func scanOnce(rootID: UUID) async throws -> LibraryScanOutcome
    func progress() -> AsyncStream<ScanProgress>
}
```

`scanOnce` order: `beginScan` → `resolveRoot` → `volume(at:)` → `rowKeys` → `integrityMerges` (apply + re-read keys if non-empty) → `walk` (`.aborted` → return, nothing saved) → `candidatePaths` → fingerprints for those only → `reconcile` → `applyStructure` → parse `staleIDs` + `newEntries` in batches → `finishScan` if complete.

Per parsed file: `before = walked stat`; load metadata and fingerprint; `after = try await fileSystem.stat(at:)`. If `after != before`, skip the write and set `needsFollowUp`. If the load or fingerprint failed, check `isReachable(root)`: unreachable → `markUnavailable` and throw `CancellationError`; reachable → write with `fingerprint: nil` / degraded metadata and log once per file per run (`Logger(subsystem: "com.ampx.macos", category: "Library")`).

- [ ] **Step 1: Write `testNoChangeScanReadsNothing`** (seeded rows equal to walked entries; `fake.fingerprintCount == 0`, loader spy count 0, `statCount == 0`). Run `LibraryScannerTests`: expected FAIL.
- [ ] **Step 2: Implement `scanOnce`** as ordered above. Build file URLs with `root.url.appendingPathComponent(relativePath)`.
- [ ] **Step 3: Add scanner tests:** `testNewFilesInsertedInBatchesOf200` (450 entries → 3 `applyParsed` calls), `testPartialWalkInsertsButNeverMoves`, `testAbortedWalkSavesNothingAfterRepair`, `testOnlyCompleteWalkSetsLastCompletedScanAt`, `testFileChangedDuringReadIsLeftStaleAndRequestsFollowUp`, `testCorruptFileInsertsDegradedRow` (zero-byte `.mp3` on a reachable root: `duration == 0`, row inserted, one log), `testVanishedRootAbortsWithoutDegradedRow`, `testRevokedMidParseRejectsRemainingBatches`, `testDuplicateRowsRepairedBeforeMatching`.
- [ ] **Step 4: Add identity tests** (on-disk temp store, fixed UUIDs, nonzero history): `testRenameKeepsIDAndHistoryWithNoInsertBeforeStructureSave`, `testPathSwapKeepsRowsOnPaths`, `testContentReplacedAtPathKeepsRow`, `testCaseOnlyRenameKeepsRowOnBothVolumeKinds`, and `testInterruptionAtEveryBatchBoundaryMatchesUninterrupted` — for the update-before-insert and hard-link inventories padded with 300 unrelated files, throw from a fake-loader barrier after the structure save and after each batch, reopen the store, rescan with the same fake file system, and compare `(relativePath, history, metadata, isMissing)` by path plus original IDs; freshly minted IDs are compared by path only.
- [ ] **Step 5: Run `LibraryScannerTests LibraryIdentityTests LibraryReconcilerTests LibraryScanTokenTests`.** Expected PASS.
- [ ] **Step 6: Commit** `feat: scan library roots without identity drift`.

## Task 11: Scan scheduling

**Files:** Create `Sources/Library/LibraryScanner+Scheduling.swift`, `Tests/AmpXTests/LibraryScanSchedulingTests.swift`.

**Interfaces:**
- Produces (on `LibraryScanner`): `func requestScan(rootID: UUID)`, `func cancelScans(rootID: UUID) async`, `func stop() async`, and test hook `var maxConcurrentRuns: Int { get }`.

State: `queue: [UUID]`, `queued: Set<UUID>`, `runningRoot: UUID?`, `runningTask: Task<Void, Never>?`, `rescanRequested: Set<UUID>`, `drainTask: Task<Void, Never>?`.

```swift
func requestScan(rootID: UUID) {
    if runningRoot == rootID { rescanRequested.insert(rootID) }
    else if queued.insert(rootID).inserted { queue.append(rootID) }
    startDrainIfIdle()
}
// Run completion: runningRoot = nil; if rescanRequested.remove(id) != nil || outcome.needsFollowUp { requestScan(id) }
// cancelScans: await store.revokeScan(rootID:) FIRST, then drop from queue/queued/rescanRequested,
// then cancel runningTask if runningRoot == rootID. The drain loop keeps the slot until the task returns.
```

`startDrainIfIdle` creates at most one `Task(priority: .utility)` that loops while `queue` is non-empty; the check-and-set is synchronous inside the actor, so reentrancy cannot start a second drain.

- [ ] **Step 1: Write failing tests** with a fake file system whose walk for root A blocks on a barrier: `testRequestsWhileRunningCollapseToOneFollowUp` (A ×3 + B while A runs → order A, B, A), `testQueuedRequestsCoalesce`, `testAtMostOneRunAtATime` (`maxConcurrentRuns == 1`), `testChangeInWalkedDirectoryIsPickedUpByFollowUp`, `testCancelQueuedRootNeverStarts`, `testCancelRunningRevokesBeforeCancelling` (a parse write already suspended is rejected), `testTwoRootsBothScanned`, `testErrorInOneRootContinuesQueue`.
- [ ] **Step 2: Run `LibraryScanSchedulingTests`.** Expected FAIL.
- [ ] **Step 3: Implement** as above.
- [ ] **Step 4: Run `LibraryScanSchedulingTests LibraryScannerTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: coalesce library scan requests`.

## Task 12: Query evaluation and the snapshot index

**Files:** Create `Sources/Library/LibraryQuery.swift`, `Sources/Library/LibraryIndex.swift`, `Tests/AmpXTests/LibraryQueryTests.swift`, `Tests/AmpXTests/LibraryChangePublicationTests.swift`.

**Interfaces:**
- Produces:

```swift
enum LibraryFacetValue: Hashable, Codable, Sendable { case text(String), absent }
enum LibrarySortColumn: String, Codable, Sendable { case artist, title, duration, bpm, musicalKey, bitrate }
struct LibraryQuery: Codable, Sendable, Equatable {
    var search = ""; var genres: Set<LibraryFacetValue> = []; var artists: Set<LibraryFacetValue> = []
    var albums: Set<LibraryFacetValue> = []; var sort: LibrarySortColumn = .artist; var ascending = true
    func evaluate(rows: [LibraryRow], snapshotVersion: UInt64, generation: UInt64) -> LibraryResult
}
struct LibraryFacetCounts: Sendable, Equatable { let genres, artists, albums: [LibraryFacetValue: Int] }
struct LibraryResult: Sendable { let rows: [LibraryRow]; let facets: LibraryFacetCounts; let snapshotVersion: UInt64; let generation: UInt64 }

actor LibraryIndex {
    init(container: ModelContainer, changes: AsyncStream<LibraryChange>,
         clock: any Clock<Duration> = ContinuousClock(), throttle: Duration = .seconds(1))
    func query(_ request: LibraryQuery, generation: UInt64) async throws -> LibraryResult
    func rows(ids: Set<UUID>) async throws -> [LibraryRow]
    func versions() -> AsyncStream<UInt64>
    func stop()
}
```

Facet key: nil genre / empty album → `.absent`; artist facet uses `artist`. `searchKey` = title, artist, album, albumArtist joined by spaces, folded with `[.caseInsensitive, .diacriticInsensitive]`. Tie-breaks after the chosen column: `artist`, `album`, `trackNumber` (nil last), `title`, `id.uuidString`; nil `bpm`/`musicalKey` sort last in both directions.

- [ ] **Step 1: Write failing pure query tests:** `testMultiTermFoldedSearch` (`"beyonce  crazy"` matches `Beyoncé`), `testOrWithinFacetAndAcrossFacets`, `testFacetCountsExcludeOwnSelection`, `testAbsentDistinctFromLiteralNoGenreText`, `testCountsIncludeUnavailableRows`, `testSortIsTotalOrderWithTieBreakers`, `testNilSortValuesLastBothDirections`, `testQueryCodableRoundTrip`.
- [ ] **Step 2: Run `LibraryQueryTests`.** Expected FAIL; implement `evaluate`; expected PASS.
- [ ] **Step 3: Write failing index tests** against a real store (in-memory container shared by store and index) with a controllable test clock: `testLazyBuildOnFirstQuery`, `testSaveDuringInitialLoadIsNotLost`, `testRootRemovedEvictsImmediately`, `testRootsChangedRebuildsURLsAndAvailability` (unmount, remount, relocate), `testRowsChangedThrottledWithTrailingRefetch` (5 saves in 1 s → 1 immediate + 1 trailing), `testRootChangeOverridesPendingRowRefetch`, `testRejectedTokenBumpsNoVersion`, `testIntegrityMergeUpdatesCounts`, `testEachChangeEmitsVersion`.
- [ ] **Step 4: Run `LibraryChangePublicationTests`.** Expected FAIL.
- [ ] **Step 5: Implement `LibraryIndex`.** Subscribe to `changes` in `init` (before any build) and mark roots dirty while the first load runs; refresh them before publishing the first version. Each refresh fetches through a **new** `ModelContext(container)` so committed saves are visible; only `LibraryRow` values leave the actor.
- [ ] **Step 6: Run `LibraryChangePublicationTests LibraryQueryTests`.** Expected PASS.
- [ ] **Step 7: Commit** `feat: query library snapshots independently of scan writes`.

## Task 13: File-system and mount watcher

**Files:** Create `Sources/Library/LibraryWatcher.swift`, `Tests/AmpXTests/LibraryWatcherTests.swift`.

**Interfaces:**
- Produces:

```swift
enum LibraryWatchEvent: Sendable, Equatable { case changed(UUID), rootChanged(UUID), mounted(URL), unmounted(URL) }
final class LibraryWatcher: @unchecked Sendable {   // all state on `queue`
    init(latency: TimeInterval = 2, handler: @escaping @Sendable (LibraryWatchEvent) -> Void)
    func bind(rootID: UUID, url: URL)      // replaces an existing binding for rootID
    func unbind(rootID: UUID)
    func startVolumeObservation() async   // @MainActor hop for NSWorkspace observers
    func stop() async
    func simulate(_ event: LibraryWatchEvent)   // test injection; same path as real callbacks
    var activeStreamCount: Int { get }
}
```

FSEvents ownership (one stream per root; the stream owns one retain of a box):

```swift
final class LibraryWatchBox: @unchecked Sendable { let rootID: UUID; let handler: @Sendable (LibraryWatchEvent) -> Void; var isLive = true }
var context = FSEventStreamContext(version: 0,
    info: Unmanaged.passRetained(box).toOpaque(), retain: nil,
    release: { info in info.map { Unmanaged<LibraryWatchBox>.fromOpaque($0).release() } },
    copyDescription: nil)
let callback: FSEventStreamCallback = { _, info, count, _, flags, _ in
    guard let info else { return }
    let box = Unmanaged<LibraryWatchBox>.fromOpaque(info).takeUnretainedValue()
    guard box.isLive else { return }
    let rootChanged = (0 ..< count).contains { flags[$0] & UInt32(kFSEventStreamEventFlagRootChanged) != 0 }
    box.handler(rootChanged ? .rootChanged(box.rootID) : .changed(box.rootID))
}
let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [url.path] as CFArray,
    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
    FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer))
FSEventStreamSetDispatchQueue(stream, queue); FSEventStreamStart(stream)
// Teardown: box.isLive = false; FSEventStreamStop; FSEventStreamInvalidate; FSEventStreamRelease (releases the box).
```

Every non-root-changed batch, including `MustScanSubDirs`, `UserDropped` and `KernelDropped`, maps to `.changed`. Mount/unmount use `NSWorkspace.shared.notificationCenter` `didMountNotification` / `didUnmountNotification` with `NSWorkspace.volumeURLUserInfoKey`.

- [ ] **Step 1: Write failing tests:** `testRealFileWriteProducesChanged` (temp dir, `latency: 0.1`, expectation), `testRenamingWatchedRootProducesRootChanged`, `testRebindReleasesOldStreamOnce` (`activeStreamCount` stays 1), `testStoppedBindingIgnoresLateCallbacks`, `testUnbindAndStopReleaseEverything` (`activeStreamCount == 0`), `testSimulatedMountAndUnmountReachHandler`.
- [ ] **Step 2: Run `LibraryWatcherTests`.** Expected FAIL.
- [ ] **Step 3: Implement** as above.
- [ ] **Step 4: Run `LibraryWatcherTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: watch library roots and volume mounts`.

## Task 14: Engine composition and start-up

**Files:** Create `Sources/Library/LibraryEngine.swift`, `Tests/AmpXTests/LibraryEngineTests.swift`.

**Interfaces:**
- Produces:

```swift
struct LibraryEngineConfiguration: Sendable {
    var storeURL: URL? = LibraryContainerFactory.defaultURL   // nil = in-memory (tests)
    var startupFlag: any LibraryStartupFlag
    var bookmarkStore: SecurityScopedBookmarkStore            // the one PlaylistManager uses
    var fileSystem: any LibraryFileSystem = FoundationLibraryFileSystem()
    var loadMetadata: LibraryMetadataLoading = { await TrackMetadataLoader.load(from: $0) }
    var storeDependencies: (any LibraryStartupFlag) -> LibraryStoreDependencies = { LibraryStoreDependencies(startupFlag: $0) }
    var watcherLatency: TimeInterval = 2
}
actor LibraryEngine {
    /// Flag false → returns nil without opening a container. Flag true → opens it;
    /// no roots → clears the flag, returns nil; else starts scopes, binds the watcher, queues one scan per available root.
    static func openIfConfigured(_ configuration: LibraryEngineConfiguration) async throws -> LibraryEngine?
    /// Opens unconditionally — for L2's first "Add Library Folder…".
    static func open(_ configuration: LibraryEngineConfiguration) async throws -> LibraryEngine
    nonisolated let index: LibraryIndex
    nonisolated let bookmarkStore: SecurityScopedBookmarkStore
    func roots() async throws -> [LibraryRootSnapshot]
    func progress() async -> AsyncStream<ScanProgress>
    func addRoot(url: URL) async throws -> UUID                 // store.addRoot → watcher.bind → requestScan
    func relocateRoot(id: UUID, to url: URL) async throws       // cancelScans → store → rebind → requestScan
    func removeRoot(id: UUID) async throws                      // cancelScans → store → unbind
    func handle(_ event: LibraryWatchEvent) async
    func stop() async                                           // scanner, watcher, index, scopes
}
```

Event routing: `.changed(id)` → `requestScan`; `.rootChanged(id)` → `cancelScans`, then `requestScan` (step 0 re-resolves the bookmark); `.mounted` → `requestScan` for every unavailable root; `.unmounted(volumeURL)` → for each root whose path lies under the volume URL (component-aware): `cancelScans`, `markUnavailable`.

- [ ] **Step 1: Write failing tests** (isolated defaults suite, temp store URL, fake file system):
  - `testFlagFalseOpensNoContainer`: `openIfConfigured` returns nil and the store file does not exist.
  - `testFlagTrueEmptyStoreSelfClears`: returns nil, flag false afterwards.
  - `testStartupQueuesOneScanPerAvailableRoot`.
  - `testAddScansAndPublishes`, `testRemoveCancelsScanAndUnbinds`, `testRelocateRebindsAndRescans`.
  - `testUnmountEventMarksRootsUnderVolumeUnavailable`, `testMountEventRescansUnavailableRoots`, `testRootChangedReResolves`.
  - `testStopReleasesScopesWatchersAndTasks` (`ScopeSpy` balanced, `activeStreamCount == 0`).
- [ ] **Step 2: Run `LibraryEngineTests`.** Expected FAIL.
- [ ] **Step 3: Implement.** Store and index share one `ModelContainer`; the store is constructed inside `Task(priority: .utility)`. The watcher handler forwards to `handle(_:)` through `Task { await engine?.handle(event) }` with a weak engine reference.
- [ ] **Step 4: Run `LibraryEngineTests LibraryScanSchedulingTests LibraryRootTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: compose the library engine behind an explicit start-up gate`.

## Task 15: Browser model and playlist enqueue

**Files:** Create `Sources/Library/LibraryBrowserModel.swift`, `Tests/AmpXTests/LibraryBrowserModelTests.swift`.

**Interfaces:**
- Produces:

```swift
struct LibraryBrowserServices: Sendable {
    var query: @Sendable (LibraryQuery, UInt64) async throws -> LibraryResult
    var rows: @Sendable (Set<UUID>) async throws -> [LibraryRow]
    var versions: @Sendable () async -> AsyncStream<UInt64>
    var progress: @Sendable () async -> AsyncStream<ScanProgress>
    var roots: @Sendable () async throws -> [LibraryRootSnapshot]
    static func live(_ engine: LibraryEngine) -> LibraryBrowserServices
}
@MainActor final class LibraryBrowserModel: ObservableObject {
    @Published private(set) var query: LibraryQuery
    @Published private(set) var rows: [LibraryRow]
    @Published private(set) var facets: LibraryFacetCounts
    @Published var selection: Set<UUID>
    @Published var focusedID: UUID?
    @Published private(set) var progress: ScanProgress?
    @Published private(set) var roots: [LibraryRootSnapshot]
    init(services: LibraryBrowserServices, playlist: PlaylistManager,
         bookmarkStore: SecurityScopedBookmarkStore, beep: @escaping @MainActor () -> Void = { NSSound.beep() })
    func setQuery(_ query: LibraryQuery)
    func refresh()
    func enqueue(append: Bool, clickedID: UUID?) async
    func stop()
}
```

Root management stays on `LibraryEngine`; L2 calls it with URLs from its panels.

- [ ] **Step 1: Write failing tests** with continuation-controlled `services.query`: `testLateOlderGenerationIsDropped` (start 1, start 2, deliver 2 then 1 → rows from 2), `testSelectionSurvivesRefreshAndDropsVanishedIDs`, `testFocusedIDSurvivesWhenPresent`, `testVersionBumpRerunsCurrentQuery`, `testStopCancelsTasks`.
- [ ] **Step 2: Run `LibraryBrowserModelTests`.** Expected FAIL.
- [ ] **Step 3: Implement** generation counting (`generation &+= 1`, cancel previous task, publish only if `result.generation == generation`) and the version/progress/roots subscriptions with `[weak self]`.
- [ ] **Step 4: Write failing enqueue tests** with `MockAudioPlayer`, `PlaylistManager(audioPlayer: mock, restoreBookmarks: false, restorePlaylist: false, bookmarkStore: store, stateStore: isolatedState, alertPresenter: SilentPlaylistAlertPresenter())`: `testEnterReplacesAndPlaysFirstInDisplayedOrder`, `testCommandEnterAppends`, `testClickOutsideSelectionEnqueuesOnlyClicked`, `testUnavailableOnlyBeepsAndKeepsPlaylist`, `testStaleResultRecheckedAgainstLatestRows` (`services.rows` reports unavailable), `testRemovedRootCannotBeEnqueued`, `testEnqueueRegistersRootBookmark`, `testSameRowTwiceYieldsDistinctTracks`.
- [ ] **Step 5: Implement `enqueue`.** Resolve ids through `services.rows` (latest snapshot), keep displayed order, drop unavailable, `bookmarkStore.saveBookmark(for:)` each involved root URL, build tracks with `makeTrack()`, then:

```swift
guard !tracks.isEmpty else { beep(); return }
if append { playlist.addTracks(tracks) }
else { playlist.clearPlaylist(); playlist.addTracks(tracks); playlist.playTrack(at: 0) }
```

- [ ] **Step 6: Run `LibraryBrowserModelTests PlaylistManagerTests`.** Expected PASS.
- [ ] **Step 7: Commit** `feat: expose library browser state and playlist actions`.

## Task 16: Integration, performance, success criterion 2, handoff

**Files:** Create `Tests/AmpXTests/LibraryEngineIntegrationTests.swift`, `Tests/AmpXTests/LibraryPerformanceTests.swift`, `Tests/AmpXTests/LibraryRetryPropertyTests.swift`. Update the spec's *L1 gate results* and this plan's checkboxes.

- [ ] **Step 1: Integration tests** on the Task 1 fixtures copied into a temp root, on-disk store, real `FoundationLibraryFileSystem`: add root → scan → query (genre `Techno` count equals fixture count) → enqueue → `stop()` → reopen via `openIfConfigured` → unchanged rescan with a counting `loadMetadata` (0 calls) → rename a file → history kept → delete a file → `isMissing` → `markUnavailable` → rows unavailable in the next query. Run `LibraryEngineIntegrationTests`: expected PASS.
- [ ] **Step 2: Retry property test.** Enumerate inventories of ≤ 3 paths × 2 stats × fingerprints {equal, different, nil} and every subset of parse writes committed after the structure save; compare interrupted+retry to uninterrupted through `LibraryReconciler` plus an in-memory apply model. Assert zero mismatches and print `LIBRARY-GATE retry-cases <n>`. Run `LibraryRetryPropertyTests`: expected PASS.
- [ ] **Step 3: Performance tests** (opt-in with `TEST_RUNNER_AMPX_LIBRARY_GATE=1`, real `~/Music/DJ` through the Music entitlement, real home path as in Task 3):
  - `testFirstScan2232UnderSixtySeconds` (engine, in-memory store).
  - `testNoChangeRescan2232UnderTwoSecondsWithZeroReads`; `testNoChangeRescan11kUnderFiveSeconds` (synthetic tree).
  - `testSuccessCriterion2GenreFacets`: every crate folder name maps to a genre facet whose count equals that folder's audio file count (17 crates, total 2,232; expected counts computed by the test from the folder listing, not hard-coded).
  - `testSearchPublishesUnder100msIdleAndDuringFirstScan`: `setQuery` → `$rows` publication, measured on the main actor.
  - `testAvailabilityPublishesUnder100ms`: `markUnavailable` → browser rows unavailable.

  Run `LibraryPerformanceTests` with the env prefix: expected PASS. Record timings, hardware and cache state in the spec. A missed budget follows the spec's amendment path; do not relax thresholds.
- [ ] **Step 4: Full suite once.** `./scripts/run-tests.sh`. Expected: summary line with 0 failures.
- [ ] **Step 5: No accidental activation.**

```bash
rg -n 'LibraryEngine|LibraryStore|LibraryBrowserModel' Sources --glob '!Sources/Library/**'
```

Expected: no output. `git diff develop -- Sources/PlaylistManager.swift` shows only the panel-types change.
- [ ] **Step 6: Handoff.** Append to the spec's *L1 gate results* an "L2 handoff" list: UI amendment items 1–7, shared `SecurityScopedBookmarkStore` construction in the app delegate, calling `LibraryEngine.openIfConfigured` at launch, root panels and Remove confirmation, and the outside-`~/Music` playback-after-relaunch check. Do not claim a user-visible library.
- [ ] **Step 7: Commit** `test: verify library engine integration and performance`.

## Coverage audit

| Spec area | Tasks |
|---|---|
| Metadata gate, fields, precedence, codec, `readFailed` | 1, 4 |
| AIFF/M4A playback gate, extension set, Add Files panel | 1, 4 |
| Rename evidence, case sensitivity, allowlist, gate exit rule | 3 |
| Cost budgets (walk, first scan, search, availability) | 3, 16 |
| Bookmark primitive | 5 |
| Schema V1, migration, no destructive recovery | 6 |
| Fingerprint | 2, 7, 10 |
| Path keys, coverage, reconciliation, retry guarantee | 7, 10, 16 |
| Integrity merge | 7, 8, 10 |
| Tokens, atomic saves, rollback, publication | 8 |
| Roots, scopes, start-up flag | 9, 14 |
| Scan steps 0–7, reachability, degraded rows | 10 |
| Scheduling and cancellation | 11 |
| FSEvents, mount/unmount | 13, 14 |
| Query semantics, index invalidation | 12 |
| Browser model, enqueue, playlist continuity registration | 15 |
| Success criteria 2, 3, 4, 6, 7, 9, 10 | 16 (8 is L2) |
| No L1 activation | 16 |
| Browser module UI, menus, key routing, app wiring | L2 (amendment gate) |

## Execution handoff

This plan is not evidence. Execute Task 1 first; Tasks 1–3 form the gate and must be recorded before Task 10. Tasks are serial: later tasks consume earlier interfaces verbatim.

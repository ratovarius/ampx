# Music Library L1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify the persistent library engine, scanner, query index, and browser model without instantiating the library in the shipping app until L2.

**Architecture:** One SwiftData writer owns persistence and validates revocable scan tokens. A scanner sends value changes to it; a separate actor maintains immutable browser rows and evaluates queries. Rename decisions use current walk values and unmatched rows' stored values, with fingerprint confirmation, exactly as approved in Revision 5.

**Tech Stack:** Swift 6, macOS 26.4 deployment target, SwiftData, AVFoundation, CryptoKit, Foundation, FSEvents, Combine, XCTest; existing Python/uv fixture tooling and local FFmpeg for generating test audio.

**Spec:** [Music Library, Revision 5](../specs/2026-09-11-music-library-design.md). Read it together with the [approved review](../specs/2026-09-11-music-library-design-review.md). This plan implements **L1 only**.

## Global Constraints

- “`Track` is **unchanged** by this spec.” Keep `Track.load(from:)` consuming its current four metadata fields.
- “Any third-party SPM package, including tag parsers” is a non-goal. SwiftData and CryptoKit are system frameworks. FFmpeg is fixture-generation tooling, not an application dependency.
- “Same path = same track”: replacing contents at a path retains row identity.
- “Moves are considered only when the walk is complete.” Use **Revision 5** ambiguity inputs: all current walk entries and stored keys from unmatched rows U. Never use stale stored keys of path-matched rows.
- “A different file that matches a missing row's size, modification date and head/tail content is treated as the same track.” Do not silently replace this with inode identity or a full-file hash.
- “L2 planning must not start until that amendment is accepted.” No module UI, app startup wiring, menu changes, or replacement of Classic UI belongs in this plan.
- No production path instantiates the library in L1. Tests explicitly construct all components.
- Files in users' roots are opened for reading only. Do not retag files. History/rating fields are initialized to defaults, preserved, and combined only during the specified integrity repair.
- Run Python through `uv` **from `scripts/`**. Preserve existing fixture generation and existing test files.
- Run real tests through Xcode. `Package.swift` is build-smoke only and has no test target.
- Do not commit unrelated existing changes. At execution time, inspect `AGENTS.md`, git status, and the active worktree before editing.

---

## Delivery order and gates

1. **Task 1 is the feasibility gate.** Record actual metadata coverage, playback, filesystem rename evidence, and timings in the spec. Do not claim unavailable hardware/filesystems were tested. Missing evidence keeps the applicable gate open; continue only independent preparation, not scanner implementation.
2. Tasks 2–7 establish extraction, storage, pure reconciliation, and root ownership. Task 8 implements the scan state machine only after the gate is satisfied.
3. Tasks 9–12 connect watching, queries, browser actions, and verify the integrated engine.
4. L2 is a separate future plan after its UI amendment/cutover. Its outside-`~/Music` UI playback-restoration check is retained as a handoff item, not reported as completed by L1.

The task ordering is intentional. Implement serially initially; no shared model or API should be independently invented by parallel implementers.

## Repository facts checked while writing

- `Sources/` and `Tests/AmpXTests/` are Xcode filesystem-synchronized groups; new Swift files there are discovered automatically.
- `Tests/Fixtures/` is an explicit resource group. New fixture resources need references and target resource entries in `AmpX.xcodeproj/project.pbxproj`.
- `scripts/ampx_fixtures/generate.py` currently generates `short.wav`; retain it and the existing `sample.m3u` resource.
- `scripts/run-tests.sh` generates fixtures and runs all tests. It does **not** forward command-line filters.
- `PlaylistManager` already supports `init(bookmarkStore:)`, `clearPlaylist()`, `addTracks(_:)`, and `playTrack(at:)`.
- `SecurityScopedBookmarkStore` owns its UserDefaults array and scope counts. Extract its primitives without changing that policy.
- FFmpeg and uv were found locally when planning; execution must still check availability and record the FFmpeg version used for fixtures.

## Validation commands

Run this before any focused Xcode test command:

```bash
./scripts/generate-fixtures.sh
```

Focused command template; substitute the **literal test class** listed in each task for `LibraryFingerprintTests`:

```bash
xcodebuild test -project AmpX.xcodeproj -scheme AmpX \
  -destination "platform=macOS,arch=$(uname -m)" ONLY_ACTIVE_ARCH=YES \
  -only-testing:AmpXTests/LibraryFingerprintTests
```

Each task's red/green instructions use this command with its named class. A failure due to missing fixtures, tool installation, or signing is infrastructure, not the intended red test. Fix infrastructure before interpreting results.

Final checks:

```bash
./scripts/run-tests.sh
swift build
./scripts/format-swift.sh
./scripts/lint-swift.sh
git diff --check
```

Run formatting/lint wrappers when their tools are installed. If formatting changes source, re-run affected tests. Do not report a skipped tool as passing. Inspect changes before each commit and stage only that task's files.

## File ownership

- `Sources/Track.swift`: widen `TrackMetadataLoader.Metadata` and extraction only.
- `Sources/M3UParser.swift`: gated extension list widening.
- `Sources/Playlist/SecurityScopedBookmark.swift`: extracted bookmark make/resolve/refresh value API.
- `Sources/Library/LibraryValues.swift`: Sendable scan/root/row payloads; no SwiftData types.
- `Sources/Library/LibraryFingerprint.swift`: deterministic bounded reads and SHA-256.
- `Sources/Library/LibraryFileSystem.swift`: enumeration, coverage, resource values, fingerprint reads, reachability.
- `Sources/Library/LibrarySchemaV1.swift`: both versioned models and migration plan.
- `Sources/Library/LibraryStore.swift`: one ModelContext writer, root/row transactions, token validation, change streams, root scope ownership.
- `Sources/Library/LibraryReconciler.swift`: pure path matching, candidates, confirmed plan, duplicate repair plan.
- `Sources/Library/LibraryScanner.swift`: utility-priority full-root runs, FIFO, cancellation, progress.
- `Sources/Library/LibraryWatcher.swift`: FSEvents and mount notification lifetime, root rebinding.
- `Sources/Library/LibraryIndex.swift`: separate reader context, rows, invalidation, versions, throttled refresh.
- `Sources/Library/LibraryQuery.swift`: Codable request, facets, sorting, results.
- `Sources/Library/LibraryBrowserModel.swift`: main-actor published state, selection, generation checks, enqueue.
- `Sources/Library/LibraryEngine.swift`: explicit factory and root-operation coordinator; dormant unless a caller invokes it. No call from app code in L1.
- `Tests/AmpXTests/LibraryTestSupport.swift`: row/root builders, fake filesystem, controlled async barriers, isolated defaults and temporary stores. It is test-only.
- `scripts/ampx_fixtures/library.py`: deterministic fixture generation; `scripts/ampx_fixtures/generate.py` calls it.

## Task 1: Record the L1 metadata, rename, and cost gate

**Files**

- Create: `scripts/ampx_fixtures/library.py`, `Sources/Library/LibraryFingerprint.swift`, `Tests/AmpXTests/LibraryMetadataGateTests.swift`, `Tests/AmpXTests/LibraryFingerprintTests.swift`.
- Modify: `scripts/ampx_fixtures/generate.py`, `AmpX.xcodeproj/project.pbxproj`, the spec's L1 gate results section.
- Generate: `Tests/Fixtures/Library/manifest.json`, tagged MP3 v2.3/v2.4, FLAC, WAV-ID3, AIFF-ID3, M4A, untagged and title-only fixtures.

**Interfaces**

- Produces `LibraryFingerprint.read(from: URL) throws -> Data`.
- Produces a recorded coverage matrix: each declared metadata field per container, exact absent value, filesystem rename evidence, hardware/timing evidence, and passed/failed gates.

- [ ] **1. Add deterministic fixture generation and a manifest.** Generate two-second stereo tones at 44.1 kHz with known title `Library Song`, artist `Library Artist`, album `Library Album`, album artist `Album Artist`, genre `Techno`, year 2024, track 3, BPM 130, key `Am`, and comment `Library fixture`. Use Python `subprocess.run` with argument arrays; never shell interpolation. Generate base audio with local FFmpeg:

```python
subprocess.run([
    "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
    "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
    "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", str(wav_path),
], check=True)
```

Encode MP3 with `libmp3lame`, FLAC with `flac`, AIFF with `pcm_s16be`, M4A with `aac`. Supply metadata flags for FLAC/M4A. For ID3 fixtures, construct the text frames explicitly so container detection does not depend on FFmpeg's tag alias mapping:

```python
def syncsafe(n: int) -> bytes:
    return bytes((n >> 21 & 127, n >> 14 & 127, n >> 7 & 127, n & 127))

def id3_text(frame_id: str, value: str, version: int) -> bytes:
    payload = b"\x01" + value.encode("utf-16")
    size = syncsafe(len(payload)) if version == 4 else len(payload).to_bytes(4, "big")
    return frame_id.encode("ascii") + size + b"\x00\x00" + payload

def append_chunk(path: Path, kind: bytes, payload: bytes, endian: str) -> None:
    data = bytearray(path.read_bytes())
    data += kind + len(payload).to_bytes(4, endian) + payload
    if len(payload) % 2:
        data += b"\x00"
    data[4:8] = (len(data) - 8).to_bytes(4, endian)
    path.write_bytes(data)
```

Build TIT2/TPE1/TALB/TPE2/TCON/TYER or TDRC/TRCK/TBPM/TKEY frames; add a proper COMM frame with encoding, `eng`, terminated empty description, then comment text. Prefix with `ID3`, version bytes, flags, and syncsafe body size. Prepend tags to MP3 bases generated with `-id3v2_version 0`; append `id3 ` little-endian RIFF chunks to WAV and `ID3 ` big-endian FORM chunks to AIFF. Retain chunk padding. Write manifest expected tags, encoding/container, file sizes, and FFmpeg version. Validate chunk lengths in the generator before writing the manifest. This is fixture writing only.

- [ ] **2. Register the Library fixture folder as a copied folder resource.** Add a folder reference under Fixtures and a build-file reference in AmpXTests Resources; preserve existing individual fixtures. Test access with:

```swift
let bundle = Bundle(for: LibraryMetadataGateTests.self)
let root = try XCTUnwrap(bundle.resourceURL?.appendingPathComponent("Library"))
XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
```

- [ ] **3. Write and run failing fingerprint tests before implementation.** Test zero bytes, 17 bytes, overlapping head/tail regions, exactly 128 KiB, and a larger file. Test changed head, tail, size, same input twice, and a missing URL throwing. Expected digest construction:

```swift
var size = UInt64(bytes.count).littleEndian
var hasher = SHA256()
withUnsafeBytes(of: &size) { hasher.update(data: Data($0)) }
hasher.update(data: Data(bytes.prefix(min(65_536, bytes.count))))
hasher.update(data: Data(bytes.suffix(min(65_536, bytes.count))))
let expected = Data(hasher.finalize())
XCTAssertEqual(try LibraryFingerprint.read(from: url), expected)
```

Use a temporary file written by the test; never modify collection files. Run `LibraryFingerprintTests`; expect missing helper failure before implementation.

- [ ] **4. Implement bounded fingerprint reads.** Open a read-only `FileHandle`, get size, seek to offset 0 and `size - min(size, 65_536)`, require the requested byte count or throw, hash the exact sequence above, and close with `defer`. The deliberately repeated bytes for small files are part of the definition. Import CryptoKit. Run fingerprint tests green and `swift build` to catch framework/Swift 6 issues early.

- [ ] **5. Probe AVFoundation and playback without widening production extraction yet.** In `LibraryMetadataGateTests`, load `.availableMetadataFormats`, enumerate each format with `loadMetadata(for:)`, and record identifiers and values alongside common metadata. Load duration/audio tracks/format descriptions/estimated data rate. Assert fixture existence and valid audio; record unsupported tag fields as absent rather than inventing support. Test AIFF/M4A with `AudioPlayer(installRemoteCommands: false)` and an XCTest expectation on `loadTrack` completion, following `PlaybackIntegrationTests`; verify duration and successful play/stop in the manual gate. No real media keys installed.

- [ ] **6. Measure filesystem evidence and cost on explicitly selected test roots.** Gate tests read optional paths from `AMPX_LIBRARY_GATE_ROOT`, `AMPX_LIBRARY_GATE_ARCHIVE`, and `AMPX_LIBRARY_GATE_EXTERNAL`; use `XCTSkip` with the missing evidence named if not configured. Only create/rename gate-owned temporary files on test volumes. Record before/after size/date for rename and same-volume move, reported case sensitivity, filesystem type, sandbox status, OS, hardware, file count, elapsed walk time, and parse-plus-fingerprint time. Cover APFS/HFS+/exFAT/SMB evidence per spec, SSD and spinning drive for cost. Measure the sandboxed app-hosted test run, not only an unrestricted shell. The synthetic 11k walk is supplementary; the real 2,232-track first-scan target cannot be established using tiny tone fixtures.

- [ ] **7. Write actual gate results into the spec and decide the gate.** Unsupported metadata takes the declared absent value; failed rename preservation disables rename tracking for that filesystem by an explicit recorded rule. Missing hardware is unmeasured, not passed. A failed time budget or loss of the required genre-crate outcome returns to a spec amendment before scanner implementation. Do not add an ad-hoc parser. Run `LibraryMetadataGateTests` and `LibraryFingerprintTests`, then commit task files with `test: establish music library feasibility gate`.

## Task 2: Extend metadata extraction and gate audio extensions

**Files:** Modify `Sources/Track.swift`, `Sources/M3UParser.swift`; create `Tests/AmpXTests/TrackMetadataLoaderTests.swift`, `Tests/AmpXTests/LibraryExtensionsTests.swift`.

**Interfaces:** Keep `TrackMetadataLoader.load(from: URL) async -> Metadata`. Make its nested `Metadata` Sendable and add `album`, `albumArtist`, `genre`, `year`, `trackNumber`, `bitrate`, `bitrateIsDerived`, `sampleRate`, `channels`, `codec`, `bpm`, `musicalKey`, and `comment` with the exact types/defaults in the spec. Existing title/artist/duration/fileSize fields remain.

- [ ] **1. Write failing extraction tests from the recorded gate matrix.** Every exposed field has an asserted known value; every unsupported field has an asserted absent value. Include this regression pattern:

```swift
let metadata = await TrackMetadataLoader.load(from: untaggedURL)
let fallback = TrackMetadataParser.parse(from: untaggedURL)
XCTAssertEqual(metadata.title, fallback.title)
XCTAssertEqual(metadata.artist, fallback.artist)
XCTAssertEqual(metadata.album, "")
XCTAssertNil(metadata.genre)
```

Also assert title-only preserves `Unknown Artist`, artist-only preserves filename title, neither uses the parser, and `Track.load` agrees on its four consumed fields. Run `TrackMetadataLoaderTests` red.

- [ ] **2. Implement extraction with the verified metadata formats/keys.** Preserve today's title/artist precedence. Parse `3/12` as track 3, year prefixes as a valid year, finite positive BPM, and case/spacing-normalized tagged key without deriving Camelot. Read sample rate/channels from audio track format descriptions. Preserve parser source unchanged. Reported positive finite `estimatedDataRate` wins; otherwise use:

```swift
let derived = duration.isFinite && duration > 0
    ? Double(fileSize) * 8 / duration : 0
let bitrate = derived.isFinite && derived > 0 && derived < Double(Int.max)
    ? Int(derived.rounded()) : 0
```

Set `bitrateIsDerived` only for an actually computed fallback. Avoid integer multiplication overflow. Treat non-finite duration as zero. Add default values to the metadata initializer so existing construction sites remain valid.

- [ ] **3. After the playback gate passes, widen the one extension set.** Test `AIF`, `aiff`, and `M4A` case-insensitively, plus unsupported files. Then change:

```swift
static let supportedExtensions: Set<String> = ["mp3", "flac", "wav", "aif", "aiff", "m4a"]
```

Run `LibraryExtensionsTests`, `TrackMetadataLoaderTests`, `TrackTests`, `TrackMetadataParserTests`, `M3UParserTests`, and `PlaylistImportTests`. Commit `feat: extract library metadata and accept verified audio formats`.

## Task 3: Extract bookmark primitives without changing playlist behavior

**Files:** Create `Sources/Playlist/SecurityScopedBookmark.swift`, `Tests/AmpXTests/SecurityScopedBookmarkTests.swift`; modify `Sources/Playlist/SecurityScopedBookmarkStore.swift`.

**Interfaces:**

```swift
struct ResolvedBookmark: Sendable {
    let url: URL
    let isStale: Bool
    let usesSecurityScope: Bool
}
enum SecurityScopedBookmark {
    static func makeData(for url: URL, usesSecurityScope: Bool = true) throws -> Data
    static func resolve(_ data: Data) -> ResolvedBookmark?
    static func refreshedData(for url: URL, usesSecurityScope: Bool) -> Data?
}
```

- [ ] **1. Write a helper round-trip test and malformed-data test; run `SecurityScopedBookmarkTests` red.** Create files under a temporary directory, mint a plain bookmark for deterministic unit tests, resolve it, and assert the standardized URL. Include:

```swift
XCTAssertNil(SecurityScopedBookmark.resolve(Data([0, 1, 2])))
let data = try SecurityScopedBookmark.makeData(for: url, usesSecurityScope: false)
let resolved = try XCTUnwrap(SecurityScopedBookmark.resolve(data))
XCTAssertEqual(resolved.url.standardizedFileURL, url.standardizedFileURL)
```

- [ ] **2. Move the existing private resolver/refresh implementation into the helper.** Preserve security-scoped resolution followed by plain-bookmark fallback and `.withoutUI`; preserve creation option selection. Delegate the playlist store to the helper. Keep its locking, UserDefaults key, deduplication, parent bookmarks, restore dropping unresolved entries, and reference-count lifetime unchanged.
- [ ] **3. Test refresh and unchanged legacy behavior.** Assert refreshed data resolves after a gate-owned rename when supported; label platform-dependent stale-state observation separately. Run `SecurityScopedBookmarkTests`, the existing **unchanged** `SecurityScopedBookmarkStoreTests`, and `PlaylistFileServiceTests`. Commit `refactor: share bookmark primitives with library roots`.

## Task 4: Define value contracts, schema, and migration boundary

**Files:** Create `Sources/Library/LibraryValues.swift`, `Sources/Library/LibrarySchemaV1.swift`, `Tests/AmpXTests/LibraryTestSupport.swift`, `Tests/AmpXTests/LibrarySchemaMigrationTests.swift`.

**Interfaces:** Define these common values before dependent tasks. `LibraryRow` is the complete struct in the spec, including rootID, albumArtist, trackNumber, fileSize, availability, and searchKey.

```swift
struct LibraryStat: Hashable, Sendable {
    let fileSize: Int64
    let contentModifiedAt: Date
}
struct LibraryHistory: Equatable, Sendable {
    var playCount: Int
    var lastPlayedAt: Date?
    var rating: Int
}
struct LibraryRowKey: Sendable {
    let id: UUID
    let relativePath: String
    let stat: LibraryStat
    let fingerprint: Data?
    let dateAdded: Date
    let history: LibraryHistory
    let isMissing: Bool
}
struct LibraryRootSnapshot: Sendable {
    let id: UUID
    let bookmark: Data
    let url: URL
    let isAvailable: Bool
    let unreadableFolderCount: Int
    let lastCompletedScanAt: Date?
}
struct LibraryEntry: Sendable {
    let relativePath: String
    let stat: LibraryStat
}
enum LibraryCoverage: Equatable, Sendable {
    case complete
    case partial(uncoveredFolders: Set<String>)
    case aborted
}
struct LibraryWalk: Sendable {
    let entries: [LibraryEntry]
    let coverage: LibraryCoverage
    let caseSensitive: Bool
    let renameTrackingEnabled: Bool
}
struct LibraryParseWrite: Sendable {
    let id: UUID
    let relativePath: String
    let stat: LibraryStat
    let metadata: TrackMetadataLoader.Metadata
    let fingerprint: Data?
}
enum LibraryChange: Sendable {
    case rootsChanged(rootID: UUID)
    case rootRemoved(rootID: UUID)
    case rowsChanged(rootID: UUID)
}
```

`LibraryRowKey` is the stored state. A matched row's stored stat must never enter rename ambiguity calculations. `LibraryParseWrite` carries a generated ID for an insertion or the existing ID for an update; store code preserves dateAdded/history on updates.

- [ ] **1. Create test builders with deterministic inputs.** `LibraryTestSupport.key(id:path:stat:fingerprint:history:) -> LibraryRowKey`, `entry(path:stat:) -> LibraryEntry`, `walk(entries:coverage:caseSensitive:renameTrackingEnabled:) -> LibraryWalk`; give parameters the types above, with default history `(0, nil, 0)`, complete coverage, case sensitivity true, and rename tracking true. Supply deterministic dateAdded and isMissing false inside the key builder. Use fixed dates and fixed UUID literals in identity assertions. Implement a `temporaryDirectory() throws -> URL` helper with per-test cleanup.
- [ ] **2. Write a failing on-disk V1 round-trip test.** Insert one root and track with nonzero reserved fields, close all contexts, reopen, and compare every stored field. Run `LibrarySchemaMigrationTests` red.
- [ ] **3. Implement `LibrarySchemaV1: VersionedSchema` with nested `@Model` `LibraryRoot` and `LibraryTrack`.** Copy **all** model fields and exact defaults from the spec. Expose `typealias LibraryRoot = LibrarySchemaV1.LibraryRoot` and `typealias LibraryTrack = LibrarySchemaV1.LibraryTrack`. Only UUID IDs have `.unique`; add rootID and rootID/relativePath indexes. Use an empty V1 migration plan:

```swift
enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
```

Container construction always supplies this plan. Store files belong under Application Support/AmpX/Library; tests pass a temporary URL or in-memory configuration. Never recover an open error by deleting or replacing a store.
- [ ] **4. Add a test-only V2 schema and plan.** Clone V1 model names and fields into a test schema, add one optional field, and migrate with a lightweight stage. Verify every original value and reserved field survives, reopen a second time, and assert idempotence. If row `schemaVersion` must change, explicitly stamp it in a data migration/post-open transaction; automatic schema migration does not update arbitrary integer fields. Keep the test V2 out of production. Run schema tests green and `swift build`. Commit `feat: define versioned library schema and value contracts`.

## Task 5: Implement filesystem coverage and pure reconciliation

**Files:** Create `Sources/Library/LibraryFileSystem.swift`, `Sources/Library/LibraryReconciler.swift`, `Tests/AmpXTests/LibraryReconcilerTests.swift`, `Tests/AmpXTests/LibraryFileSystemTests.swift`; extend test support with a fake filesystem.

**Interfaces:**

```swift
protocol LibraryFileSystem: Sendable {
    func walk(root: URL) async throws -> LibraryWalk
    func fingerprint(at url: URL) async throws -> Data
    func isReachable(_ root: URL) async -> Bool
}
struct LibraryMove: Equatable, Sendable {
    let id: UUID
    let relativePath: String
}
struct LibraryIntegrityMerge: Sendable {
    let survivorID: UUID
    let deletedIDs: Set<UUID>
    let history: LibraryHistory
}
struct LibraryReconciliation: Sendable {
    let moves: [LibraryMove]
    let spellingUpdates: [LibraryMove]
    let foundIDs: Set<UUID>
    let missingIDs: Set<UUID>
    let newEntries: [LibraryEntry]
    let parseIDs: Set<UUID>
}
enum LibraryReconciler {
    static func integrityMerges(rows: [LibraryRowKey],
                                caseSensitive: Bool) -> [LibraryIntegrityMerge]
    static func candidatePaths(rows: [LibraryRowKey], walk: LibraryWalk) -> [String]
    static func reconcile(rows: [LibraryRowKey], walk: LibraryWalk,
                          fingerprints: [String: Data]) -> LibraryReconciliation
    static func pathKey(_ path: String, caseSensitive: Bool) -> String
}
```

`candidatePaths` and `reconcile` use one shared internal matching routine so eligibility cannot drift. Fingerprint I/O is performed outside the pure reconciler; a missing dictionary value means unreadable and disallows that move. Only complete walks with rename tracking enabled produce candidates. Production sets `renameTrackingEnabled` using the filesystem rules recorded by Task 1's gate; a failing or unverified filesystem rule disables moves without disabling indexing. `parseIDs` contains existing path-matched rows whose walked stat differs from stored stat.

- [ ] **1. Write the reviewed update-before-insert test using the value builders; run `LibraryReconcilerTests` red.** Its exact expected decision is:

```swift
let k = LibraryStat(fileSize: 1_000, contentModifiedAt: Date(timeIntervalSince1970: 10))
let k2 = LibraryStat(fileSize: 2_000, contentModifiedAt: Date(timeIntervalSince1970: 20))
let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
let x = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
let fp = Data([1])
let rows = [
    LibraryTestSupport.key(id: a, path: "A.mp3", stat: k, fingerprint: fp),
    LibraryTestSupport.key(id: x, path: "X.mp3", stat: k, fingerprint: fp),
]
let walk = LibraryTestSupport.walk(entries: [
    LibraryTestSupport.entry(path: "B.mp3", stat: k),
    LibraryTestSupport.entry(path: "X.mp3", stat: k2),
])
let result = LibraryReconciler.reconcile(rows: rows, walk: walk,
                                        fingerprints: ["B.mp3": fp])
XCTAssertEqual(result.moves, [LibraryMove(id: a, relativePath: "B.mp3")])
XCTAssertEqual(result.parseIDs, [x])
XCTAssertTrue(result.newEntries.isEmpty)
```

- [ ] **2. Add the remaining pure counterexamples before implementation.** Two walked links with K refuse a move before and after either link is inserted. A matched entry with K blocks a candidate; a matched row with stored K but walked K2 does not. Two U rows with K, nil stored fingerprint, fingerprint mismatch, missing read, and disabled rename tracking all refuse. A partial walk never moves, even when an unindexed hidden link is absent from its entries; covered absent rows become missing, uncovered rows stay untouched. An aborted walk returns an empty plan. Path replacements keep ID; case/normalization spelling changes update spelling under the declared path rule.
- [ ] **3. Implement the immutable decision basis.** The critical logic is:

```swift
let entriesByStat = Dictionary(grouping: walk.entries, by: \.stat)
let unmatchedByStat = Dictionary(grouping: unmatchedRows, by: \.stat)
// For each unmatched entry, require complete coverage,
// entriesByStat[entry.stat]?.count == 1,
// unmatchedByStat[entry.stat]?.count == 1,
// non-nil stored fingerprint equal to fingerprints[entry.relativePath].
```

`unmatchedRows` is U, derived after path matching and uncovered-folder exclusion. Do not count stored stats of matched rows. Compute coverage with path components/boundary-aware prefixes, not string prefixes that confuse `crate` with `crate2`. Return the plan without mutating inputs. Sort output paths/IDs to make tests deterministic.
- [ ] **4. Implement `FoundationLibraryFileSystem` and test coverage.** Run its blocking enumeration inside a utility-priority detached task; poll cancellation during traversal. Prefetch regular-file/stat/volume identifiers; skip excluded directories, dotfiles, packages and nested mounts. Do not follow file symlinks out of the root. Record unreadable locations conservatively; an unknown enumeration error cannot prove absence. Check `fileExists`/readability and enumeration failure separately so a disappeared root is aborted rather than an empty complete walk. Use the fingerprint helper for reads. A full-root walk must perform zero content reads.
- [ ] **5. Run `LibraryReconcilerTests`, `LibraryFileSystemTests`, and `LibraryFingerprintTests` green.** Include boundary cases: nested uncovered folders, root enumeration failure, empty available root, and excluded directory prefixes. Commit `feat: reconcile library rows from stable walk evidence`.

## Task 6: Implement the writer, atomic structure saves, and scan tokens

**Files:** Create `Sources/Library/LibraryStore.swift`, `Tests/AmpXTests/LibraryStoreTests.swift`, `Tests/AmpXTests/LibraryScanTokenTests.swift`; extend schema tests/test support.

**Interfaces:** `LibraryStore` is a `@ModelActor` with its own writer context. Define an opaque Sendable/Hashable `LibraryScanToken` containing a random UUID and rootID; only the store can issue valid tokens. Produce these actor methods:

```swift
func beginScan(rootID: UUID) throws -> LibraryScanToken
func revokeScan(rootID: UUID)
func rowKeys(rootID: UUID) throws -> [LibraryRowKey]
func applyStructure(_ plan: LibraryReconciliation, token: LibraryScanToken,
                    unreadableFolderCount: Int) throws
func applyParsed(_ writes: [LibraryParseWrite], token: LibraryScanToken) throws
func finishScan(token: LibraryScanToken, completedAt: Date) throws
func changes() -> AsyncStream<LibraryChange>
```

Add `LibraryStoreError` cases `unknownRoot`, `revokedToken`, `overlappingRoot`, `unavailableRoot`, `storeOpenFailed(String)`; propagate underlying persistence errors without deleting data. Root APIs arrive in Task 7.

- [ ] **1. Write failing token tests using an in-memory model container and one root.** Seed the root directly through a test-owned context before constructing the writer, so these tests do not depend on Task 7's root APIs. After beginning/revoking a token, assert both structure and parse saves throw `revokedToken`, do not mutate rows, and emit no changes. Reissue a token and confirm the old token stays rejected. Use a controlled async barrier to deliver the old write after reissue; never sleep to manufacture the ordering. Run `LibraryScanTokenTests` red.
- [ ] **2. Implement validation and persistence in one actor-isolated, non-suspending transaction.** The entire critical section is:

```swift
guard activeTokens[token.rootID] == token else { throw LibraryStoreError.revokedToken }
// Fetch the still-existing root, apply mutations, and save without an await.
do {
    try modelContext.save()
} catch {
    modelContext.rollback()
    throw error
}
// Yield the exact root/row changes only after save succeeds.
```

Disable writer autosave; otherwise pending changes could persist outside the token-validated save path. Publish synchronously after commit using registered AsyncStream continuations. Give each subscriber its own stream; do not assume two iterators over one stream broadcast. Remove terminated subscribers.
- [ ] **3. Implement atomic structure and batch parse transactions.** One structure save applies all moves/spelling/found/missing changes and root unreadable count. `applyParsed` handles at most 200 rows per call and preserves history/dateAdded on updates. It validates unique canonical paths before insertion and never relies on SwiftData path upsert. The final partial batch is saved. `finishScan` changes lastCompletedScanAt only for the caller's complete walk.
- [ ] **4. Implement integrity merge before reconciliation.** Use `LibraryReconciler.integrityMerges(rows:caseSensitive:)` to group by canonical path; oldest dateAdded then smallest UUID survives; preserve its metadata/fingerprint; take maximum playCount and latest lastPlayedAt, keep survivor rating unless zero, then first nonzero rating ordered by dateAdded and UUID. Apply the returned survivor/history/deletion values in one token-validated save and log a fault. Test two/three duplicates and a second no-op scan. Do not mutate unchanged rows merely to make progress events.
- [ ] **5. Test rollback and publication.** Use an injected writer-owned `saveContext: @Sendable (ModelContext) throws -> Void`, defaulting to `try $0.save()`, to fail a save deterministically. Confirm rollback and no event; ensure the next valid transaction is clean. The closure runs synchronously on the writer and never transfers its context elsewhere. Verify one accepted save can emit rootsChanged and rowsChanged, while rejection emits neither. Run `LibraryStoreTests`, `LibraryScanTokenTests`, and schema tests. Commit `feat: persist library changes behind revocable scan tokens`.

## Task 7: Own root access, relocation, removal, and startup discovery

**Files:** Extend `Sources/Library/LibraryStore.swift`; create `Tests/AmpXTests/LibraryRootTests.swift`; extend test support with scope/access spies. Engine composition is created in Task 11, once all its types exist.

**Interfaces:** Store produces `roots() throws -> [LibraryRootSnapshot]`, `addRoot(url: URL) throws -> UUID`, `relocateRoot(id: UUID, to: URL) throws`, `removeRoot(id: UUID) throws`, `markUnavailable(id: UUID) throws`, and `resolveRoot(token: LibraryScanToken) throws -> LibraryRootSnapshot`. Inject UserDefaults and bookmark/scope functions for deterministic tests. Scope abstraction has `start(URL) -> Bool` and `stop(URL)`; production delegates to Foundation.

- [ ] **1. Write failing root lifecycle tests.** Add rejects equality, ancestor, descendant, and symlink-equivalent roots; relocation uses the same test excluding itself. Verify:

```swift
let token = try await store.beginScan(rootID: id)
try await store.markUnavailable(id: id)
do {
    try await store.applyParsed([], token: token)
    XCTFail("Unmount must revoke the old run")
} catch LibraryStoreError.revokedToken {}
```

Run `LibraryRootTests` red. Record scope starts/stops and ensure repeated access resolution does not leak counts.
- [ ] **2. Implement root transactions and access lifetime.** Root mutation revokes active tokens before applying the change. Persist bookmark refresh; treat unresolved, missing, or failed scope start as unavailable. Keep track `isMissing` unchanged on root unavailability. On relocation retain rootID/relative paths, publish changed root before new scanning, stop old scope, start new, and retain independent playlist bookmarks. Never publish available merely because resolution returned a URL if access or existence failed.
- [ ] **3. Implement `AmpXLibraryHasRoots` ordering.** Set before add insertion; clear only after the last-root removal save. A true flag plus empty store self-clears. A failed add may leave a true flag, which is recoverable. Tests use isolated defaults suites and assert order with a persistence spy. No production startup code reads the flag until L2.
- [ ] **4. Make root construction testable without an app singleton.** Construct `LibraryStore(modelContainer:)` on a utility task with the isolated container, then configure its injected defaults and access functions before accepting commands. Record the scope function results in an actor-safe spy. Leave container/scanner/index/watcher composition to Task 11 so this task compiles independently. No static `.shared` or app call site is introduced.
- [ ] **5. Verify removal affects only its root, relocation preserves fields, unavailable→available requires zero re-parses, and all scopes stop on teardown.** Run root/token/bookmark suites. Commit `feat: manage library roots and security scope lifetimes`.

## Task 8: Implement the full-root scanner with resumable parse batches

**Files:** Create `Sources/Library/LibraryScanner.swift`, `Tests/AmpXTests/LibraryScannerTests.swift`, `Tests/AmpXTests/LibraryIdentityTests.swift`; extend test support.

**Interfaces:** `LibraryScanner` actor consumes store, filesystem, and `@Sendable (URL) async -> TrackMetadataLoader.Metadata`. Produce `scanOnce(rootID: UUID) async throws`, `requestScan(rootID: UUID)`, `cancelScans(rootID: UUID) async`, and `progress() -> AsyncStream<ScanProgress>`. Define `ScanProgress` with rootID, phase (`walking`, `reconciling`, `parsing`), done, total. Scheduling is completed in Task 9.

- [ ] **1. Write a no-change scan test with parse and fingerprint spies.** Scan seeded rows/identical entries and assert:

```swift
try await scanner.scanOnce(rootID: rootID)
let parseCount = await fake.parseCount
let fingerprintCount = await fake.fingerprintCount
XCTAssertEqual(parseCount, 0)
XCTAssertEqual(fingerprintCount, 0)
```

The fake filesystem and loader counters are actor-isolated. Run `LibraryScannerTests` red.
- [ ] **2. Implement the exact steps 0–7 in the approved spec.** Issue token, resolve access, repair integrity, walk, derive candidate paths, read only their fingerprints, reconcile, commit structure, then parse existing stale/new rows in batches of 200. Build every file URL from the run's resolved root and relative path. Candidate read failure means no move. New-file fingerprint failure stores nil only if the root remains reachable. Metadata failure on a reachable root stores parsed defaults/duration zero and logs once per file per scan. Lost access revokes/marks unavailable and aborts without a degraded write.
- [ ] **3. Keep stat/fingerprint/metadata writes coherent.** Persist the stat associated with successful parsing, and check for a file changing during the read. If it changed, queue another scan and leave it stale rather than certifying mismatched data as current. Existing unchanged rows retain their stored fingerprint. Do not add fingerprint reads to the no-change path. No `@Model` leaves the writer.
- [ ] **4. Add interruption tests against actual store transactions.** Seed nonzero history and fixed IDs. Use fake barriers immediately after structure save and between every parse batch. Reopen the same on-disk store and retry under identical walk/read results. Compare original IDs, path/history/metadata/missing state; normalize newly minted IDs by path and do not compare wall-clock insertion timestamps. Include the exact update-before-insert and hard-link fixtures from Task 5 with enough unrelated rows to straddle a 200-row boundary.
- [ ] **5. Cover complete, partial, aborted and fingerprint mismatch runs.** Partial saves process covered locations and insert new entries but never move; uncovered rows remain untouched. Aborted walk does not commit beyond access/repair. Only complete Finish changes lastCompletedScanAt. Rename A→B retains reserved fields only under the approved conditions. Nil fingerprint, equal size/date with different fingerprints, and ambiguous entries become missing-plus-new.
- [ ] **6. Run `LibraryScannerTests`, `LibraryIdentityTests`, `LibraryReconcilerTests`, and token tests.** Confirm cancellation after unmount and remount rejects an already queued parse batch. Commit `feat: scan and resume library roots without identity drift`.

## Task 9: Schedule scans and bind filesystem notifications

**Files:** Extend scanner; create `Sources/Library/LibraryWatcher.swift`, `Tests/AmpXTests/LibraryScanSchedulingTests.swift`, `Tests/AmpXTests/LibraryWatcherTests.swift`. Task 11 connects production engine callbacks.

**Interfaces:** `LibraryWatcher` owns `bind(rootID: UUID, url: URL)`, `unbind(rootID: UUID)`, `stop()` and a Sendable callback `(LibraryWatchEvent) -> Void`. Define events `.changed(UUID)`, `.rootChanged(UUID)`, `.mounted`, `.unmounted(URL)`. The engine routes them to scheduler/store root operations.

- [ ] **1. Write controlled queue tests; run scheduling tests red.** Block root A mid-walk, request it three times and root B once, then release. Assert maximum concurrent scans = 1, execution order A/B/A, and exactly one A follow-up. Request an edit in an already-walked directory and verify the follow-up sees it. Cancel queued B and verify it never starts.
- [ ] **2. Implement FIFO and pending/rescan flags.** `requestScan` queues a previously idle root; queued requests coalesce; running requests set one follow-up flag. Drain from a retained utility-priority task. `cancelScans` revokes in the store before cancelling the task, removes queued entries, and clears follow-up state. Do not let actor reentrancy start a second drain. Finish/error cleanup releases the current slot and continues other roots.

Keep the queue transition explicit inside the scanner actor (declare `queue: [UUID]`, `queued: Set<UUID>`, `runningRoot: UUID?`, and `rescanRequested: Set<UUID>` as its state):

```swift
if runningRoot == rootID {
    rescanRequested.insert(rootID)
} else if queued.insert(rootID).inserted {
    queue.append(rootID)
}
```

On completion, clear runningRoot; if `rescanRequested.remove(rootID) != nil`, append that root once at the end of the FIFO. A cancellation clears the flag before completion can consume it. The drain task must not be cleared while the cancelled run still occupies its slot.
- [ ] **3. Implement FSEvents with an owned context and serial callback queue.** Use the current SDK declaration for callback/context ownership. Create with 2-second latency and root-change watching, start on a dispatch queue, and stop/invalidate/release during rebinding or teardown. Route all event batches for a root to full-root scans; explicitly include MustScanSubDirs, UserDropped, KernelDropped. RootChanged re-resolves its bookmark through the coordinator. Do not persist event IDs or introduce subtree scans. Filter roots by component-aware containment.
- [ ] **4. Observe NSWorkspace mount/unmount notifications.** Mount attempts root resolution and queues catch-up scans; unmount immediately revokes affected scans and publishes unavailable state. Bind observers on the main actor as required, forward value events to the coordinator, remove observers on stop. Use injected events in unit tests; do not require unplugging a user's drive.
- [ ] **5. Verify lifecycle.** Rebinding releases the old stream exactly once, callbacks from stopped bindings are ignored, removing a root cancels its queued work, and stop releases streams/observers/tasks. Startup queues each configured root once; no-root startup opens no container. Run scheduler/watcher/root/token suites and commit `feat: watch roots and coalesce library scans`.

## Task 10: Build the independent query snapshot and invalidation stream

**Files:** Create `Sources/Library/LibraryIndex.swift`, `Sources/Library/LibraryQuery.swift`, `Tests/AmpXTests/LibraryQueryTests.swift`, `Tests/AmpXTests/LibraryChangePublicationTests.swift`.

**Interfaces:**

```swift
enum LibraryFacetValue: Hashable, Codable, Sendable {
    case text(String)
    case absent
}
enum LibrarySortColumn: String, Codable, Sendable { case artist, title, duration, bpm, musicalKey, bitrate }
struct LibraryQuery: Codable, Sendable {
    var search: String = ""
    var genres: Set<LibraryFacetValue> = []
    var artists: Set<LibraryFacetValue> = []
    var albums: Set<LibraryFacetValue> = []
    var sort: LibrarySortColumn = .artist
    var ascending = true
}
struct LibraryFacetCounts: Sendable {
    let genres: [LibraryFacetValue: Int]
    let artists: [LibraryFacetValue: Int]
    let albums: [LibraryFacetValue: Int]
}
struct LibraryResult: Sendable {
    let rows: [LibraryRow]
    let facets: LibraryFacetCounts
    let snapshotVersion: UInt64
    let generation: UInt64
}
```

`LibraryIndex` actor produces `query(_ request: LibraryQuery, generation: UInt64) async throws -> LibraryResult`, `versions() -> AsyncStream<UInt64>`, and `rows(ids: Set<UUID>) async throws -> [LibraryRow]`. It owns a separate reader ModelContext on the same container. Add `LibraryRow.makeTrack() -> Track` and stable library ID mapping here. Test `.absent` is distinct from literal text `(No Genre)`.

Define the pure `LibraryQuery.evaluate(rows: [LibraryRow], snapshotVersion: UInt64, generation: UInt64) -> LibraryResult` used by the index and unit tests, so query semantics can be tested without SwiftData.

- [ ] **1. Write pure query examples and run `LibraryQueryTests` red.** Use rows including accented artist names, nil genre, empty album, unavailable rows, and tied sort values. Verify whitespace-split case/diacritic-folded AND terms; OR within facets, AND across facets; own-facet exclusion counts; nil optional sort values last; ascending/descending primary order with fixed artist/album/trackNumber/title/UUID tie-breaks. Round-trip requests through JSONEncoder/JSONDecoder.

Use this minimal real row as the first search/facet test, then add the multi-row cases above:

```swift
let row = LibraryRow(
    id: UUID(), rootID: UUID(), url: URL(fileURLWithPath: "/Music/a.mp3"),
    title: "Song", artist: "Artist", album: "", albumArtist: "",
    genre: nil, trackNumber: nil, duration: 120, fileSize: 1_000,
    bpm: nil, musicalKey: nil, bitrate: 0, bitrateIsDerived: false,
    codec: "mp3", isAvailable: false, searchKey: "song artist  "
)
let result = LibraryQuery(search: "ARTIST song").evaluate(
    rows: [row], snapshotVersion: 1, generation: 2
)
XCTAssertEqual(result.rows.map(\.id), [row.id])
XCTAssertEqual(result.facets.genres[.absent], 1)
XCTAssertEqual(result.facets.albums[.absent], 1)
XCTAssertEqual(result.generation, 2)
```
- [ ] **2. Implement query evaluation against snapshots only.** Construct folded searchKey once per row from title/artist/album/albumArtist. Missing genre/album become `.absent` and display labels only at presentation. Empty facet selection means no filter. Count unavailable rows. Always include stable UUID as the final comparator key. Use an explicit optional comparator so nil ordering is consistent.
- [ ] **3. Subscribe to store changes before building the first snapshot.** Build lazily on the first query. Prevent a save during initial load from being lost: retain dirty root IDs while loading, then refresh those roots before announcing the version. The reader must observe new commits, not reuse stale registered model values; use fresh per-refresh contexts or explicit refetch/context invalidation confirmed by the persistence test. Never send fetched `@Model` instances to the main actor.
- [ ] **4. Implement typed invalidation.** Root removal evicts immediately. Root changes rebuild availability/URLs immediately. Row changes throttle refetch to at most once per root per second with a trailing refresh; an immediate root change overrides pending stale work. Inject time/scheduling in tests. Applying a change increments snapshot version and emits it. Record current version while evaluating a query so consumers can identify which snapshot it used.
- [ ] **5. Test actual store-to-reader changes with an open query.** Add, unavailable, remount, relocate, remove, scan batch, and integrity merge must update rows/counts. Test burst+trailing refresh, save during lazy load, removal while a refetch is pending, and rejected token causing no version bump. Run `LibraryQueryTests`, `LibraryChangePublicationTests`, store/token suites. Commit `feat: query library snapshots independently of scan writes`.

## Task 11: Build browser model and enqueue bridge without UI wiring

**Files:** Create `Sources/Library/LibraryBrowserModel.swift`, `Sources/Library/LibraryEngine.swift`, `Tests/AmpXTests/LibraryBrowserModelTests.swift`.

**Interfaces:** `@MainActor final class LibraryBrowserModel: ObservableObject` consumes index, engine/root operations, a concrete injected `PlaylistManager`, and the same `SecurityScopedBookmarkStore` used by that manager. Publish query/result rows/facets, selection `Set<UUID>`, focused ID, progress, and root snapshots. Produce `setQuery(_:)`, `refresh()`, `enqueue(append: Bool, clickedID: UUID?) async`, and `stop()`. Root management methods delegate to the engine; they accept URLs and confirmation decisions supplied by L2, not NSOpenPanel UI in L1.

Define `LibraryEngine.open(storeURL: URL, defaults: UserDefaults, bookmarkStore: SecurityScopedBookmarkStore) async throws -> LibraryEngine`, `stop() async`, and root operations with the same argument/return types as Task 7's store methods. The engine owns store/scanner/index/watcher, constructs actor contexts at utility priority, routes filesystem events, and coordinates `cancelScans` before root mutations. Define browser query injection as `@Sendable (LibraryQuery, UInt64) async throws -> LibraryResult`; production delegates to the index, tests use controlled continuations. Keep singleton-free initialization: the caller must explicitly invoke open.

- [ ] **1. Write out-of-order result and selection tests.** Inject a query closure backed by controlled continuations, start generation 1 then 2, deliver 2 then 1, and assert generation 1 cannot overwrite rows/facets. A refresh retains selected/focused IDs still present and drops vanished IDs. Cancel retained tasks on stop. Run `LibraryBrowserModelTests` red.
- [ ] **2. Implement request generation plus version refresh.** Increment a monotonically increasing generation for each request; cancel the previous task and check generation before publication. Subscribe to index versions and scanner progress/root state; avoid retain cycles. UI publication happens only on the main actor. Cancellation alone is insufficient because a completed task may still deliver.
- [ ] **3. Implement enqueue from current snapshots.** Resolve selected IDs against the latest index, preserving displayed order. A clicked row outside selection acts alone. Filter currently unavailable rows, register every involved root URL with the shared bookmark store, then build `Track` occurrences. No available rows means beep/no-op; inject a beep closure for tests. Replacement does not clear the playlist until the nonempty available list is ready:

```swift
guard !tracks.isEmpty else { beep(); return }
if append {
    playlist.addTracks(tracks)
} else {
    playlist.clearPlaylist()
    playlist.addTracks(tracks)
    playlist.playTrack(at: 0)
}
```

Before this block, construct `tracks` from latest rows with `makeTrack()`; use latest root URLs after relocation. No changes to PlaylistManager's public API or Track.
- [ ] **4. Test actions using existing test mocks.** Construct `MockAudioPlayer`, isolated UserDefaults, shared bookmark store, and `PlaylistManager(restoreBookmarks: false, restorePlaylist: false, bookmarkStore: store, stateStore: isolatedState, alertPresenter: SilentPlaylistAlertPresenter())`. Confirm append, replacement/play-first, outside-selection click, unavailable-only no-op preserving existing playlist, rechecked unavailable stale result, root registration, and repeated enqueue with distinct Track IDs but preserved fileSize. Confirm a removed root cannot be enqueued from old selected IDs.

Pass `audioPlayer: mockAudioPlayer` explicitly into that initializer; do not let tests use `AudioPlayer.shared` via the default parameter. The two-occurrence bridge assertion is:

```swift
let first = row.makeTrack()
let second = row.makeTrack()
XCTAssertNotEqual(first.id, second.id)
XCTAssertEqual(first.fileSize, row.fileSize)
XCTAssertEqual(first.url, row.url)
```
- [ ] **5. Complete engine ownership and teardown.** Factory supplies the same model container to writer/reader, starts watcher/scanner only when explicitly called, and stops tasks/scopes/streams in explicit `stop()`. Browser models can be dropped without destroying a library engine that still owns configured roots; closing a future browser does not disable watchers. No production call sites added in L1. Run browser, query, root and existing PlaylistManager tests. Commit `feat: expose library browser state and playlist actions`.

## Task 12: Verify integrated engine, performance, and L2 handoff

**Files:** Create `Tests/AmpXTests/LibraryEngineIntegrationTests.swift`, `Tests/AmpXTests/LibraryPerformanceTests.swift`; update the spec with final measured results and this plan's completed checks.

**Interfaces:** Uses the explicit `LibraryEngine.open` factory and stop lifecycle, all public value APIs above; adds no production APIs solely for performance assertions.

- [ ] **1. Write and run integration tests.** In a temporary on-disk container, add a fixture root, scan, query, enqueue, stop, reopen, and rescan unchanged. Assert IDs/history survive, no unchanged parses/content reads occur, playlist entries carry metadata/fileSize, and all scopes/observers release on stop. Inject rename/missing/partial/late-token events and compare store and reader snapshots. Do not change existing regression tests to make the new code pass.
- [ ] **2. Convert the reviewed model exploration into a meaningful reconciler property test.** Enumerate small inventories of three paths, two stat keys, differing/nil fingerprints and all subsets of parse writes persisted after structure commit. Compare uninterrupted vs retry outcomes under identical reads, normalizing only fresh IDs/timestamps. Include moves, stale path matches, missing rows, and ambiguous entries. The prior review observed 50,311 modeled cases; implementation must run its own checks and report its own count, not copy that number as evidence.
- [ ] **3. Measure required budgets on the real selected roots after gate approval.** First scan of 2,232 tracks including fingerprints <60s; no-change scans <2s/2,232 and <5s/11,000 with zero content reads. Search <100ms through `LibraryBrowserModel` publication both idle and during a first scan; availability save→published unavailable result <100ms. Warm query benchmarking alone does not satisfy the keystroke-to-publication target. Observe main-thread responsiveness and record hardware/cache state/runs; do not relax thresholds to make tests green.
- [ ] **4. Run final repository validation.** Generate fixtures and run `./scripts/run-tests.sh`, `swift build`, installed format/lint wrappers, affected tests after formatting, and `git diff --check`. Preserve raw result paths and concise pass/failure summaries. If metadata/IO budgets fail, return to the spec's stated amendment path rather than switching architectures inside this plan.
- [ ] **5. Check L1 has no accidental startup/UI activation.** Inspect:

```bash
rg -n 'LibraryEngine|LibraryStore|LibraryBrowserModel' Sources
git diff -- Sources/AmpXApp.swift Sources/ContentView.swift Sources/PlaylistManager.swift
```

References may exist in `Sources/Library/` only, plus any explicitly justified helper imports. The app shell, Classic views, menus, and PlaylistManager shared construction remain untouched in L1. The intentional import-extension widening and richer loader are the only existing app-path behavior changes.
- [ ] **6. Document L2 handoff and commit `test: verify library engine integration and performance`.** List the UI amendment, module registration/overflow/text-input/key-router work, shared bookmark-store app construction, startup marker activation, root panels, and outside-`~/Music` playback-restoration UI check as remaining L2 work. Do not claim the user-visible library has shipped.

## Coverage audit

- Metadata sources/fallbacks/codec acceptance: Tasks 1–2.
- Root bookmarks, stale refresh, playlist access continuity: Tasks 3, 7, 11–12.
- V1 schema, defaults, migration and no-destructive-recovery policy: Tasks 4, 6.
- Fingerprint definition and IO cost: Tasks 1, 5, 8, 12.
- Stable identities, path comparison, coverage, reviewed rename/retry examples: Tasks 4–6, 8, 12.
- Integrity merge and reserved-field preservation: Tasks 6, 8, 12.
- Tokens, rollback, partial batches, late writes: Tasks 6–9, 12.
- Root add/remove/relocate/unmount/remount and startup marker: Tasks 7, 9.
- FSEvents queue, coalescing and teardown: Task 9.
- Independent queries, facets, sort, availability and change publication: Task 10.
- Browser selection, stale-result rejection, available-only enqueue: Task 11.
- No-root/no-L2 activation, build-smoke, existing tests, latency budgets: Task 12.
- Browser visuals/accessibility/menus/windowing: intentionally L2, subject to the spec's existing amendment gate.

## Execution handoff

This document is a plan, not implementation or measurement evidence. Execute with either Superpowers subagent-driven development (fresh implementer per task, review between tasks) or inline executing-plans with checkpoints. Start with Task 1 and retain its gate; do not start L2 from this plan.

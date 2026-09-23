# Music Library Design — Spec Review

## Revision 5 review — 2026-09-15

**Status:** Approved for L1 implementation planning. No remaining blocking findings. Earlier reviews below are historical and do not describe the current verdict.

**Method:** Superpowers spec-document review, an independent reviewer, and an in-memory check of the revised reconciliation rule. The spec is unchanged.

### Final fix verified

**R4.1 is resolved.** Reconciliation now counts size/date pairs from the current complete walk and stored keys from unmatched rows U only. Re-parsing a matched row cannot change either input. In the previous counterexample, X contributes its walked K2 values from the outset, so A moves to B during the first structure save; a retry finds that row at B by path. There is no later change in the rename decision.

The hard-link case remains safe under the declared rule: all walked entries contribute to ambiguity, including entries whose rows were inserted before interruption. Complete coverage is still required for moves, and revoked scan tokens still reject late saves.

### Verification and limits

- An in-memory model exercised **50,311 interruption cases with zero mismatches** across three paths, two size/date keys, differing or unavailable fingerprints, and every subset of pending parse updates/inserts committed before retry. Comparisons preserved original row identity and normalized newly generated IDs by path.
- This checks the specified complete-walk algorithm under fixed filesystem state and read results. It is not a test of SwiftData, real file I/O, crash durability, or the future app implementation.
- The independent Superpowers reviewer also returned **Approved**, with no blocking findings.

### Planning reminders — non-blocking

- Carry the same-filesystem-state and same-read-results premise into interruption tests.
- Run and record the existing **L1 metadata, rename-evidence, and cost gate before scanner implementation**. This approval does not assert that those measurements pass.
- **L2 planning remains dependent on the accepted UI-spec amendment and UI cutover**, as the spec already requires.

No app build or runtime test suite was run for this document review.

---

## Revision 4 review — historical, 2026-09-15

**Status:** Issues Found — one remaining blocker in retry consistency.

**Method:** Superpowers spec-document review of Revision 4 against the prior findings. Re-read the revised design and modeled the remaining reconciliation counterexample in memory. This verifies a contradiction in the specified algorithm, not an implemented scanner. The spec is unchanged.

### Fixes verified

- **R3.1 resolved:** Persisted file identifiers are removed. Fingerprints provide the new evidence, and the guarantee explicitly accepts identical size/date/head-tail content as the same track. The sampled fingerprint is not being treated as proof of whole-file equality.
- **R3.2 previous examples resolved:** Moves require complete coverage, and ambiguity counts matched as well as unmatched rows and entries. Both the hidden-hard-link example and interruption between hard-link insertions are handled. One case involving metadata updates remains below.
- **R3.3 resolved:** Store-issued tokens are explicitly revoked on cancellation, unmount, access loss, relocation, and removal. Late saves remain invalid after remount; tests cover this.
- **Case-only rename clarification resolved:** The spec distinguishes a path match on case-insensitive volumes from the ordinary rename rule on case-sensitive volumes.

### R4.1 — P1: Re-parsing can remove ambiguity between batches

**Spec:** Whole-root row counts, lines 226–228; metadata updates and batching, line 233; retry proof, lines 239–242; success criterion 7, line 474.

The retry argument says the row count for a size/date pair K can only grow. That holds for inserts, but step 6 also updates existing rows' size/date values. An update can remove a row from K and make a previously rejected rename eligible on retry.

Concrete case, with the filesystem unchanged throughout both runs:

1. The index contains A and X, both with stored size/date K.
2. On disk, A has been renamed B with unchanged K and fingerprint. X has been modified and now has size/date K2.
3. The complete walk path-matches X. It leaves U = {A} and N = {B}, but the stored whole-root row count for K is two (A and X). The scanner rejects the move.
4. Step 6 re-parses X and saves its K2 values in a batch. The app stops before the batch inserting B.
5. On retry, only A has stored K; only B has walked K. Their fingerprints match, so A moves to B.

An uninterrupted scan would instead insert a new B and retain missing A. The retry moves A's original identity and reserved fields to B. The declared rule produced these different decisions in an in-memory check, contradicting the promised identical final state. Existing tests only cover insertion increasing ambiguity, not an update decreasing it.

**Required resolution:** Make the ambiguity inventory independent of partially committed metadata updates. For example, define matched rows' candidate keys from the current walk consistently before reconciliation, or persist the reconciliation decision across parse batches. Specify the rule and add this exact update-before-insert interruption test. Reordering batches alone is not a general proof of retry consistency.

**Disposition:** Resolve R4.1 before approving the complete L1 implementation plan. The other prior blockers are closed. The L1 metadata/rename/cost gate remains required before scanner work, and L2 still requires its UI amendment. No app build or runtime suite was run.

---

## Revision 3 review — historical, 2026-09-15

**Status:** Issues Found — three remaining blockers. The changes resolve publication and relocation, and substantially improve coverage handling, but do not yet satisfy the identity and interruption guarantees.

**Method:** Superpowers spec-document review of Revision 3 against the previous findings. Checked the declared state transitions and exercised the hard-link retry counterexample below with an in-memory model of the specified matching rule. This is not a test of an implemented scanner. The original spec remains unchanged.

### Fixes verified

- **R2.1 partially resolved:** Volume UUID invalidation and restricted filesystem enablement fix cross-volume matching. Size/mtime corroboration reduces false matches but does not establish the promised identity guarantee; see R3.1.
- **R2.2 original scenario resolved:** Aborted walks stop; partial walks set aside uncovered rows and defer entries sharing their IDs. The previous partial-walk hard-link example is covered. A separate batch-interruption case remains; see R3.2.
- **R2.3 resolved:** Typed changes after every save, root eviction, immediate availability/location refresh, query reruns, and enqueue rechecks establish the missing publication contract.
- **R2.4 resolved for relocation:** Overlap validation, generation increments, stale-save rejection, and watcher/scope rebinding are explicit. The extension of this guarantee to unmount is incomplete; see R3.3.
- **Previous advisories addressed:** Snapshot fields, duplicate-path merge rules, startup discovery, and absent-value defaults are specified. The case-only rename wording needs the small clarification below.

### R3.1 — P1: Equal size and modification time do not rule out identifier reuse

**Spec:** Reconciliation, lines 228–232; reused-identifier behavior, line 368; success criterion, line 466; risk guarantee, line 476.

The rules still move a row solely on equal volume UUID, file ID, size, and modification time, with uniqueness in U/N. A deleted file A can leave a retained row while another file B receives the same identifier on that volume. If B has the same size and preserved modification time, all conditions pass and A's row and reserved fields move to B. Neither size nor timestamp is unique to a file. The error table assumes one differs, but neither the model nor the algorithm enforces that assumption.

**Required resolution:** Either add a reliable continuity check with explicit lifetime/invalidation rules, or explicitly accept this remaining false-positive risk and narrow the success criterion. Calling the persisted value a hint does not change the result when it authorizes a move. Add a reconciler test with equal volume, ID, size and mtime for two distinct file lifetimes; the current algorithm moves the row while the current success criterion forbids it.

### R3.2 — P1: Partial coverage and batch interruptions change hard-link reconciliation

**Spec:** Coverage and uniqueness among U/N, lines 228–234; batched insertion, line 236; interruption guarantee, line 241.

Consider indexed A, then rename A to B and add hard link C. B and C share the original file ID, size, and mtime. A complete walk produces U = {A}, N = {B, C}. The ID is not unique in N, so the specified result is to retain missing A and insert new B and C.

Now interrupt after B is saved but before C is saved, across a 200-row batch boundary. On retry, B is matched by path and excluded from N. U = {A}, N = {C}, so the ID becomes unique and A's original row moves to C. This yields a different identity and reserved-field assignment from an uninterrupted scan. The counterexample was reproduced with an in-memory model of these rules.

There is also a remaining partial-coverage case: the walk covers A's absence and sees B, but C is inside an unreadable folder and has never been indexed. No set-aside row represents C, so deferral does not apply; the scan moves A to B. A complete walk would see both links and refuse that move. The independent reviewer identified this counterexample. Checking only indexed rows under uncovered folders cannot establish uniqueness across unknown entries there.

**Required resolution:** Evaluate ambiguity against the entire relevant root inventory, including path-matched rows and entries, or persist reconciliation decisions so retry cannot reinterpret them. Do not infer global uniqueness from partial coverage without additional evidence. Test both an unindexed hard link hidden by an unreadable folder and interruption between insert batches containing separate hard links. The existing partial-walk deferral test exercises neither case.

### R3.3 — P2: Unmount cancellation does not invalidate late scan saves

**Spec:** Save acceptance, line 216; cancellation guarantee, line 256; Unmount/Relocate, lines 268–269.

The scheduler claims generation fencing makes a cancelled scan's late save harmless for unmount as well as relocation. But Unmount only cancels the task and saves `isAvailable = false`; it does not increment `locationGeneration`, and the root still exists. A suspended parse batch can therefore resume and pass the store's stated acceptance checks after unmount. It can overwrite row metadata with results from failed reads or commit structural changes despite the access-loss contract. Relocation avoids this because it increments the generation; unmount does not.

**Required resolution:** Invalidate the active scan token/generation on unmount and access loss, or require a store-side validity check that rejects cancelled runs across unmount/remount. Do not rely on cooperative task cancellation for the late-save guarantee. Test a save queued or suspended before unmount and delivered afterward, including after a remount.

### Advisory clarification

The case-only rename edge-case row (line 367) and revision log say it matches by path on every volume. The path-key rule only case-folds on case-insensitive volumes. On a case-sensitive volume it must use ID reconciliation, or take the documented missing-plus-new fallback when ID matching is disabled. Align this wording with the already-defined capability rules.

**Disposition:** Resolve R3.1–R3.3 before approving the complete L1 plan. The fixes to earlier findings are retained; these are specific remaining counterexamples, not a request to redesign the library. No app build or runtime test suite was run.

---

## Revision 2 review — historical, 2026-09-14

**Status:** Issues Found. Most original findings are resolved, but the remaining identity and lifecycle issues below prevent approval for implementation planning.

**Method:** Re-read Revision 2 in full, checked its resolutions against the previous review and current bookmark/playlist code, and checked the file-identifier contract in Apple's installed SDK. The earlier review is retained below as history. This review does not change the spec or claim that the metadata/performance gates have passed.

### Fixes verified

- **Original R1:** Insertion now follows reconciliation. Path swaps and replacement deliberately use path identity; that accepted semantic change is not being reflagged. File-ID reconciliation still has the separate problems below.
- **Original R2:** The impossible cleared unique string is removed. Stable row IDs and root-relative paths replace it.
- **Original R3:** Full-root scans and an explicit queue/follow-up policy resolve subtree coverage and lost scan requests.
- **Original R4:** Root records, relative-path relocation, effective availability, and clearing `isMissing` independently of metadata resolve the original recovery gaps. Root mutations still need coordination and publication rules.
- **Original R5:** Shared bookmark primitives, a shared playlist store, root registration on enqueue, and explicit scope ownership resolve the API and playback-access design gaps.
- **Original R6:** `LibraryRow` supplies stable identity and availability; fresh playback occurrences preserve repeated enqueue behavior.
- **Original R7:** Metadata precedence now matches the existing loader.
- **Advisories:** Delivery order, reserved fields, metadata feasibility gates, query semantics, stale-result rejection, and separate performance budgets are now explicit. L2 remains gated on its UI-spec amendment.

### R2.1 — P1: Persisted file IDs are not a durable rename identity

**Spec:** Decisions, lines 45–46; `fileID`, line 111; reconciliation, line 205; relocation, line 232.

The revision calls `fileIdentifierKey` persistent and saves it as a bare `UInt64`, then matches unmatched files by equality across later scans. Apple's SDK describes it as an internal inode identifier, warns that stability varies across filesystems and mounts, and advises against persisting it. See [Apple's API reference](https://developer.apple.com/documentation/foundation/urlresourcekey/fileidentifierkey) and the installed [NSURL.h declaration](/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Foundation.framework/Headers/NSURL.h:260) (`NSURLFileIdentifierKey`).

A concrete failure needs no path swap: relocate a root to another volume, retaining an unmatched old row with file ID 42; a different new file also has ID 42. Step 4 transfers the old row's identity and reserved fields to it. The same risk exists when an identifier is recycled while missing rows remain in the index. The stated fallback of “missing row plus new row” does not cover false-positive matches.

**Required resolution:** Define the validity domain and invalidation of rename identifiers, including restart, remount, relocation, and retained missing rows. Do not infer continuity from an unqualified persisted integer. If reliable evidence is unavailable, retain the missing row and insert a new one. Extend the gate beyond rename stability to collision/invalidation scenarios; a successful APFS rename test alone cannot establish this contract.

### R2.2 — P1: An incomplete walk cannot prove a rename

**Spec:** Scanning steps 2–6, lines 203–207; interruption contract, line 210.

Step 4 explicitly allows moves after an incomplete walk because a file-ID match is called positive evidence. It proves a common filesystem object, not that the original path disappeared. For example, an indexed file A has a newly added hard link B; a partial walk visits B and stops before A. U contains A and N contains B, so the rule moves A's row to B. A later full scan inserts A as a new row. An uninterrupted full scan would keep A's original row and insert B instead. Reserved fields therefore end up on different paths depending on cancellation timing, contradicting the promised idempotent final state.

**Required resolution:** Defer rename decisions until coverage proves the old path absent, or verify that absence separately and handle hard-link ambiguity. Defer ambiguous inserts too, so an incomplete scan does not preempt reconciliation on retry. Test a partial walk that sees a new hard link but not the existing indexed path, followed by a complete retry.

### R2.3 — P1: Root changes do not consistently invalidate browser snapshots

**Spec:** Access failure, line 202; change emission, line 208; unmount, line 223; root operations, lines 229–233; index refresh, line 251.

The only explicit `LibraryChange` emission is at scan Finish. However, failed root access returns before Finish, an unmount changes availability without scanning, and Remove deletes rows without a scan. An already-built `LibraryIndex` snapshot therefore has no specified refresh trigger for these operations. Unplugging a drive can leave its cached rows available for enqueue; removing a root can leave its rows and facet counts in the browser.

**Required resolution:** Publish committed root availability, location, and removal changes independently of scan completion. Define how removal evicts rows and how availability/location changes rebuild their snapshots. Also define publication of committed batches when a scan exits early. Test unmount, access failure, relocation, and removal with the browser already open and its snapshot populated.

### R2.4 — P2: Relocation bypasses root validation and scan coordination

**Spec:** Roots must not overlap, line 51; scheduling, lines 216–223; Add/Relocate, lines 229–232.

Add checks overlap, and Remove cancels scans. Relocate only replaces the bookmark/path and requests a scan. It can point a root at or inside another root, violating the locked root invariant. It also allows an old in-flight scan to commit results collected from the previous location after the new bookmark is installed, potentially overwriting file IDs, missing state, or metadata for the relocated root.

**Required resolution:** Validate the destination using the same overlap rules as Add, excluding the root being relocated. Coordinate relocation with the active scan through cancellation and completion, or a root-location generation checked before commits. Define watcher and security-scope rebinding. Test relocation into another root and relocation while metadata parsing is suspended.

### Remaining recommendations — advisory

- **Complete the snapshot fields.** The declared `LibraryRow` lacks `trackNumber`, required by the in-memory sort tie-breaker. It also lacks `fileSize`, so its direct `makeTrack()` bridge cannot preserve that existing playback field without an additional lookup. Include these values or define the lookup explicitly.
- **Make duplicate-path repair real or fail explicitly.** Step 3 treats duplicate rows as unmatched, but neither marking them missing nor logging a fault changes their identical `relativePath`. That does not satisfy the test requiring one path owner. Specify a quarantine/repair policy or fail that scan without claiming repair.
- **Clarify startup discovery.** Roots live in SwiftData, but startup promises to avoid opening a container when no roots exist. Define the lightweight persisted marker or other discovery mechanism that makes this decision possible.
- **Align fallback representations.** The gate says unsupported fields become nil, while several model fields require empty strings or zero. Refer to the field-specific defaults. Likewise, qualify the unconditional “replacement re-parsed” statement with the declared size/mtime staleness limitation.
- **Update downstream names before DJ-mode planning.** That spec still names `LibraryTrackSchemaV2` and the former model file, whereas this revision introduces `LibrarySchemaV1` containing both root and track models.

**Disposition:** Revision 2 substantially addresses the original review. Resolve R2.1–R2.4 before treating L1 as ready for an implementation plan. No runtime tests were run; the L1 metadata and performance spike remains required.

---

## Revision 1 review — historical

**Date:** 2026-09-14

**Status:** Issues Found — resolve the findings below before implementation planning.

**Method:** Superpowers spec-document review: completeness, consistency, clarity, scope, and unnecessary complexity, checked against current source. This is a document review; no runtime or performance claims were tested.

**Reviewed:** [Music library spec](./2026-09-11-music-library-design.md), current `Track`, `TrackMetadataLoader`, `TrackMetadataParser`, `SecurityScopedBookmarkStore`, `PlaylistManager`, panel descriptors, and the related DJ-mode and UI designs.

## Issues

### 1. P1 — Path-first identity resolution cannot preserve identity in all promised cases

**Spec:** Scanning and Identity resolution, lines 126–139.

A new path is inserted during enumeration, but existing bookmarks are reconciled only after the walk. Renaming `A.mp3` to `B.mp3` can therefore insert a new B row before discovering that the A row owns it, contrary to the promise to rewrite the original row without inserting a duplicate. Batch saves can persist that intermediate result.

There is a second failure even if insertion is deferred: swap the paths of two indexed tracks. Both paths hit existing rows, both rows are touched, and neither enters the bookmark sweep. Metadata may be updated, but ratings and play counts remain attached to the wrong files. Equal size and modification time also defeats the staleness check. The declared conflict handler is never reached.

**Required resolution:** Specify reconciliation before insertion and a way to detect path reuse independently of metadata staleness. For example, a filesystem identity check can decide when bookmark reconciliation is necessary. Define winner selection and atomic updates. Test rename, path swap, replacement, and interruption between enumeration and reconciliation.

### 2. P1 — Cleared path hints are incompatible with the declared schema

**Spec:** Model, lines 75–76 and 99; conflict handling, lines 139 and 171.

`pathHint` is a required unique `String`, while losing rows must keep their data and clear that field. `nil` is not representable; clearing multiple rows to an empty string violates uniqueness. Once cleared, the hint also cannot identify the row's former root for the later sweep.

**Required resolution:** Separate stable row identity, optional current path ownership, and last-known display path/root membership. Specify a representation that permits multiple retained rows with no current path, and test multiple conflicts in one save. Do not use a shared empty string as the unclaimed-path value.

### 3. P1 — Incremental scan coverage and queued changes are undefined

**Spec:** Live updates, line 38; root-wide sweep, line 130; concurrent scans, line 175.

The watcher scans only a changed subtree, but reconciliation examines every untouched row under the watched root. Scanning one crate therefore sweeps unrelated crates, contradicting the intended incremental work bound. Restricting the sweep to the changed subtree instead requires an explicit rule for moves across subtrees.

Likewise, “second call coalesces into the first” does not say what happens when that call concerns another subtree, or a directory the active scan has already passed. Those changes can be omitted from the completed scan.

**Required resolution:** Define scan coverage, dirty-subtree accumulation, cross-subtree reconciliation, and a follow-up pass for changes received after coverage has already been processed. Define when startup and watcher recovery require a full-root scan. Test changes in two crates and a second edit to a directory already visited.

### 4. P1 — Root relocation and missing-file recovery lack state transitions

**Spec:** Watched roots, line 37; scanning, lines 124–130; unavailable roots, line 166; recovery success criterion, line 218.

The spec promises persisted, user-managed roots and recovery through Relocate, but defines no root record, row-to-root association, or relocation mapping. This matters when the old root bookmark cannot resolve: providing a new root URL alone does not specify which old rows should be recovered rather than inserted again.

Recovery at the same path also fails under the literal scan steps. A temporarily unavailable root marks its rows missing; on return, unchanged rows take the skip branch, which never clears `isMissing`. Those tracks remain excluded from enqueue.

**Required resolution:** Define root persistence and add/remove/relocate behavior, how existing rows are matched after relocation, and how successful access clears missing state independently of metadata parsing. Specify handling of incomplete enumeration so an interrupted or failed walk is not treated as a complete inventory. Test unavailable → available with unchanged files and relocation that requires a newly selected root.

### 5. P2 — Reusing the bookmark store requires an explicit API and ownership change

**Spec:** Locked bookmark decision, line 35; model, line 75; scan, lines 124–130; bridge, lines 29 and 69.

The existing [bookmark store](../../../Sources/Playlist/SecurityScopedBookmarkStore.swift) has `saveBookmark(for:) -> Void`; raw creation and resolution are private. It owns a UserDefaults bookmark array and active scopes. The proposed library instead stores per-row bookmark data in SwiftData and needs to resolve individual rows. Its current public API cannot implement that contract. `restore()` also omits unresolved bookmarks from its rewritten array, so its persistence policy cannot serve as the library's retained-missing-record policy.

The bridge supplies URL-based `Track` values, while `PlaylistManager.addTracks` only appends and persists tracks. The spec does not assign responsibility for keeping access available through playback and playlist restoration after the library scan ends.

**Required resolution:** Scope a shared bookmark primitive API for creation, resolution, refresh, and access lifetime; distinguish library persistence from playlist persistence. Specify how enqueue transfers or retains access while preserving the playlist's public API. Include the helper in the change list and verify playback after scan completion and relaunch.

### 6. P2 — Browser results do not define stable identity or missing-state transport

**Spec:** Storage-only model, line 29; `[Track]` browser results, lines 63–69; missing-row UI, line 167; widened Track, line 198.

Current [Track](../../../Sources/Track.swift) creates a fresh UUID for every instance and has no `isMissing` field. Rebuilding results through `asTrack()` therefore changes identities on every query unless the bridge changes this behavior. Selection can disappear during scan updates, and the browser has no declared way to gray out missing rows or exclude them from actions without accessing the storage model.

**Required resolution:** Define the value contract crossing the store boundary, including a stable library identifier and availability. A browser-row snapshot can keep this separate from playback occurrence identity, which matters when the same library song is appended twice. Specify which rows replace the playlist on double-click and how selection survives refreshed results. Test refresh with a selection, missing rows, and repeated enqueue.

### 7. P2 — Untagged metadata has contradictory acceptance criteria

**Spec:** Artist fallback, line 78; preserved parser fallback, line 105; absent-tag behavior, line 173; tests, lines 183–184.

Three outcomes are required: artist falls back to filename stem; artist becomes `Unknown Artist`; and the existing heuristic parser stays in use. For an untagged `Artist - Song.mp3`, that parser returns artist `Artist` and title `Song`, not either prescribed fallback pair. An implementation cannot satisfy all three.

**Required resolution:** Declare one precedence chain. Preserving existing behavior would mean tags first, then existing filename/path heuristics, then the parser's final unknown-artist fallback. Align the model notes, error table, and fixture expectations.

## Recommendations — advisory

- **Declare UI implementation order.** This spec correctly follows current Classic source and the supplied AGENTS.md. However, [UI design Revision 7](./2026-09-11-ampx-ui-design.md) retires Classic sprites, 275 px geometry, and SwiftUI hosting. State whether the library ships before that cutover or will be adapted to its module host; do not silently choose a different architecture during planning.
- **Clarify reserved fields.** State whether `lastPlayedAt`, `playCount`, and `rating` are preservation-only fields in this release. If they are active features, define their update events and ownership.
- **Prove metadata coverage early.** Treat FLAC and ID3-in-WAV/AIFF fixture extraction as an early implementation gate before committing to the first-scan budget. The review has not verified AVFoundation support for every claimed container/tag combination.
- **Separate performance measurements.** State whether the incremental two-second target excludes the watcher's two-second coalescing delay, and measure query latency during scanning as well as against an idle index.
- **Define query semantics.** Specify how selected facets combine, whether counts reflect other active filters, and the stable sort tie-breaker. Require cancellation or request-generation checks so a late result for an older search cannot overwrite the latest query.

## Disposition

The storage/playback split and explicit migration boundary are useful foundations. Scope is coherent for a library feature; no split into unrelated projects is required. The identity and recovery contracts need revision before a plan can safely promise preserved rows and reliable incremental updates. The original spec is unchanged.

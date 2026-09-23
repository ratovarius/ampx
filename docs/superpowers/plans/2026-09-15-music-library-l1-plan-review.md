# Music Library L1 Plan — Review

**Date:** 2026-09-15
**Reviewed:** [Music Library L1 Implementation Plan](./2026-09-15-music-library-l1.md) against [Music Library spec, Revision 5](../specs/2026-09-11-music-library-design.md)
**Method:** superpowers:writing-plans self-review checklist (spec coverage, placeholder scan, type consistency, task sizing) plus source checks against `develop` (`5562af8`) and `feature/ampx-ui` (`086e577`)
**Status:** Open. Items 1–5 block execution; item 3 needs a user decision.

## Does the plan include the Library UI?

**No.** The plan covers only **L1, the engine**: store, scanner, reconciler, watcher, query index, and `LibraryBrowserModel` (rows, selection, playlist enqueue). It has no views, menus, root-picker panels or key handling, and no production code instantiates the library. Nothing new is user-visible after L1.

This follows the spec. The spec forbids planning L2 (the browser module) until the AmpX UI design spec gets an amendment covering:

1. module ID `library` (collapse/close/detach/re-dock, left column);
2. Library as a second variable-height module, with an overflow rule;
3. a custom search text input implementing `NSTextInputClient` (IME/marked text);
4. key-router priority 2b for the focused Library module.

The amendment does not exist yet. Both copies of `2026-09-11-ampx-ui-design.md` (`develop` and `feature/ampx-ui`) still list Library as out of scope. **The next step toward a visible library is writing that amendment.**

## Verified plan claims

All accurate:

- `PlaylistManager.init(audioPlayer:restoreBookmarks:restorePlaylist:bookmarkStore:stateStore:alertPresenter:)`
- `MockAudioPlayer`, `SilentPlaylistAlertPresenter`, and `AudioPlayer(installRemoteCommands:)` exist
- `SecurityScopedBookmarkStore` has private `ResolvedBookmark`, `resolveBookmark` and `refreshBookmarkData`
- `Sources/` and `Tests/AmpXTests/` are filesystem-synchronized groups; `Tests/Fixtures` is an explicit group
- deployment target 26.4, Swift 6
- `addTracks`, `clearPlaylist` and `playTrack` are synchronous, so the replace-then-play order in Task 11 is sound

Strengths: global constraints; the Revision 5 ambiguity basis is encoded in the reconciler test; token validation happens in one non-suspending critical section; one stream per subscriber; explicit L1 non-activation check. Tasks 1–5 are detailed and executable.

## Findings

### Fix before execution

1. **No base branch.** The new UI exists only on `feature/ampx-ui` (39 commits ahead of `develop`, 1 behind: it lacks the executor-crash fix `5562af8`). Task 1 edits `AmpX.xcodeproj/project.pbxproj`, which already differs between the branches. `AGENTS.md` on `develop` still describes the Classic UI. The plan must name a base, e.g. `feature/ampx-ui` after bringing in `5562af8`.

2. **Task 1, step 6 (filesystem gate) cannot run as written.**
   - `xcodebuild test` only forwards environment variables prefixed with `TEST_RUNNER_` to tests. Plain `AMPX_LIBRARY_GATE_ROOT` / `_ARCHIVE` / `_EXTERNAL` never arrive, so every gate test `XCTSkip`s.
   - `AmpXTests` runs inside the sandboxed `AmpX.app` (`TEST_HOST`, `com.apple.security.app-sandbox`). It cannot read external or SMB paths without a user-selected bookmark. `~/Music` is read-only (`assets.music.read-only`), so gate-owned rename files cannot be created there.
   - The plan requires measuring inside the sandbox, so it needs a real way to give the host access to those folders: pass a bookmark in, or use a manual in-app harness.

3. **The gate has no exit rule for missing hardware.** It asks for APFS, HFS+, exFAT, SMB and a spinning drive, and "missing evidence keeps the gate open", which can block Task 8 indefinitely. Filesystems that fail the rename check already fall back to rename tracking disabled by rule. Missing *cost* evidence has no rule. **User decision needed:** which evidence is required, and which may be recorded as unmeasured and waived.

4. **Missing interfaces force implementers to invent APIs:**
   - Integrity repair: described in Task 6, step 4 and called by Task 8, but the store has no method signature for it.
   - Task 8, step 3 checks whether a file changed during its read, but `LibraryFileSystem` has no single-file stat.
   - The metadata loader closure returns non-optional `Metadata`, so "log metadata failure once per file" has nothing to detect.
   - Start-up flag: Task 9, step 5 tests "no-root start-up opens no container", but `LibraryEngine` only arrives in Task 11, and `LibraryEngine.open(...)` always opens the container. Nothing reads `AmpXLibraryHasRoots`. Needs an entry point such as `openIfConfigured(defaults:) -> LibraryEngine?`, placed before that test.

5. **`LibraryStore` has a two-phase init.** Task 7, step 4 constructs `LibraryStore(modelContainer:)`, then "configures" defaults and security-scope functions before accepting commands. Task 6 also injects `saveContext`. `@ModelActor` only generates `init(modelContainer:)`. Hand-write the `ModelActor` conformance (`modelExecutor`, `modelContainer`) with one complete init, so the actor cannot be used before it is configured.

### Should fix

6. **AIFF/M4A widening is incomplete.** Folder import uses `supportedExtensions` (`Sources/Playlist/PlaylistFileService.swift:58`). The Add Files panel at `Sources/PlaylistManager.swift:654` (same on both branches) still allows only mp3/wav/flac/m3u. Task 12, step 5 requires `PlaylistManager` to stay untouched. Either allow a one-line exception or record it as L2 work.

7. **Spec coverage gaps:**
   - Success criterion 2 (a real `~/Music/DJ` scan yields all 17 crates as genre facets with correct counts) is not in Task 12 or the coverage audit.
   - Task 2 omits deriving `codec` from the extension with `aif` normalized to `aiff`.
   - `TrackMetadataLoader.Metadata` uses `let` fields. A `let` with a default is excluded from the memberwise init, so "add default values" needs an explicit initializer.

8. **Plan standard (writing-plans):**
   - Tasks 6–11 are mostly prose. FSEvents context ownership, root transactions, index refresh and engine composition have no code blocks. "Use the current SDK declaration" is a placeholder. The failing- and passing-test run steps are implied rather than written with expected output.
   - Task sizing:
     - Task 1 mixes the fingerprint implementation into the gate.
     - Task 9 combines scan scheduling, FSEvents and mount observation.
     - Task 11 combines the browser model with engine composition, the riskiest integration. Split the engine into its own task, before Task 9's start-up test.

## Verdict

The design is sound. The plan is **ready to execute after items 1–5 are fixed**; items 6–8 can go in the same edit.

## Next steps

- [ ] User decides item 3 (required vs. waivable gate evidence).
- [ ] Revise the L1 plan for items 1–8.
- [ ] Draft the AmpX UI spec amendment (module ID, variable-height overflow, text input, key-router 2b) so L2 planning can start.

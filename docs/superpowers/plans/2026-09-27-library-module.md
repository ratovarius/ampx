# Library Module (Music Library L2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Library window: a snapping module window that browses, searches and filters the L1 engine and sends tracks to the playlist, in the app's custom-drawn skin.

**Architecture:**
- **Window.** `library` becomes a sixth `AmpXModuleID`, hosted by the existing per-module window machinery, so snapping, persistence, the header and windowshade come for free. Its content is an `AmpXModuleContent` built from small custom-drawn views over `LibraryBrowserModel`.
- **Engine lifecycle.** A `LibraryController` owns the engine: it opens it at launch only when the start-up flag is set, and on the first Add Folder otherwise.
- **Pure logic.** Query mapping, columns, selection and layout are pure types with unit tests. Views stay thin.

**Tech Stack:** Swift 6, AppKit (custom `NSView` drawing, `NSTextInputClient`, `NSDraggingSource`), Combine, XCTest; the L1 engine in `Sources/Library/`.

**Spec:** [Library Module design](../specs/2026-09-27-library-module-design.md) (with its *UI spec amendment*); engine: [Music Library, Revision 7](../specs/2026-09-11-music-library-design.md).

**Base:** `feature/library-module`, stacked on `feature/music-library` (PR #15).

## Global Constraints

- No native controls: no `NSTableView`, `NSScrollView`, `NSTextField` or `NSSearchField`. Everything is drawn in `AmpXSkin` colours, with `AmpXScrollbar`, `AmpXButton` and `AmpXLabel`.
- The Library window is never part of the stack: it has no minimize and no detach, and it snaps like any module window (`AmpXSnapGeometry` works from frames).
- Minimum window size is 910 × 420 pt, with no maximum; the first open is 1,000 × 500 pt below the stack, clamped on-screen. Collapse is header-only.
- Facets are GENRE and ARTIST only; there is no album facet or column.
- Columns are #, ARTIST, TITLE, GENRE, TIME, BPM, KEY, KBPS, FORMAT. TITLE is always visible; the default hides only #.
- **MIXES WELL** is a placeholder in L2: the switch works and persists, the list shows "Recommendations arrive with DJ mode (BPM & key analysis).", and + QUEUE is disabled.
- `PlaylistManager`'s public API is unchanged. Drops onto the Playlist use its existing file-URL import.
- Closing the Library window stops only the browser model; the engine runs until quit.
- The launch flag is off with no roots, so no container opens.
- Never add `Co-Authored-By:` lines. Never run `swiftformat` by hand (the hook formats files).

## Review Focus

1. **IME and dead-key input in search** (e.g. ⌥E then E → "é", Japanese composition). Marked text is drawn underlined, and the query uses committed text only. Test in Task 3 (`testMarkedTextDoesNotChangeCommittedValue`) and Task 9 (`testQueryIgnoresMarkedText`).
2. **Long and accented names** ("Sébastien Léger – Mirage (Extended Mix) [Remastered]"): truncated with "…" inside their column, never drawn into the next column. Test in Task 6 (`testCellTextTruncatesWithinColumn`).
3. **Very large selections**: ⌘A on 11,000 rows, then ↩, enqueues in displayed order without hanging the main thread past one refresh. Test in Task 9 (`testSelectAllEnqueuesInDisplayOrder`, 11,000 synthetic rows, under 1 s).
4. **A saved Library frame on a display that is gone, or a screen narrower than 910 pt**: the frame is clamped into the visible frame and the width never drops below the minimum (the window may overhang). Test in Task 2 (`testLibraryFrameClampedToVisibleScreen`).
5. **The window opened before the engine exists or after it fails** (no roots; a store from a newer schema): the empty or error state shows and nothing crashes. Add Folder… from the empty state opens the engine. Test in Task 9 (`testEmptyStateThenAddFolderOpensEngine`, `testEngineErrorShowsErrorState`).

---

## Validation commands

**Run `<Suites>`** (one `-only-testing` per suite):

```bash
xcodebuild test -project AmpX.xcodeproj -scheme AmpX \
  -destination "platform=macOS,arch=$(uname -m)" \
  -only-testing:AmpXTests/<Suite> 2>&1 | grep -E 'error: |failed \(|TEST (SUCCEEDED|FAILED)'
```

*Expected FAIL* means compile errors naming the missing symbol, or `failed (` lines for the named tests. *Expected PASS* means `TEST SUCCEEDED`. Visual checks use `./scripts/shoot.sh`, which captures by window id; library windows need `--index`. Run the full suite once, at the end.

## File map

| File | Responsibility | Task |
|---|---|---|
| `Sources/Library/LibraryQuery.swift`, `LibraryIndex.swift` | `bpmRange`, `onlyUnavailable`, `.genre` sort, `unavailableTotal` | 1 |
| `Sources/Modules/AmpXModuleID.swift`, `AmpXModuleState.swift`, `AmpXLayout.swift`, `AmpXLayoutStore.swift` | `.library` id, default closed, size and frame, persistence | 2 |
| `Sources/Windows/AmpXHostCoordinator.swift`, `AmpXModuleWindowController.swift` | host it, resize constraints, live resize | 2 |
| `Sources/Components/AmpXModuleHeaderView.swift`, `AmpXModuleView.swift` | "LIBRARY" title, accessibility label | 2 |
| `Sources/Components/AmpXTextInput.swift` | custom `NSTextInputClient` field (text and numeric modes) | 3 |
| `Sources/Library/LibraryController.swift` | engine lifecycle, services, state | 4 |
| `Sources/Playlist/SecurityScopedBookmarkStore.swift`, `Sources/PlaylistManager.swift` | one shared bookmark store | 4 |
| `Sources/Modules/Library/LibraryColumns.swift` | column set, visibility, widths, sort mapping | 5 |
| `Sources/Modules/Library/LibrarySelection.swift` | click, ⇧ and ⌘ selection, keyboard focus | 5 |
| `Sources/Modules/Library/LibraryFilterState.swift` | UI state → `LibraryQuery`; preferences persistence | 5 |
| `Sources/Modules/Library/LibraryTrackTableView.swift` | header, rows, sort clicks, column menu, drag source | 6 |
| `Sources/Modules/Library/LibraryFacetListView.swift` | facet values with counts | 7 |
| `Sources/Modules/Library/LibraryToolbarView.swift`, `LibraryFooterView.swift`, `LibraryMixesSidebarView.swift`, `LibraryRootsMenu.swift` | toolbar, footer, ROOTS menu, placeholder sidebar | 8 |
| `Sources/Modules/Library/LibraryModuleContent.swift`, `LibraryModuleLayout.swift` | composition, pane frames, empty and error states | 9 |
| `Sources/Utilities/AmpXKeyRouter.swift`, `AmpXMenuBuilder.swift`, `AmpXMenuCatalog.swift`, `Sources/AmpXApplicationController.swift`, `Sources/AmpXAppDelegate.swift` | route 2b, ⌘F, ⌘L, Add Library Folder…, launch wiring | 10 |

`Sources/` and `Tests/AmpXTests/` are synchronized groups; new files need no project edit.

---

## Task 1: Query additions

**Files:** Modify `Sources/Library/LibraryQuery.swift`, `Sources/Library/LibraryIndex.swift`; extend `Tests/AmpXTests/LibraryQueryTests.swift` and `LibraryChangePublicationTests.swift`.

**Interfaces — produces:**

```swift
struct LibraryQuery {                       // existing fields unchanged
    var bpmRange: ClosedRange<Double>? = nil  // rows without bpm are excluded while set
    var onlyUnavailable = false               // MISSING view
}
enum LibrarySortColumn { case artist, title, genre, duration, bpm, musicalKey, bitrate }
struct LibraryResult {                       // existing fields unchanged
    let unavailableTotal: Int                 // unavailable rows in the whole snapshot, ignoring the query
    let totalDuration: Double                 // sum of `rows` durations
}
```

Decoding stays compatible: `LibraryQuery` gains a custom `init(from:)` that uses `decodeIfPresent` for every field, falling back to the defaults. The BPM range and the MISSING view act like facets: they filter rows **and** every facet's counts.

- [ ] **Step 1: Write failing tests:**
  - `testBpmRangeFiltersAndHidesUntagged`: range 120…126 keeps 120, 124 and 126; drops 119, 127 and nil.
  - `testBpmRangeAppliesToFacetCounts`.
  - `testOnlyUnavailableShowsMissingRows`.
  - `testGenreSortNilLastWithTieBreakers`.
  - `testDecodesQueryWithoutNewFields`: JSON from the Task-12 L1 encoder → defaults.
  - `testResultCarriesUnavailableTotalAndDuration`.
  - In `LibraryChangePublicationTests`: `testUnavailableTotalIgnoresQueryFilters`.
- [ ] **Step 2: Run `LibraryQueryTests LibraryChangePublicationTests`.** Expected FAIL.
- [ ] **Step 3: Implement.** Apply the range and availability in the same pass as the facet filters. `LibraryIndex` computes `unavailableTotal` from the cached snapshot once per version.
- [ ] **Step 4: Run `LibraryQueryTests LibraryChangePublicationTests LibraryBrowserModelTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: library query BPM range, missing view and genre sort`.

## Task 2: `library` module window

**Files:**
- Modify: `AmpXModuleID.swift`, `AmpXModuleState.swift`, `AmpXLayout.swift`, `AmpXLayoutStore.swift`, `AmpXHostCoordinator.swift`, `AmpXModuleWindowController.swift`, `AmpXModuleHeaderView.swift`, `AmpXModuleView.swift`, `AmpXModuleContent.swift`.
- Test: new `Tests/AmpXTests/AmpXLibraryWindowTests.swift`; extend `AmpXLayoutStoreTests.swift`.

**Interfaces — produces:**

```swift
enum AmpXModuleID { case player, equalizer, playlist, enthea, library }
enum AmpXMetrics {                                   // additions
    static let minimumLibrarySize = CGSize(width: 910, height: 420)
    static let defaultLibrarySize = CGSize(width: 1000, height: 500)
}
struct AmpXSavedLayout { var librarySize: CGSize = AmpXMetrics.defaultLibrarySize }
```

- **Default state.** `AmpXModuleState().closed == [.enthea, .library]`.
- **Layout DTO.** `AmpXLayoutV2DTO` gains `libraryOpen: Bool?`, `libraryWidth: Double?` and `libraryHeight: Double?`. A payload without `libraryOpen` (every layout saved before L2) keeps the Library closed. The size is raised to the minimum when read.
- **Size.** `AmpXLayout.moduleSize(.library, …)` returns `librarySize` expanded, and `(librarySize.width, headerHeight)` when collapsed.
- **Default frame.** The default frame sits flush below the lowest of Player, EQ and Playlist, left-aligned with the Player, and is clamped to the screen's visible frame.
- **Window controller.**
  - The resize constraints for the expanded `.library` window are min `minimumLibrarySize` and max unbounded.
  - Live resize updates `librarySize` and reflows the attached windows, as the Playlist does.
- **Header.** "LIBRARY" (its placement is measured once against the PLAYLIST title's metrics); no minimize button. The accessibility label is "Library".
- **Content.** `createModuleViews` builds a placeholder `LibraryModuleContent` (grey panel) until Task 9 replaces its body. `AmpXModuleContent.make` gains the `.library` case.

- [ ] **Step 1: Write failing tests:**
  - `testLibraryClosedByDefault`.
  - `testLegacyLayoutWithoutLibraryKeepsItClosed`.
  - `testLibrarySizeRoundTripsAndClampsToMinimum`.
  - `testDefaultLibraryFrameBelowStack`.
  - `testLibraryFrameClampedToVisibleScreen` (Review Focus 4).
  - `testReopenLibraryShowsAtSavedFrame`.
  - `testCollapsedLibraryIsHeaderOnly`.
  - `testLibraryHeaderHasNoMinimize`.
  - `testLibraryWindowResizeConstraints`.
  - `testLibrarySnapsAndMovesWithPlayerWhenAttached`: frames touching → `AmpXSnapGeometry` treats it as attached.
- [ ] **Step 2: Run `AmpXLibraryWindowTests AmpXLayoutStoreTests`.** Expected FAIL.
- [ ] **Step 3: Implement,** letting the compiler list every exhaustive `switch` on `AmpXModuleID` (header titles, compact heights, accessibility labels, menu toggles). Library never has a compact view.
- [ ] **Step 4: Run** `AmpXLibraryWindowTests AmpXLayoutStoreTests AmpXLayoutTests AmpXHostCoordinatorTests AmpXSnapGeometryTests AmpXWindowDragTests AmpXModuleStateTests`. Expected PASS; the existing suites unchanged.
- [ ] **Step 5: Commit** `feat: host the library as a snapping module window`.

## Task 3: `AmpXTextInput`

**Files:** Create `Sources/Components/AmpXTextInput.swift`, `Tests/AmpXTests/AmpXTextInputTests.swift`.

**Interfaces — produces:**

```swift
final class AmpXTextInput: AmpXControlView, NSTextInputClient {
    enum Mode { case text, numeric }            // numeric: digits and one "."
    init(skin: any AmpXSkin, mode: Mode = .text, placeholder: String)
    var committedText: String { get set }        // excludes marked text
    var onChange: ((String) -> Void)?            // fires on committed changes only
    var onCommit: ((String) -> Void)?            // Enter / Tab / resign
    var onEscape: (() -> Void)?                  // after the built-in clear-then-resign rule
}
```

**Behaviour:**
- **Drawing:** an LCD well (`skin.display`), text in `skin.green`, a dim placeholder, and a block caret that blinks only while the window is key. The selection is drawn in `skin.selection`; marked text is underlined.
- **Editing:** `insertText`, `setMarkedText`, `unmarkText`, `selectedRange`, `markedRange`, `attributedSubstring(forProposedRange:)` and `firstRect(forCharacterRange:)` go through `NSTextInputContext`. Editing commands use `doCommand(by:)`: `deleteBackward:`, `deleteForward:`, `moveLeft:`/`moveRight:` (± `…AndModifySelection:`), `moveWordLeft:`/`moveWordRight:`, `moveToBeginningOfLine:`/`moveToEndOfLine:`, `selectAll:`, `insertNewline:` and `insertTab:` (commit), and `cancelOperation:` (Escape).
- **Clipboard:** copy, cut and paste via the responder chain actions.
- **Escape:** if the text is non-empty, clear it (with `onChange`); otherwise resign first responder and call `onEscape`.
- **Accessibility:** the text-field role; value = `committedText`; the placeholder is the description.

- [ ] **Step 1: Write failing tests,** driving the `NSTextInputClient` methods directly:
  - `testInsertAndDelete`.
  - `testWordMotionAndSelection`.
  - `testMarkedTextDoesNotChangeCommittedValue`: set marked "e", then unmark with "é" → committed "é", and `onChange` fires once.
  - `testPasteInsertsAtCaret`.
  - `testEscapeClearsThenResigns`.
  - `testNumericModeRejectsLetters`.
  - `testCommitOnEnterAndTab`.
  - `testAccessibilityValue`.
- [ ] **Step 2: Run `AmpXTextInputTests`.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `AmpXTextInputTests AmpXKeyboardFocusTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: add custom text input component`.

## Task 4: `LibraryController` and the shared bookmark store

**Files:**
- Create: `Sources/Library/LibraryController.swift`, `Tests/AmpXTests/LibraryControllerTests.swift`.
- Modify: `Sources/Playlist/SecurityScopedBookmarkStore.swift` (`static let shared`) and `Sources/PlaylistManager.swift` (`static let shared = PlaylistManager(bookmarkStore: .shared)`).

**Interfaces — produces:**

```swift
@MainActor final class LibraryController: ObservableObject {
    enum State: Equatable { case notConfigured, opening, ready, failed(String) }
    @Published private(set) var state: State
    init(configuration: @escaping @Sendable () -> LibraryEngineConfiguration)
    func startIfConfigured() async                 // launch; flag off → .notConfigured, no container
    func ensureEngine() async throws -> LibraryEngine   // first Add Folder
    var engine: LibraryEngine? { get }
    func makeBrowserModel(playlist: PlaylistManager) -> LibraryBrowserModel?   // nil until .ready
    func stop() async                              // app termination
}
```

`failed` carries the user-facing message; `LibraryContainerError.newerSchema` maps to "This library was saved by a newer version of AmpX and was left untouched."

- [ ] **Step 1: Write failing tests** (engine configuration uses an isolated flag, a temp store URL and the fake file system from the L1 test support):
  - `testFlagOffStaysNotConfiguredAndOpensNoContainer`.
  - `testFlagOnOpensEngine`.
  - `testEnsureEngineOpensOnceWhenCalledTwiceConcurrently`.
  - `testNewerSchemaFailureMessage`.
  - `testStopStopsEngine`.
  - `testPlaylistSharedUsesSharedBookmarkStore`.
- [ ] **Step 2: Run `LibraryControllerTests`.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `LibraryControllerTests PlaylistManagerTests SecurityScopedBookmarkStoreTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: own the library engine lifecycle`.

## Task 5: Pure models — columns, selection, filter state

**Files:** Create `Sources/Modules/Library/LibraryColumns.swift`, `LibrarySelection.swift` and `LibraryFilterState.swift`, with tests `LibraryColumnsTests.swift`, `LibrarySelectionTests.swift` and `LibraryFilterStateTests.swift`.

**Interfaces — produces:**

```swift
enum LibraryColumn: String, CaseIterable, Codable {
    case number, artist, title, genre, time, bpm, key, kbps, format
    var title: String                    // "#", "ARTIST", …
    var minimumWidth: CGFloat
    var weight: CGFloat                  // share of spare width
    var sortColumn: LibrarySortColumn?   // nil for number, format
    var isHideable: Bool                 // false for title
}
struct LibraryColumnSet: Codable, Equatable {
    var visible: [LibraryColumn]         // display order = allCases order
    static let `default`: LibraryColumnSet   // all but .number
    mutating func toggle(_ column: LibraryColumn)   // ignores .title
    func frames(width: CGFloat) -> [(LibraryColumn, CGRect)]   // proportional, minimums honoured
}
struct LibrarySelection: Equatable {
    private(set) var ids: Set<UUID>; private(set) var anchor: UUID?; private(set) var focused: UUID?
    mutating func click(_ id: UUID, order: [UUID])
    mutating func shiftClick(_ id: UUID, order: [UUID])
    mutating func commandClick(_ id: UUID)
    mutating func moveFocus(by delta: Int, extend: Bool, order: [UUID])   // ↑↓, Page = ±visibleRows
    mutating func moveFocusToEdge(end: Bool, extend: Bool, order: [UUID]) // Home/End
    mutating func selectAll(order: [UUID])
    mutating func retain(present order: [UUID])                          // after refresh
}
struct LibraryFilterState: Codable, Equatable {
    var search = ""                      // committed text only
    var genres: Set<LibraryFacetValue> = []; var artists: Set<LibraryFacetValue> = []
    var bpmMin: Double?; var bpmMax: Double?
    var showMissing = false
    var sort: LibrarySortColumn = .artist; var ascending = true
    var query: LibraryQuery { get }      // swaps min>max; blank = unbounded; missing → onlyUnavailable
    mutating func clear()                // keeps sort
    mutating func sortBy(_ column: LibrarySortColumn)   // same column toggles direction
    mutating func facetClick(_ value: LibraryFacetValue, facet: WritableKeyPath<Self, Set<LibraryFacetValue>>, command: Bool)
}
struct LibraryModulePreferences: Codable, Equatable {   // UserDefaults "AmpXLibraryModuleV1"
    var columns = LibraryColumnSet.default; var sort: LibrarySortColumn = .artist; var ascending = true
    var mixesFollowsSelection = false
    static func load(_ defaults: UserDefaults) -> Self; func save(_ defaults: UserDefaults)
}
```

- [ ] **Step 1: Write failing tests:**
  - **Columns:** `testDefaultHidesNumberOnly`, `testTitleCannotBeHidden`, `testFramesHonourMinimumsAndFillWidth` (at the minimum table width 420 and at 1,400), `testHidingSortedColumnFallsBackToArtist` (via filter state).
  - **Selection:** `testClickSelectsOne`, `testShiftClickExtendsFromAnchor`, `testCommandClickToggles`, `testArrowAndShiftArrow`, `testHomeEnd`, `testSelectAll`, `testRetainDropsVanished`.
  - **Filter state:** `testQueryMapping`, `testBpmSwapAndBlank`, `testFacetClickSingleAndCommandMulti`, `testClickingSelectedValueClearsFacet`, `testClearKeepsSort`, `testSortToggle`, `testPreferencesRoundTripAndDefaults`.
- [ ] **Step 2: Run the three suites.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the three suites.** Expected PASS.
- [ ] **Step 5: Commit** `feat: library columns, selection and filter models`.

## Task 6: Track table view

**Files:** Create `Sources/Modules/Library/LibraryTrackTableView.swift`, `Tests/AmpXTests/LibraryTrackTableViewTests.swift`.

**Interfaces:**
- **Consumes:** `LibraryColumnSet`, `LibrarySelection`, `LibraryRow`, `AmpXScrollbar`.
- **Produces:**

```swift
final class LibraryTrackTableView: AmpXControlView, NSDraggingSource {
    init(skin: any AmpXSkin)
    var rows: [LibraryRow] { get set }             // redraws, keeps scroll offset clamped
    var columns: LibraryColumnSet { get set }
    var selection: LibrarySelection { get set }
    var sort: (column: LibrarySortColumn, ascending: Bool) { get set }
    var onSelectionChange: ((LibrarySelection) -> Void)?
    var onSortClick: ((LibrarySortColumn) -> Void)?
    var onColumnsChange: ((LibraryColumnSet) -> Void)?
    var onActivate: ((UUID) -> Void)?              // double-click
    var onDragBegan: (([LibraryRow]) -> Void)?     // register root bookmarks
    func scrollToFocused()
    static let headerHeight: CGFloat = 22
}
```

**Behaviour:**
- **Header:** 22 pt, with small-caps titles and a ▲/▼ on the sorted column. Clicking a sortable title calls `onSortClick`.
- **Column menu:** right-clicking the header opens an `NSMenu` of every hideable column with a checkmark state; toggling calls `onColumnsChange`.
- **Rows:** 22 pt; only the visible range is drawn (`PlaylistRowLayout`'s visible-range math). Cell text is drawn with `.byTruncatingTail`, clipped to the column rect. Missing BPM or key draws a dim "—", a derived bitrate "~n", and the format is `codec` uppercased. Unavailable rows use `textDim`, the selection `skin.selection`, and the focused row a 1 pt outline.
- **Mouse:** click, ⇧-click and ⌘-click go through `LibrarySelection`; a double-click calls `onActivate`.
- **Drag:** a drag beyond 4 pt starts an `NSDraggingSession` with `NSURL`s of the *available* selected rows (a single URL if the dragged row is outside the selection) and calls `onDragBegan`.
- **Scrolling:** the scrollbar sits on the right, and the scroll wheel scrolls.
- **Accessibility:** the table role; rows are children with settable selection; selection changes post notifications.

- [ ] **Step 1: Write failing tests:**
  - `testVisibleRowRangeOnly` (a draw spy counts rows drawn).
  - `testHeaderClickReportsSort`.
  - `testHeaderMenuListsHideableColumnsWithState`.
  - `testCellTextTruncatesWithinColumn` (Review Focus 2).
  - `testDashForMissingBpmAndKey`.
  - `testClickShiftCommandSelection`.
  - `testDoubleClickActivates`.
  - `testDragPasteboardHasAvailableURLsOnly`.
  - `testAccessibilityRowsAndSelection`.
- [ ] **Step 2: Run `LibraryTrackTableViewTests`.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `LibraryTrackTableViewTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: draw the library track table`.

## Task 7: Facet list view

**Files:** Create `Sources/Modules/Library/LibraryFacetListView.swift`, `Tests/AmpXTests/LibraryFacetListViewTests.swift`.

**Interfaces — produces:**

```swift
final class LibraryFacetListView: AmpXControlView {
    init(skin: any AmpXSkin, title: String)        // "GENRE" / "ARTIST"
    var values: [(LibraryFacetValue, Int)] { get set }   // sorted by name, (No Genre) last
    var selected: Set<LibraryFacetValue> { get set }
    var onClick: ((LibraryFacetValue, _ command: Bool) -> Void)?
}
```

**Behaviour:**
- The title bar shows the title and the value count.
- Rows are 22 pt, with the value on the left and the count right-aligned; `.absent` reads "(No Genre)" or "(No Artist)".
- Selected rows use `skin.selection`.
- The list has its own `AmpXScrollbar`.
- Accessibility reads each row as "value, count".

- [ ] **Step 1: Write failing tests:**
  - `testSortsByNameWithAbsentLast`.
  - `testClickAndCommandClickReport`.
  - `testAbsentLabel`.
  - `testAccessibilityValueCount`.
- [ ] **Step 2: Run `LibraryFacetListViewTests`.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `LibraryFacetListViewTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: draw library facet lists`.

## Task 8: Toolbar, footer, ROOTS menu, MIXES WELL placeholder

**Files:** Create `LibraryToolbarView.swift`, `LibraryFooterView.swift`, `LibraryRootsMenu.swift` and `LibraryMixesSidebarView.swift` under `Sources/Modules/Library/`, with tests `LibraryChromeTests.swift` and `LibraryRootsMenuTests.swift`.

**Interfaces — produces:**

```swift
final class LibraryToolbarView: AmpXDrawingView {
    let search: AmpXTextInput; let bpmMin: AmpXTextInput; let bpmMax: AmpXTextInput
    var onSearch: ((String) -> Void)?; var onBpm: ((Double?, Double?) -> Void)?; var onClear: (() -> Void)?
    func apply(_ state: LibraryFilterState)
}
final class LibraryFooterView: AmpXDrawingView {
    func update(trackCount: Int, totalDuration: Double, progress: ScanProgress?, missing: Int, showingMissing: Bool)
    var onToggleMissing: (() -> Void)?; var onEnqueue: (() -> Void)?; var rootsButton: AmpXButton { get }
}
enum LibraryRootsMenu {
    struct Actions { var add: () -> Void; var relocate: (UUID) -> Void; var remove: (UUID) -> Void }
    static func make(roots: [LibraryRootSnapshot], actions: Actions) -> NSMenu
    static func removeConfirmation(rootName: String, trackCount: Int) -> (message: String, info: String)
}
final class LibraryMixesSidebarView: AmpXDrawingView {
    var followsSelection: Bool { get set }; var onModeChange: ((Bool) -> Void)?
    func updateReference(_ row: LibraryRow?)   // playing track or focused row
}
```

**Behaviour:**
- **Status:** "UP TO DATE" with a green LED when `progress == nil`; otherwise "SCANNING done / total" with an amber LED.
- **n MISSING:** hidden when `missing == 0`; lit while the MISSING view is active.
- **Remove confirmation text** (exact):
  - message: `Remove "\(name)" from the library?`
  - info: `Its \(n formatted with grouping) tracks and their ratings and play counts will be removed. The files are not deleted.`
- **Root status lines:** "Available", "Unavailable" or "n folders unreadable".
- **Sidebar placeholder text:** "Recommendations arrive with DJ mode (BPM & key analysis)."; + QUEUE disabled.

- [ ] **Step 1: Write failing tests:**
  - `testToolbarReportsSearchBpmAndClear`.
  - `testFooterStatusTexts`.
  - `testMissingButtonHiddenAtZero`.
  - `testRootsMenuItemsAndStatus`.
  - `testRemoveConfirmationText`.
  - `testSidebarPlaceholderAndDisabledQueue`.
  - `testSidebarModeToggleReports`.
- [ ] **Step 2: Run `LibraryChromeTests LibraryRootsMenuTests`.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `LibraryChromeTests LibraryRootsMenuTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: library toolbar, footer, roots menu and mixes sidebar`.

## Task 9: Compose `LibraryModuleContent`

**Files:** Create `Sources/Modules/Library/LibraryModuleLayout.swift`, `Tests/AmpXTests/LibraryModuleContentTests.swift`; replace the Task-2 placeholder in `Sources/Modules/Library/LibraryModuleContent.swift`.

**Interfaces:**
- **Consumes:** Tasks 1 and 3–8, `LibraryController`, `LibraryBrowserModel`, `PlaylistManager`, `AudioPlayer.currentTrack`.
- **Produces:**

```swift
enum LibraryModuleLayout {   // content-local frames for a content size
    static func frames(size: CGSize) -> (toolbar: CGRect, genre: CGRect, artist: CGRect, table: CGRect, sidebar: CGRect, footer: CGRect)
}   // left column 230, sidebar 260, toolbar 32, footer 34, 6 pt gutters
final class LibraryModuleContent: AmpXModuleContent {
    init(skin: any AmpXSkin, controller: LibraryController, playlist: PlaylistManager, audioPlayer: AudioPlayer,
         panels: LibraryPanelPresenting = AppKitLibraryPanels(), defaults: UserDefaults = .standard)
    func focusSearch()                       // ⌘F
    func handleKey(_ event: NSEvent) -> Bool // route 2b (Task 10)
    func windowDidClose()                    // stops the browser model only
}
protocol LibraryPanelPresenting {            // injectable for tests
    func chooseFolder(title: String) async -> URL?
    func confirmRemove(message: String, info: String) async -> Bool
    func showError(_ message: String)
}
```

**Behaviour:**
- **State flow:** `LibraryFilterState` → `model.setQuery`. The model's `rows`, `facets` and `selection` → the views. Preferences load at init and save on change.
- **Actions:**
  - `onActivate` / ↩ → `model.enqueue(append: false, clickedID:)`.
  - ⌘↩ / ENQUEUE → append.
  - The drag start registers each root in `SecurityScopedBookmarkStore.shared`.
- **Folders:** Add Folder calls `controller.ensureEngine()`, then `engine.addRoot(url:)`. Store errors (`overlappingRoot`) go to `panels.showError` with "That folder overlaps a folder already in the library."
- **States:** `.notConfigured` → the empty state ("No library folders yet" + ADD FOLDER…). `.failed(msg)` → an error panel. `.ready` → the browser.
- **MIXES WELL reference:** the playing track's row (matched by URL through the current rows) or the focused row.

- [ ] **Step 1: Write failing tests** (fake panels, a controller over a temp engine with the fake file system):
  - `testFramesAtMinimumDefaultWide`.
  - `testQueryIgnoresMarkedText` (Review Focus 1).
  - `testSearchFacetBpmMissingDriveQuery`.
  - `testDoubleClickReplacesAndPlays`.
  - `testCommandReturnAndEnqueueAppend`.
  - `testSelectAllEnqueuesInDisplayOrder` (11,000 rows, under 1 s; Review Focus 3).
  - `testEmptyStateThenAddFolderOpensEngine` (Review Focus 5).
  - `testEngineErrorShowsErrorState`.
  - `testRemoveAsksAndRemoves`.
  - `testOverlapErrorShown`.
  - `testPreferencesPersistColumnsSortMixesMode`.
  - `testWindowCloseKeepsEngineRunning`.
- [ ] **Step 2: Run `LibraryModuleContentTests`.** Expected FAIL.
- [ ] **Step 3: Implement.** Wire `AmpXHostCoordinator.makeModuleContent(.library)` to build it with the app's `LibraryController`, passed in through a new `libraryController:` init parameter (default nil → empty state).
- [ ] **Step 4: Run `LibraryModuleContentTests AmpXLibraryWindowTests LibraryBrowserModelTests`.** Expected PASS.
- [ ] **Step 5: Commit** `feat: compose the library module`.

## Task 10: Keyboard, menus and launch wiring

**Files:** Modify `AmpXKeyRouter.swift`, `AmpXMenuBuilder.swift`, `AmpXMenuCatalog.swift`, `AmpXApplicationController.swift` and `AmpXAppDelegate.swift`; extend `AmpXKeyRouterTests.swift` and `AmpXMenuCatalogTests.swift`; create `Tests/AmpXTests/LibraryWiringTests.swift`.

**Interfaces — produces:**
- A new `AmpXKeyRoute.library`, chosen after `.playlist` and before `.enthea` when `context.module == .library` and the key is one of:
  - ↑↓ Home End PageUp PageDown (± ⇧);
  - ↩ and ⌘↩;
  - ⌘A;
  - ⌘F.
- `isTextResponder` also returns true for `AmpXTextInput`, so letters and Space type into search.
- **Menus:**
  - `AmpXMenuCatalog.ViewPanel.library = "Library"`: `Window ▸ Library` (⌘L) toggles the module, with its check state.
  - `AmpXMenuCatalog.FileItem.addLibraryFolder = "Add Library Folder…"` → `AmpXApplicationController.addLibraryFolder(_:)`.
- **Launch:** `AmpXAppDelegate` creates one `LibraryController`. The configuration uses `UserDefaultsLibraryStartupFlag(.standard)` and `bookmarkStore: .shared`. It is passed to the coordinator and the application controller, and `startIfConfigured()` runs in a `Task(priority: .utility)` after `application.start()`. `applicationWillTerminate` stops it.

- [ ] **Step 1: Write failing tests:**
  - `testLibraryRouteKeys`.
  - `testSpaceTypesIntoLibrarySearch`.
  - `testCommandFFocusesSearch`.
  - `testWindowMenuLibraryToggleAndShortcut`.
  - `testFileMenuAddLibraryFolder`.
  - `testLaunchWithFlagOffOpensNoContainer`.
  - `testAddLibraryFolderFromMenuOpensEngineAndShowsLibrary`.
- [ ] **Step 2: Run `AmpXKeyRouterTests AmpXMenuCatalogTests AmpXMenuBuilderTests LibraryWiringTests`.** Expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same suites plus `AmpXKeyboardFocusTests PlaylistKeyboardAdapterTests`. Expected PASS.
- [ ] **Step 5: Commit** `feat: library keyboard, menus and launch wiring`.

## Task 11: Verification

- [ ] **Step 1: Visual captures.** `./scripts/shoot.sh`, then open Library (⌘L) and capture it with `--index`, at:
  - the default size;
  - 910 × 420;
  - collapsed;
  - the empty state (fresh defaults suite via `-AmpXLibraryModuleV1` launch argument reset);
  - scanning `~/Music/DJ`.

  Compare each against the mockup's structure (pane order, toolbar, footer). Save the captures under `docs/superpowers/plans/library-module/` (force-added).
- [ ] **Step 2: Manual checks,** recorded in the spec:
  - **Success criterion 8:** add a root outside `~/Music`, enqueue, relaunch, play.
  - **Unplug:** rows dim within one refresh, and ROOTS shows *Unavailable*.
  - **VoiceOver:** navigate the table, the facets and search.
- [ ] **Step 3: Full suite.** `./scripts/run-tests.sh`. Expected: all pass.
- [ ] **Step 4: Update the spec status** to Implemented, with a link to the captures. Commit `test: verify the library module`.

## Coverage audit

| Spec section | Tasks |
|---|---|
| Decisions: style, facets, BPM, window, collapse, missing view, columns | 1, 2, 5–9 |
| UI amendment 1–3 (module ID, size, collapse) | 2 |
| UI amendment 4 (text input) | 3 |
| UI amendment 5–6 (key route 2b, commands) | 10 |
| Layout | 6–9 |
| Behaviour: query mapping, selection, facets, sort, columns, BPM, MISSING, actions, ROOTS, MIXES WELL, empty/error, start-up | 4–10 |
| Accessibility | 3, 6, 7, 11 |
| Performance | 6 (visible rows), 9 (large enqueue), L1 budgets |
| Engine additions | 1 |
| DJ-mode handoff | 8 (placeholder, persisted mode) |
| Success criteria 1–8 | 2, 9, 10, 11 |

## Execution handoff

Tasks are serial: Task 2 must land before Task 9, and Tasks 3 and 5–8 feed Task 9. Execute with subagent-driven development or inline executing-plans.

# Library Module (Music Library L2)

**Date:** 2026-09-27
**Status:** Approved design (user, 2026-09-27) — pending written-spec review
**Implements:** phase L2 of [Music Library, Revision 7](./2026-09-11-music-library-design.md). This document replaces that spec's *Browser module (L2)* section, and its *Required amendment* items 1–7 are resolved here.
**Amends:** [AmpX UI design, Revision 9](./2026-09-11-ampx-ui-design.md) — see *UI spec amendment* below.
**Related:** [DJ mode](./2026-09-11-dj-mode-design.md) fills the MIXES WELL sidebar this module reserves.
**Mockup:** [library-module/mockup-b2.png](./library-module/mockup-b2.png) (Codex render of the chosen layout in the app's style; spacing indicative, not a pixel reference).

## Goal

Make the L1 engine usable: a Library window that browses, searches and filters the collection, and sends tracks to the playlist. It must feel like the rest of AmpX (custom-drawn steel skin, LCD wells, no native controls). It should also make room for DJ-mode recommendations, which arrive later.

## Decisions (user, 2026-09-27)

| Topic | Choice |
|---|---|
| Style | Option B "wide browser", arrangement B2: facet lists on the left, track table in the middle, recommendations sidebar on the right |
| Facets | GENRE and ARTIST only; no album list, no album column |
| BPM | Range filter in the toolbar, working in L2 on tagged BPM |
| Recommendations | MIXES WELL sidebar with a PLAYING / SELECTED switch. L2 draws it with a placeholder; DJ mode fills it (only 391 of 2,232 tracks carry both BPM and key tags today) |
| Window | Its own window, like Winamp's Media Library. It snaps to the stack and other windows but never joins or widens the stack |
| Collapse (▢) | Header only, like ENTHEA |
| Unavailable tracks | No AVAILABLE ONLY switch. Unavailable rows are dimmed and cannot be enqueued; a footer "n MISSING" button appears only when n > 0 and toggles a view of just those rows |
| Columns | Right-click on the table header shows a checklist to show/hide columns; Title always visible |

## UI spec amendment

These changes to the AmpX UI design (Revision 9) take effect with this document:

1. **Module ID `library`.** The module has a close (✕) and a collapse (▢) header button, but no minimize and no detach/re-dock. It is **never part of the stack**: not in `order`, it does not count toward `leftWidth`, and the stack's overflow rule ignores it. Its window takes part in Winamp-style magnetic snapping like a detached module's. The previous amendment items 2 (second variable-height module in the stack) and 7 (docking inside the left column) are therefore void.
2. **Size.** The window is resizable in both axes. Minimum 910 × 420 pt, which fits the left column, a 420 pt table and the sidebar. No maximum. The UI is never scaled. The first open places it below the stack at 1,000 × 500 pt, clamped on-screen. Frame, collapsed state, visible columns and sort persist in `AmpXLayoutStore` under the `library` entry. Resize affordances follow the Playlist's: 6 pt bottom and right strips plus a bottom-right grip.
3. **Collapse.** Header-only collapse (ENTHEA rule). No compact presentation.
4. **Text input component.** Adds `AmpXTextInput`, a custom-drawn field that implements `NSTextInputClient`:
   - supports marked text and IME composition, selection, copy/cut/paste and ⌘A;
   - supports arrows, ⌥/⌘ word and line motion, and Delete/Forward Delete;
   - draws a block caret in an LCD well, and has a placeholder;
   - exposes the accessibility role text field, with its value.

   It is used for search and, in a numeric mode (digits and one decimal point only), for the two BPM boxes. `NSTextField` stays forbidden.
5. **Key router priority 2b — focused Library window**, after the Playlist (2) and before ENTHEA (3):
   - ↑/↓, Home/End and Page Up/Down move the focused row; with ⇧ they extend the selection.
   - ↩ replaces the playlist and plays; ⌘↩ appends.
   - ⌘F focuses search; Escape in search clears it, then leaves the field.

   While the search field has focus it is a *focused control* (priority 1), so letters type into it and Space is not play/pause.
6. **Commands.**
   - `Window ▸ Library` (⌘L) shows or hides the window. ⌘L is free: `AmpXMenuCatalog` uses bare L / ⇧L for Add Files / Add Folder.
   - `File ▸ Add Library Folder…`.

## Layout

At the default 1,000 × 500 pt, top to bottom:

- **Header:** the standard module header, reading "AmpX LIBRARY", with ▢ and ✕.
- **Toolbar** (one row):
  - the search field, taking the remaining width;
  - a BPM range: a "BPM" label, two numeric LCD boxes (min – max) and a ✕ to clear;
  - a steel **CLEAR** button, which resets search, BPM range, facet selections and the MISSING view.
- **Body** (three columns):
  - **Left, 230 pt:** GENRE on top and ARTIST below, each about half the height. Each is a list of values with right-aligned counts and a custom scrollbar. Nil genre shows as "(No Genre)".
  - **Middle, remaining width:** the track table with a header row and 22 pt rows (the Playlist's row metric).
    - Columns in order: #, ARTIST, TITLE, GENRE, TIME, BPM, KEY, KBPS, FORMAT.
    - A derived bitrate shows as `~243`, and a missing BPM or key as a dim `—`.
    - Unavailable rows use `textDim`; the selection uses the Playlist's selection colour; the focused row has an outline.
    - The table has a custom scrollbar.
  - **Right, 260 pt:** the MIXES WELL sidebar:
    - its title with a PLAYING | SELECTED two-segment switch;
    - a reference card showing the track being matched, its BPM and key;
    - the list;
    - a **+ QUEUE** button.
- **Footer:**
  - an LCD well with "n TRACKS · h:mm:ss" for the current result;
  - the scan status: an LED plus "UP TO DATE" or "SCANNING n / N";
  - **n MISSING**, only when n > 0;
  - **ROOTS ▾**;
  - **ENQUEUE**.

The # column is the row's position in the current result, not a stored track number.

## Behaviour

**Query mapping.** The search field, the facet selections, the BPM range, the MISSING view and the sort map onto one `LibraryQuery`. Every change runs `LibraryBrowserModel.setQuery`, so the existing generation rule drops stale results; there is no debounce, because the index answers inside the search budget.

**Selection.**
- A plain click selects one row.
- ⇧-click extends the selection from the anchor.
- ⌘-click toggles a row.
- The selection survives refreshes (L1 rule).

**Facets.** Clicking selects a single value; ⌘-click adds or removes a value (OR within a facet). Clicking the selected value again clears that facet.

**Sort.**
- Clicking a column header sorts by it; clicking it again reverses the direction. A small ▲/▼ marks the active column.
- Sortable columns: ARTIST, TITLE, GENRE, TIME, BPM, KEY, KBPS.
- # and FORMAT are not sortable.
- Hiding the sorted column falls back to ARTIST ascending.

**Columns.** Right-clicking the header opens a checklist of every column except TITLE. The default is everything visible except #. Column widths are proportional with per-column minimums; resizing columns by dragging is out of scope.

**BPM range.**
- Both boxes are optional and a blank box means unbounded; Enter, Tab or leaving the box commits it.
- If min > max, the two values swap.
- While a range is set, rows without a BPM are hidden and facet counts respect the range.
- ✕ clears the range.

**MISSING view.** The footer button appears when the snapshot has unavailable rows (missing files or unavailable roots). Toggling it shows only those rows, so you can relocate a root or remove them. The button stays lit while the view is active.

**Actions** (as in L1, using `LibraryBrowserModel.enqueue`):
- **Replace and play:** double-click or ↩.
- **Append:** ⌘↩, **ENQUEUE**, or dragging the selection onto the Playlist window (dropped rows append).
- Unavailable rows are skipped at action time. A selection with no available rows beeps.

**ROOTS ▾ menu.**
- **Add Folder…** opens an `NSOpenPanel` for directories.
- **One submenu per root:** its path and status (available, *unavailable*, *n folders unreadable*), **Relocate…** (`NSOpenPanel`), and **Remove…**.
- **Remove…** asks for confirmation: "Remove "DJ" from the library? Its 2,232 tracks and their ratings and play counts will be removed. The files are not deleted."
- Overlap errors surface as an alert with the store's explanation.

**MIXES WELL in L2.**
- The switch works and persists its mode.
- The reference card shows the playing track (PLAYING) or the focused row (SELECTED).
- The list area shows "Recommendations arrive with DJ mode (BPM & key analysis)."
- **+ QUEUE** is disabled.

**Empty and error states.**
- **No roots:** the table area shows "No library folders yet" and an **ADD FOLDER…** button.
- **Engine failed to open:** an alert shows the error; a store written by a newer version says so and leaves it untouched. The window shows the error state.

**Start-up and app wiring.**
- The app delegate creates one `SecurityScopedBookmarkStore`, passes it to `PlaylistManager.shared`, and calls `LibraryEngine.openIfConfigured` at `.utility` after launch.
- The first **Add Folder…** (from the menu or ROOTS) opens the engine with `LibraryEngine.open` if it is not running.
- Closing the window stops only the `LibraryBrowserModel`; the engine keeps scanning and watching until quit.

## Accessibility

- The table exposes rows with settable selection and selection-change notifications (as the Playlist does); each row reads Artist, Title, Time and BPM.
- Facet values expose "value, count".
- The search and BPM fields expose their values; buttons support press; the MIXES WELL switch exposes its state.
- Keyboard-only use covers every action above.

## Performance

- Drawing touches only visible rows; an 11,000-row result scrolls at the display rate.
- The L1 budgets carry through the UI: keystroke to published rows under 100 ms, and unavailability shown within 100 ms of the store save.

## Engine additions (small, in L1 types)

- `LibraryQuery` gains `bpmRange: ClosedRange<Double>?` and `onlyUnavailable: Bool`. Both are optional or default when decoding, so saved queries stay compatible.
- `LibrarySortColumn` gains `genre`.
- The query tests extend accordingly.

## DJ-mode handoff

DJ mode phase A-UI fills MIXES WELL:

- **Reference track:** follows the switch (playing, or the focused row).
- **Matches:** BPM within ±6% and a Camelot-compatible key (same, ±1, relative), per its *Key-compatible* rule.
- **Reason tags:** SAME KEY, +1, −1, REL, ±n%.
- **Controls:** enables + QUEUE, and switches the KEY column to Camelot notation.

The DJ-mode spec is updated to point here.

## Testing

| Area | Checks |
|---|---|
| Layout | Column and pane frames at the minimum, default and wide sizes; hidden columns reflow; the minimum size is enforced |
| Text input | Insert, delete and word motion; marked text and IME commit or cancel; paste; Escape clears then resigns; numeric mode rejects letters |
| Query mapping | Search, facets, BPM range (swap, blank, hides untagged), MISSING view, CLEAR, sort toggle and fallback |
| Selection | Click, ⇧-click range, ⌘-click toggle; focus movement by keyboard |
| Actions | Double-click and ↩ replace-play; ⌘↩ and ENQUEUE append; drag to Playlist appends; all-unavailable beeps |
| Menus and keys | ⌘L toggles; ⌘F focuses; 2b priority, and Space while search is focused; ROOTS menu items and the Remove confirmation text |
| Persistence | Frame, collapsed state, columns, sort and MIXES WELL mode restore after relaunch |
| Wiring | Launch with the flag off opens no container; first Add opens the engine; closing the window leaves the engine running |
| Visual | `shoot.sh` captures of default, minimum, collapsed, empty and scanning states, compared against the mockup's structure |
| Manual | Success criterion 8: tracks enqueued from a root outside `~/Music` play after relaunch |

## Out of scope

- Recommendation logic and Camelot keys (DJ mode).
- An album facet and album column.
- Column reordering and drag-resizing.
- A compact presentation.
- Tag editing.
- Artwork.
- Smart playlists (DJ mode).

## Files expected to change

- **New** `Sources/Modules/Library/` — module content, toolbar, facet lists, track table, MIXES WELL sidebar, footer, ROOTS menu, drag source
- **New** `Sources/Components/AmpXTextInput.swift`
- `Sources/Modules/AmpXModuleID.swift`, `AmpXLayoutStore.swift`, `Sources/Windows/*` — `library` window hosting and snapping, excluded from the stack
- `Sources/Utilities/AmpXKeyRouter.swift`, `AmpXMenuCatalog.swift` — priority 2b, ⌘L, Add Library Folder…
- `Sources/AmpXAppDelegate.swift` / `AmpXApplicationController.swift` — shared bookmark store, engine start-up
- Playlist: unchanged. Library drags put the available rows' file URLs on the pasteboard, which the Playlist's existing file drop imports (appending). The drag registers each involved root with the shared bookmark store when it starts.
- `Sources/Library/LibraryQuery.swift` — `bpmRange`, `onlyUnavailable`, `genre` sort
- Specs: this document; pointers in the UI, music library and DJ-mode specs

## Success criteria

1. ⌘L opens the Library window, which snaps to the stack without changing it. Its frame, columns and sort persist.
2. Search, genre and artist facets, the BPM range and the MISSING view filter together, with results under 100 ms.
3. Double-click plays through the existing `AudioPlayer` path, and ⌘↩, ENQUEUE and drag append — all with no change to `PlaylistManager`'s public API beyond accepting drops.
4. Unplugging a root dims its rows immediately, and the ROOTS menu offers Relocate…; Remove… names the track count.
5. With no roots at launch, no container is opened; the first Add Folder… opens the engine and scanning starts.
6. MIXES WELL shows its placeholder and the switch persists; nothing else depends on DJ mode.
7. Keyboard-only and VoiceOver can do everything above.
8. Tracks enqueued from a root outside `~/Music` play after relaunch.

# AmpX UI — develop parity inventory

**Date:** 2026-09-15
**Purpose:** Input for the next spec revision (Revision 10; Revision 9 is the horizontally resizable Playlist, decided 2026-09-16). Lists every user-facing behavior of the retired Classic UI on `develop` and its status in `feature/ampx-ui`, so each gap gets an explicit keep / drop / change decision instead of being discovered one at a time.

**Sources compared:** `develop` — `Views/Classic/*` (main player, shade, equalizer, playlist, visualizer panel), `SpectrumView.swift`, `AmpXCommands.swift`, `AmpXHotkeys.swift`, `AmpXPanelWindowManager.swift`. `feature/ampx-ui` — `Modules/*`, `Components/AmpXModuleHeaderView.swift`, `Windows/*`, `Utilities/AmpXMenuBuilder.swift`, `Utilities/AmpXKeyRouter.swift`.

**Excluded by user:** View ▸ UI Scale menu.

**Status key:** Present — same behavior. Changed — different behavior that may be acceptable. Missing — no equivalent. Fixed — restored on 2026-09-15.

**Decision column:** Keep (restore), Drop (accept removal), or Change (describe). Blank means undecided.

## Player

| ID | develop behavior | ampx-ui status | Proposal | Decision |
|---|---|---|---|---|
| P1 | Mini visualizer: click cycles Bars → Oscilloscope → Analyzer; choice persists (`visualizationMode`) | **Missing.** One segmented spectrum style only (`SpectrumWellView`) | Keep. Draw all three modes in the Classic Modern style; reuse the same `visualizationMode` key | **Done** 2026-09-16, revised 2026-09-17 — see the note below |
| P2 | Double-click mini visualizer shows/hides the Visualizer | **Missing** | Keep. Toggles the ENTHEA module | **Done** 2026-09-16: double-click toggles the ENTHEA module and never also cycles the mode |
| P3 | Track title scrolls (marquee) when longer than the display: text, `***`, text again, looping right-to-left at a constant speed; short titles stay still | **Missing.** Same text (`12. Artist - Title (3:45)`) but clipped at the track well edge, so the end of long titles and the duration are never visible | Keep | **Keep** (user 2026-09-16): restore the marquee. **Done** 2026-09-19 (`TrackTitleMarqueeView`) |
| P4 | Click time display toggles elapsed / remaining | Present | — | |
| P5 | Transport: previous, play, pause, stop, next; eject opens Add Files | Present | — | |
| P6 | Shuffle and repeat toggles; EQ and PL toggles show/hide modules | Present | — | |
| P7 | Volume and balance sliders (value-tinted tracks); position seek bar | Present | — | |
| P8 | Title bar options menu: Show/Hide Visualizer | **Changed.** Orange menu button has Add Files/Folder, Load/Save Playlist, playback, Quit. Visualizer toggle lives only in the View menu | Change: add Show/Hide Visualizer to the Player menu | **Change** (user 2026-09-16): add it to the Player menu, keep the View menu item |
| P9 | Title bar close button quits the app | **Changed.** Close hides the stack; playback continues; Quit is in the Player menu and ⌘Q (spec-defined) | Drop (keep spec behavior) | |
| P10 | Title bar minimize sends the window to the Dock | Present | — | |
| P11 | Shade mode: player shrinks to a 14 px strip with scrolling title, mini transport, time, and mini position bar | **Changed.** Collapse leaves only the module header; no transport, time, or title while collapsed | Decide in the collapsed-module plan | **Deferred** (user 2026-09-16): handled in a separate plan, not in this inventory |

## Equalizer

| ID | develop behavior | ampx-ui status | Proposal | Decision |
|---|---|---|---|---|
| E1 | ON / AUTO toggles, preamp, 10 bands, curve | Present | — | |
| E2 | Presets menu: built-in presets, Load EQF…, Reset | Present | — | |
| E3 | Shade (minimize) the equalizer panel | Changed. Module collapse | Drop (collapse covers it) | |

## Playlist

| ID | develop behavior | ampx-ui status | Proposal | Decision |
|---|---|---|---|---|
| L1 | Click, shift-range, ⌘-toggle selection; double-click plays; drag reorder; drop files | Present | — | |
| L2 | Row right-click menu: Play, Get Info, Remove from Playlist, Remove from Disk… | **Missing.** `presentTrackInfo` and `removeTrackFromDisk` have no UI caller | Keep | **Done** 2026-09-19. Right-click selects the row if it is not selected; Remove from Playlist removes the selection, the others act on the clicked row |
| L3 | Footer menus — ADD: Add File…, Add Directory…; REM: Remove, Crop, Clear Playlist; SEL: Select All, Select None, Invert Selection; MISC: Sort by Title/Filename/Path, Reverse, Randomize, File Info; LIST: New List, Save List…, Load List… | Present | — | |
| L4 | List follows the playing track; playing row white, selection fill only | **Fixed** (`4f53706`) | — | Keep |
| L5 | Resize the playlist height | Present, and extended by spec Revision 9 to horizontal resizing of the docked and detached Playlist (work in progress in this worktree) | — | |
| L6 | Mini transport in the footer | Present | — | |
| L7 | Playlist shade strip | Changed. Module collapse | Drop (collapse covers it) | |

## Visualizer (ENTHEA)

| ID | develop behavior | ampx-ui status | Proposal | Decision |
|---|---|---|---|---|
| V1 | ◀ / ▶ change mode (Shift nudges dose); title click toggles autopilot; DROP; theater button and F; LOOKS menu applies a look | Present | — | |
| V2 | **Photosensitivity notice** before first use (bright, rapidly changing patterns); OK stores acceptance | **Missing.** `EntheaPreferences.photosensitiveWarningAccepted` exists but nothing shows the notice | Keep — safety | **Drop** (user 2026-09-16): not wanted |
| V3 | Double-click the mode title reseeds the visualization | **Missing.** `reseed()` exists with no UI caller | Keep | |
| V4 | LOOKS menu: section heading, per-look description tooltip, and disclaimer tooltip | **Missing.** Plain list of look titles | Keep | |
| V5 | Tooltips: "Theater mode (F)", "Force drop effect" | **Missing.** Accessibility titles only, no hover tooltips | Keep (tooltips on all header/module buttons) | |

## App, menus, keyboard, windows

| ID | develop behavior | ampx-ui status | Proposal | Decision |
|---|---|---|---|---|
| A1 | File menu: Add Files/Folder (with shortcuts), Load/Save Playlist; Playback menu; View panel toggles | Present | — | |
| A2 | Keyboard shortcuts (global playback, playlist editing, F/Escape theater) | **Fixed** (`e121ec9`); Space is always play/pause | — | Keep |
| A3 | Separate windows with magnetic edge snapping and group dragging (docked clusters move together) | Changed. Single module stack with detach/re-dock; snapping is out of scope in the spec (see `docs/DOCKING_MAGNETISM_OPTIONS.md` on `develop` checkout) | Stay out of scope | **Drop** (user 2026-09-16): out of scope; detached modules stay free-floating |

## P1 mini visualizer — implemented behavior (2026-09-17)

The first pass (2026-09-16) shipped the three modes but was reported as unresponsive in use. Two
defects and one gap, all fixed:

- **Cycling was deferred by a full `NSEvent.doubleClickInterval`** so a single click could still be
  ruled out as a double-click, and the pending change was cancelled by the next click. A click
  lagged half a second or more, and two clicks in a row cancelled the cycle *and* fired the
  double-click handler, so the ENTHEA visualizer opened instead of the mode advancing. The click now
  cycles immediately; the second click of a double-click reverts the advance (persisting the revert)
  before toggling ENTHEA, so a double-click still never changes mode.
- **`wakeRendering()` left the parked frame's timestamp in place**, so the first frame after the
  display link un-parked carried the whole parked interval as its delta and drove the smoothing and
  falloff to their extremes. It now clears `lastTimestamp`, matching
  `MetalVisualizationRenderer.resume`'s `frameClock.resetDelta()`. Cycling the mode also wakes a
  parked well, so the newly chosen mode draws live data rather than the last pre-park frame.
- **The three modes were not visually distinct** — bars and analyzer drew the same segmented
  columns, differing only by peak marks (as develop did). The user asked for three distinct Core
  Graphics visualizers and picked from rendered candidates:
  - **Bars** — segmented columns with a per-column afterglow trail behind them, reproducing the
    persistence develop got from a GPU history texture. The trail follows the bar up instantly and
    falls linearly at `AmpXSpectrumColumnPipeline.trailFalloffPerSecond` (1.5/s, half the bars'
    3.0/s), drawn at `SpectrumWellView.trailAlpha`. An exponential fade fast enough to clear the well
    stays behind the linear bar falloff and is never visible — the trail must fall linearly.
  - **Oscilloscope** — thin green waveform line (unchanged; candidate A, chosen 2026-09-16). An
    empty sample buffer now draws the flat zero line instead of nothing.
  - **Analyzer** — one thin continuous bar per analysis band (32, not the 16 folded columns) with a
    floating peak cap, via `AmpXAnalyzerBarLayout`.

**Renderer decision (user, 2026-09-17):** stay on Core Graphics for the mini well; Metal stays for
ENTHEA. One measured well frame costs ~125 µs at 336 × 190 device px — 0.75% of a 60 Hz budget, so
the renderer is not the limit on visual ambition. Metal would only pay for itself here for per-pixel
effects (bloom, blur, feedback warp), and an `MTKView` cannot composite with the module's Core
Graphics drawing (well background, L/R labels, pixel snapping). The retired
`MiniSpectrumMetalPlugin` / `MiniAnalyzerMetalPlugin` / `MiniOscilloscopeMetalPlugin` remain in the
tree if that changes.

A reference presentation now always draws the segmented columns, so the deterministic captures no
longer depend on whichever mode the user last persisted.

## Order of work

Decided rows, in build order:

1. V2 photosensitivity notice (safety).
2. P1 + P2 mini visualizer modes and double-click (needs oscilloscope/analyzer mockups first).
3. L2 playlist row context menu.
4. P3 scrolling title (decided 2026-09-16).
5. V3 ENTHEA reseed on double-click; V4–V5 look descriptions and tooltips; P8 Show/Hide Visualizer in the Player menu (decided 2026-09-16).

Not in this queue: P11 collapsed Player (separate plan), A3 window snapping (out of scope), View ▸ UI Scale (excluded by user).

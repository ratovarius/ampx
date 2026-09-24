# AmpX UI: AppKit / Core Graphics Module Architecture

**Date:** 2026-09-11

**Compact presentation addendum (2026-09-19):** [Functional Collapsed Modules](2026-09-15-shrunk-modules-design.md) supersedes this document's header-only collapse descriptions for Player, EQ, and Playlist. Playlist retains its selected width while compact; only its expanded presentation resizes. Vertically stacked modules have zero gaps; the 6 pt gap applies only to the right-side ENTHEA column. ENTHEA's header-only collapse is unchanged.

**Status:** Revision 9 — horizontally resizable Playlist, decided by user 2026-09-16. Revision 8 (Playlist resize affordance, value-colored volume/balance tracks, 2026-09-14) and Revision 7 (fixed module dimensions and right-side visualizer, 2026-09-13) remain in effect except where this revision changes them.

**Revision 9 origin.** User request: the Playlist must also resize horizontally, with a minimum equal to the fixed Equalizer width and no maximum. This relaxes Revision 7's "every module is 490 pt wide and host width changes only with the ENTHEA column". Decisions (user, 2026-09-16): horizontal resize applies to the docked **and** detached Playlist, and a wider Playlist **stretches** its content (same type size, more visible title text) instead of scaling up.

**Revision 8 origin.** Two defects shipped because behavior-bearing appearance was left to the static PNG. (1) The spec defined *what* resizes (only Playlist, vertically) but not *where* or *how it is discovered*; it assumed a native titled window edge while hosts were built borderless, and the Classic Playlist resize grip was not listed for preservation. (2) "Colored slider tracks" was satisfied with one color sampled per slider from a single frame, although Classic tinted volume by value and balance by distance from center. Live pointer checks that would have caught both were deferred.

**Review history:** [Design review](./2026-09-11-ampx-ui-design-review.md)

## Goal and scope

Replace the Classic UI with an original, high-DPI evolution of the Winamp instrument panel: dark navy panels, steel-blue borders, micro-bevels, black display wells, monospace text, and green/yellow/orange accents. Visual fidelity and reliable module ordering, collapse, detach, and re-dock are equally important.

The primary interface uses **AppKit and Core Graphics**, with custom controls and chrome. It contains no SwiftUI, `NSButton`, `NSSlider`, `NSTextField`, `NSTableView`, `NSScrollView`, native scrollbars, or SF Symbols. Open panels, alerts, and About remain native system UI.

This replaces the UI layer only. Audio, playlist persistence, visualization, ENTHEA internals, shaders, and models remain unchanged, except for moving the existing playlist actions into `Sources/Playlist/`. The UI hotkey router is replaced as described below. Library, DJ mode, new audio features, magnetic window snapping, legacy layout migration, additional skins, a skin picker, and `.wsz` loading are out of scope. The Classic sprite skin and 275 px geometry are retired at cutover.

### References

- [AmpX.png](../../../screenshots/AmpX.png) is the visual acceptance target, not a mood board. It governs appearance and measured geometry, except for the explicit choices below. Existing implementation screenshots and measurement tables do not override it.
- This spec governs behavior and architecture.
- [AmpX UI.pdf](./AmpX%20UI.pdf) supplies rationale and illustrative guidance; its code and dimensions are not implementation contracts.
- Related: [app identity](./2026-09-11-app-identity-design.md), [windowing review](../../WINDOWING_REVIEW.md), [magnetism options](../../DOCKING_MAGNETISM_OPTIONS.md).

## Visual contract

Each module is **490 pt wide** at its fixed reference size; from Revision 9 the Playlist's width is variable (minimum 490 pt, no maximum) while every other module stays fixed. Player/EQ/Playlist occupy the left column; docked ENTHEA occupies a second column on the right. The PNG's 499 × 788 pt canvas includes background padding that is excluded from the window; macOS supplies its shadow.

| Metric | Starting value at scale 1.0 |
|---|---|
| Player height | 223.5 pt |
| Equalizer height | 225.5 pt |
| Playlist height | 305 pt |
| ENTHEA height when shown | 290 pt |
| Module gap | 6 pt |
| Button classes | Primary 44 × 40; secondary 64 × 32; utility 28 × 28 pt |

The panel measurements and button classes are starting values, not permission to standardize differently shaped reference controls. Phase 1 records annotated reference crops and source-pixel measurements, converts them to logical coordinates with explicit header/content origins, and records final geometry in the shared layout/metrics. Measure visible tracks, thumbs, and interaction bounds separately, including thumb travel endpoints; enlarging a hit area must not enlarge its artwork. Label estimates as estimates and validate them visually before freezing them. There is no invariant requiring the composition to total 788 pt.

**Required visual characteristics:**

- Preserve centered Player branding, uppercase EQ/Playlist titles, the reference's left glyph treatment, paired decorative lines, and header-button order. The grip interaction uses the existing left decoration; it does not introduce a generic menu icon.
- Match layered steel-blue frame edges, raised button faces, recessed black wells, and metallic slider thumbs. A single outline or flat fill is not an equivalent bevel treatment.
- Button faces use the Midnight Hardware key material (revision 2026-09-23, superseding the 2026-09-22 light-steel faces): one navy face with light `faceInk` glyphs shared by every button and slider/scrollbar handle. The bevel stays raised in every state: hover lifts the face and brightens the bevel; a press darkens both and sinks the ink 0.5 pt. Accent glyphs use the bright `faceGreen`/`faceAmber`/`faceOrange` roles. The orange menu button keeps its own face with light ink, and non-interactive raised surfaces use `AmpXFaceStyle.surface`. The Playlist scrollbar track is a recessed neutral trough (`neutralTrack`, shared with the seek bar), not a raised surface.
- Preserve slender colored slider tracks within their control areas, individual transport widths and spacing, indicator placement, and the separation of the EQ curve, toggles, preamp, and bands. Track color is value-driven, not a constant sampled from the PNG (see Player controls).
- The PNG is one frame. Any appearance that depends on a value, state, or pointer position must be specified in this document; a single sampled color or shape never satisfies such a requirement.
- Match text size, weight, baseline, and alignment. Keep metadata labels on one line without collisions or clipping. Timer digits retain consistent reference proportions and spacing as values change; shorter times must not stretch digits to fill the well.

**Theme.** Keep `AmpXSkin` small: palette, metrics, font family, and drawing primitives (`bevel`, `inset`, `accentLine`, `displayWell`). `ClassicModernSkin` is its only implementation. Components resolve colors and dimensions through it; this scope does not include a general skin engine.

| Token | Value |
|---|---|
| `background` | `rgb(0.043, 0.059, 0.094)` |
| `panel` | `rgb(0.082, 0.106, 0.161)` |
| `panelLight` | `rgb(0.125, 0.157, 0.227)` |
| `border` | `rgb(0.231, 0.275, 0.361)` |
| `borderHighlight` | `rgb(0.396, 0.443, 0.529)` |
| `borderDark` | `rgb(0.035, 0.047, 0.078)` |
| `text` | `rgb(0.902, 0.929, 0.969)` |
| `textDim` | `rgb(0.545, 0.588, 0.667)` |
| `selection` | `rgb(0.13, 0.18, 0.29)` |
| `green` / `yellow` / `orange` | `#00FF32` / `#FFD21A` / `#FF9D00` |
| `display` | `#000000` |
| `gold` / `goldLight` | Sample from PNG in Phase 1 |

**Typography.** Bundle Roboto Mono Regular, Medium, and SemiBold (Apache 2.0); register with `CTFontManagerRegisterFontsForURL` at process scope. Registration failure falls back to `NSFont.monospacedSystemFont`, logs once, and never prevents launch. Sizes resolve through the skin.

**Reference choices and exceptions:**

- Draw the seven-segment timer with custom segments; it is exempt from the Roboto Mono requirement. Phase 1 determines from the reference whether numeric kbps/kHz readouts need the same treatment.
- Use the PNG's gold bevelled scrollbar thumb rather than the PDF's steel-blue suggestion.
- Player has three header buttons; other modules have two, with semantics defined below.
- Exclude the reference's outer canvas padding.

The behavior-defined collapsed, detached, overflow, theater, and interactive states extend beyond the static PNG and use the same visual treatment. Live track text, time, spectrum, EQ values, and selection may differ during normal use; comparison captures use deterministic reference-matching data. Backing-scale rasterization may differ at individual antialiased edges, but not in geometry, spacing, hierarchy, or material treatment. Any further appearance deviation requires a specific reference/result crop, rationale, and user approval; do not self-accept it as a minor delta.

Every border, bevel, and hairline uses `AmpXPixelGrid`, including `pixelAlign(value, backingScale) = round(value * backingScale) / backingScale` and stroke-rectangle snapping. Re-snap and redraw on backing-scale changes without changing module order.

## Architecture and boundaries

The app delegate owns the models, registers fonts, constructs `NSMenu` menus from `AmpXMenuCatalog`, and creates the stack host. The stack and detached window controllers host the same module views.

| Responsibility | Contract |
|---|---|
| `AmpXDrawingView` | Layer-backed, flipped `NSView`; skin access, backing-scale observation, hover tracking, accessibility defaults |
| `AmpXModuleContent` | Draws within its bounds; does not reference `self.window`, draw host chrome, or know neighboring modules |
| `AmpXModuleView` / header | Shared frame, bevels, grip, yellow accent lines, brand/module label, and header buttons |
| `AmpXModuleOrder` | Pure state: `order`, `collapsed`, `detached`, `closed`; operations move, collapse, detach, re-dock, close, reopen; no geometry |
| Stack/layout/drag | Top-down layout, insertion target calculation, reorder and transfer gestures |
| Window hosts | Window behavior, scale, viewport, presentation, ownership, and effective visibility |

Use `Sources/Theme/`, `Components/`, `Modules/{Player,Equalizer,Playlist,Enthea}/`, and `Windows/` as the proposed organization, with fonts in `Resources/Fonts/`. Helper names and file splits may be refined in the implementation plan; the boundaries and behavior contracts are binding.

Reuse `AudioPlayer`, `PlaylistManager`, `Track`, `AudioFeatureBus`, parsers, DSP/EQ, `AmpXEQBands` (band count, labels, and curve geometry), `RemoteCommandController`, `NowPlayingInfo`, `PlaylistSelectionModel`, `AmpXPlaylistKeyboard`, `AmpXMenuCatalog`, `AmpXTimeFormatting`, and `TrackInfoFormatter`. Replace `AmpXHotkeys` with focus-based routing; it must no longer depend on the deleted panel manager.

## Modules and window behavior

Player is the anchor: it always remains in the stack's `order`, cannot detach, and never enters the module `closed` set. Equalizer, Playlist, and ENTHEA may collapse, close, detach, and re-dock. Player, Equalizer, and Playlist may reorder within the left column. Docked ENTHEA always occupies the right column; re-docking it restores that placement.

| Header button | Player | Other modules |
|---|---|---|
| `—` | Miniaturize stack window | Not shown |
| `▢` | Collapse/expand Player content only | Collapse/expand that module's content |
| `✕` | Close stack window | Close that module |

Collapsed modules retain their headers. Closing the stack window hides it without quitting: playback, media keys, menus, and Now Playing continue; detached windows stay usable. Reopen through the Dock icon, `Window ▸ AmpX`, or re-docking a detached module. Restore the stored frame, order, collapsed state, and playlist viewport. If all non-anchor modules close, the stack shrinks to Player.

`order` retains closed modules. Reopening restores a module's position, prior detached state, and detached frame where applicable. Restored frames must be on-screen; a detached frame whose display is gone is clamped to the main screen's visible frame.

### Dragging and persistence

The left grip reorders or tears off a module; the rest of the header moves its host window. Detach/re-dock also has per-module Window menu commands and keyboard equivalents, but no header button.

Reorder and re-dock share the pure `dropIndex(stackGeometry:point:) -> Int?` calculation and a yellow 2 pt insertion marker. Dragging a detachable module more than 40 pt outside the stack tears it off, keeping it under the cursor. Dropping a detached module outside the stack leaves it detached at the release position. Collapsing a module during its content drag cancels the drag without changing order.

`AmpXLayoutStore` persists module state, stack/detached frames, playlist viewport height, and (Revision 9) playlist width as versioned JSON in UserDefaults. A payload without a stored width uses the 490 pt default, and a stored width below the minimum is raised to it. Missing, corrupt, or unknown-version payloads use defaults without throwing. Unknown module IDs are ignored while retaining recognized entries.

### Sizing and overflow

Normal hosts are borderless, resizable, and miniaturizable windows; AmpX draws all chrome. (Earlier revisions named a titled window with a hidden, transparent title bar; the implementation uses borderless hosts and this revision records that.) Native window-edge resizing is not a discoverable affordance on borderless hosts and must not be the only way to resize. Detached windows have no snapping or attraction.

```
normalUIScale = 1
playlistWidth = max(490, savedPlaylistWidth)          // Revision 9: no maximum
leftWidth = max(490, dockedPlaylistOpen ? playlistWidth : 490)
hostWidth = leftWidth + (dockedVisualizerOpen ? 6 + 490 : 0)
hostHeight = max(leftColumnHeight, dockedVisualizerHeight)
```

Only open, docked modules contribute to this composition. Collapsed modules contribute header height.

- Player and EQ retain their current reference width and height when the host is resized; horizontal resizing never scales the UI. Backing-scale changes still redraw crisply at the same logical dimensions.
- **Playlist width (Revision 9).** The Playlist is the only module with a variable width: minimum 490 pt (the fixed Equalizer width), no maximum. It applies docked and detached, is persisted like the viewport height, and survives collapse, close/reopen, detach and re-dock. Player, EQ and ENTHEA keep their 490 pt width at every Playlist width.
- **Host width (Revision 9).** The docked left column is as wide as its widest visible module, so the stack window width is `leftWidth + ENTHEA column`. Growing the Playlist keeps the window's left edge fixed and extends it to the right. Player and EQ stay 490 pt and left-aligned; the docked ENTHEA column shifts right to stay `moduleGap` clear of the left column, so a wide Playlist never overlaps it. When the Playlist is closed, detached or collapsed, host width returns to the fixed composition.
- Docked ENTHEA is top-aligned with the left column at `leftWidth + 6` pt (x=496 pt at the reference Playlist width), with its existing 490 × 290 pt normal dimensions. Opening it increases host width, not the left column's height. Closing or detaching it removes that column. Theater remains the explicit display-filling exception.
- Playlist is the only module with a variable normal height. Vertical resize adjusts its expanded viewport, changing row count. Detached Playlist supports the same vertical resizing at fixed width; other detached modules retain fixed normal dimensions. Preserve the preferred Playlist viewport independently of temporary screen constraints.
- **Playlist resize handle.** The expanded Playlist owns its resize affordance, in both docked and detached hosts and regardless of its position in the stack order:
  - A 6 pt strip along the Playlist module's bottom edge and a 6 pt strip along its right edge, plus a drawn grip (diagonal ridges, `borderHighlight`/`borderDark`) in the bottom-right corner below LIST OPTS. None may overlap a footer control's hit area.
  - Pointer over a strip or the grip shows the matching system resize cursor — `NSCursor.frameResize(position:directions:)` with `.bottom`, `.right`, and `.bottomRight` respectively; everywhere else keeps the normal cursor.
  - Dragging changes the preferred size by the pointer delta in screen coordinates: the bottom strip changes height only, the right strip width only, and the grip both. Height clamps to three rows and to the screen fit rule below; width clamps to the 490 pt minimum with no maximum. The module's top and left edges stay fixed. Save once when the drag ends, not per event.
  - A collapsed or closed Playlist exposes no handle and no resize cursor. Other modules never show a resize cursor.
- When the left column exceeds the screen's visible height, shrink only the expanded Playlist viewport by the excess, down to three rows. Never scale Player/EQ, scroll the stack, or automatically close/collapse/detach another module. Without an expanded docked Playlist, host height follows the fixed composition.
- The fixed Player+EQ column needs about 455 pt before Playlist chrome; screens smaller than the fixed minimum composition cannot show all of it. Keep its top edge reachable rather than violating fixed dimensions; this physical minimum is not a reason to reintroduce UI scaling.
- Closing a module must hide its view as well as exclude its frame from layout. Reopening restores the same view and recomputes all occupied frames. Resizing after a close must not leave stale module pixels covering another panel.
- Grip dragging must preserve the pointer's position within the module header across detachment and re-docking. Use source-window-to-screen conversion for each event; never interpret one window's event coordinates as another window's local coordinates. Detached modules remain visible during stack relayout.

### Theater

Theater is a distinct ENTHEA presentation mode. The window fills `screen.frame`; the visualization fills the window, bypassing ordinary scale and height rules. Hide module chrome and insets, use a black background, and add `.autoHideMenuBar` and `.autoHideDock` to `NSApp.presentationOptions` after capturing its prior value.

Entering and exiting reparent the same mounted ENTHEA view; never recreate its WebView. Exit restores the previous host (stack or detached), scale, frame, and presentation options. Visibility rules below continue to apply.

## State and rendering lifecycle

| State | Source and update path |
|---|---|
| Discrete: track, playlist, EQ, toggles, metadata | One Combine subscription set per module to model `@Published` values; invalidate only the smallest affected subview |
| Continuous: spectrum, time, position | Pull `AudioFeatureBus.spectrumSnapshot(at:)` and `PlaybackClock` through `NSView.displayLink(target:selector:)`; redraw only that view's bounds |

Continuous UI updates do not use Combine or invalidate the whole window. All continuous views and ENTHEA share an effective-visibility predicate:

```
isEffectivelyVisible = !module.isCollapsed && !module.isClosed
    && hostWindow.isVisible && !hostWindow.isMiniaturized
    && hostWindow.occlusionState.contains(.visible)
    && intersectsHostViewport
```

The stack does not scroll, so docked modules always intersect the stack viewport; the term is retained for host symmetry. Detached and theater hosts pass that viewport gate while retaining the other checks. Terms combine; viewport intersection cannot reactivate a collapsed or hidden module. Apply transitions only when the result changes.

| Transition | Display links and ENTHEA behavior |
|---|---|
| Visibility becomes false | Invalidate display links. Suspend ENTHEA rendering, deactivate audio/track bridges, stop its push timer; retain the host |
| Visibility becomes true | Resume display links and ENTHEA bridges/timer/render state |
| ENTHEA module closes | Call `teardown()` and release the host/WebView to release its WebContent resources |
| Detach, re-dock, enter/exit theater | Transfer ownership of the same view; work follows effective visibility in the destination host |

These rules apply to collapse, close, and window hide/miniaturize/occlusion.

## Module composition and controls

**Player:** Left approximately 37% holds a dotted black display well, play-state glyph, segment timer, and L/R spectrum. Right approximately 63% holds track text, bitrate/sample-rate/channel metadata (inactive channel label in `textDim`), two horizontal sliders, and EQ/PL toggles with green indicators. A full-width position bar sits above transport: previous, play, pause, stop, next, eject, shuffle, repeat, and orange menu button.

**Volume and balance tracks:** Winamp's original value coloring. A pure ramp maps an intensity `t` in 0…1 to color by linear RGB interpolation through green `rgb(14, 236, 2)` at 0, yellow `rgb(247, 210, 3)` at 0.5, and red `rgb(240, 32, 8)` at 1. Volume uses `t = value`; balance uses `t = |value − center| / halfRange`, so centered balance is green and either extreme is red. The ramp color fills the **entire track length, end to end, independent of thumb position**, as Winamp's full-width volume/balance bars do; only the color changes with the value, immediately (including reference presentation). There is no progress-style fill ending at the thumb and no unfilled remainder. This supersedes the PNG's fill-to-thumb appearance and Step 2 deviation 2 (fixed tint run past the thumb); approved by user 2026-09-14. (The first Revision 8 text specified the ramp's color but kept the PNG's fill extent, because the extent was never compared against Classic's full-width sprites.) Keep the ramp testable independently of drawing. At the reference values (volume 0.762, balance centered) volume renders orange-red rather than the PNG's orange; this is an approved deviation (user, 2026-09-14).

**Spectrum:** Discrete segmented columns; level determines lit-segment count, while vertical segment position determines color from green through yellow-green/yellow to orange. Floating peak-hold marks decay. Keep segment geometry, color-band mapping, and peak behavior testable independently of drawing; sample segment metrics/boundaries from the PNG in Phase 1.

**Equalizer:** ON/AUTO indicators, curve (revision 2026-09-22: one knot per band at its slider value, drawn with `MonotoneCubicSpline` so a raised band never dips its neighbours, run flat to the graph edges; preamp is its own horizontal line; single-slider moves redraw immediately and only multi-band jumps such as presets animate), PRESETS menu, preamp, and ten bands at 60 / 170 / 310 / 600 / 1K / 3K / 6K / 12K / 14K / 16K. Vertical tracks use rectangular metallic thumbs and a +12 / 0 / −12 dB scale. Bind existing EQ values, preamp, enabled, and auto-enabled state.

**Playlist stretching (Revision 9).** Beyond 490 pt the Playlist stretches; it never scales. Type size, row height, header height, footer control sizes and the scrollbar width stay at their reference values, and the extra width becomes visible content: the row area and its well grow, so longer titles show. The scrollbar stays at the right edge; row durations stay right-aligned in their 42 pt column; the footer's left buttons (ADD/REM/SEL/MISC) keep their left anchor while its right group (counter well, mini transport, remaining readout, LIST OPTS) keeps its right anchor. The Playlist header stretches the same way: the brand/title group stays centered, its gold rules fill the space, and the header buttons stay right-anchored. This is the one module whose content coordinates are not the 490 pt reference space.

**Playlist:** Custom rows, 22 pt high; index and Artist – Title left, duration right in a 42 pt column. Green text on black; the playing track's text is white (`text`) whether or not it is selected, and selection only draws a flat fill behind the row without changing text color (Winamp PLEDIT behavior, decided by user 2026-09-15). When the playing track changes and its row is not fully visible, the rows scroll to center it. Amber scrollbar arrows, gold thumb. Footer contains ADD/REM/SEL/MISC, mini transport, combined time counter, remaining-time readout, and LIST OPTS.

**ENTHEA:** Host the existing visualization surface inside standard module chrome, under the lifecycle and theater contracts above; internals remain unchanged.

Buttons distinguish normal, hover, pressed, active, and disabled states; active includes a green indicator. Sliders update immediately on click-to-position and drag. Permitted UI transitions are module settling (150–200 ms), button press (60–80 ms), and EQ curve follow (50–100 ms); other UI transitions do not animate.

## Keyboard and accessibility

`AmpXKeyRouter` uses focus context, with this precedence in both hosts:

| Priority | Context | Behavior |
|---|---|---|
| 1 | Focused control (reached by keyboard navigation; a click does not focus a control) | Return/Enter activates a button; arrows adjust a slider/EQ band; Escape moves focus out. Consumed keys do not reach playback |
| 2 | Focused Playlist module | Existing navigation, selection, removal, cropping, playback, and reorder bindings |
| 3 | Focused ENTHEA module | F toggles theater; Escape exits theater |
| 4 | Global, including while a control has focus | Existing playback, next/previous, volume, and seek bindings. Space always toggles play/pause (decided by user 2026-09-15). Space and unmodified letters are skipped while a text field has focus |

Stack, detached, and theater hosts are borderless but must accept key and main status; a borderless window that refuses key status receives no key events, so no binding above can run.

Module commands appear in the Window menu: `⌘⌥↑/↓` reorder the focused module, `⌘⌥D` detaches/re-docks, and `⌘⌥C` collapses/expands. All module operations must be reachable without dragging.

Every interactive component supplies an accessibility role, label, value, and change notifications. Buttons implement press; sliders expose min/max/current values in real units and increment/decrement actions (1 dB for EQ). Playlist exposes a selectable row hierarchy with settable selected rows and selection-change notifications. Modules expose applicable collapse/expand/close/detach/re-dock actions; scrollbars expose scroll position semantics.

Preserve focus across collapse/expand and reparenting; restore the previously focused element when its module becomes visible. Closing a module transfers focus to the next module in order. Validate all controls and module operations using keyboard only and VoiceOver.

## Migration

**Post-implementation correction:** The migration sequence below records the original replacement of Classic. Visual correction preserves working architecture, model bindings, persistence, and interaction infrastructure; it does not repeat completed extraction/cutover work or restore the retired UI. Revisit drawing, geometry, and affected controls under the visual gates below.

Keep the existing models and non-UI regression suites intact. Before deleting Classic:

- Move `PlaylistChromeActions` verbatim from `Views/Classic/PlaylistListInteractions.swift` to `Sources/Playlist/PlaylistChromeActions.swift`; retain `PlaylistChromeActionsTests` unmodified.
- Replace the SwiftUI-binding-based `PlaylistKeyboardNavigation` with an AppKit `AmpXPlaylistKeyboard.Handling` adapter preserving selection, navigation, playback, removal, cropping, and reorder. Reimplement `PlaylistTrackReorderModifier` with AppKit mouse tracking.
- Rename legacy `Sources/Utilities/AmpXMetrics.swift` to `LegacyPanelMetrics` so the new theme can own `AmpXMetrics`.
- Inventory Classic's dynamic visual and pointer behaviors before deletion and map each to a spec requirement or an explicit user-approved removal. Known items: value-tinted volume track and center-distance-tinted balance track (`AmpXSkinSprites.Volume/Balance.background(forNormalized:)`); gain-tinted EQ bands; the Playlist bottom-right resize grip. (Added in Revision 8 after the first two were lost at cutover.)

| Phase | Deliverable |
|---|---|
| 0 — Preparation | Extract playlist actions and rename legacy metrics; behavior unchanged |
| 1 — Static composition | Measure internal geometry/colors; theme, fonts, pixel grid, drawing base, module frames/headers, stack; mock data |
| 2 — Controls | Custom buttons, sliders, icons, segment digits, scrollbar, labels |
| 3 — Interaction | Module gestures, overflow viewport/auto-scroll, key router, keyboard operation and accessibility |
| 4 — Real state | Model wiring, playlist adapter, ENTHEA lifecycle and theater |
| 5 — Cutover | Port menus to NSMenu, remove old UI and feature flag, update project documentation |

Phases 1–4 use the `AmpXNewUI` UserDefaults flag, default NO, enabled with `-AmpXNewUI YES`. Phase 5 makes the new UI unconditional and deletes the flag. Every phase must build and pass `./scripts/run-tests.sh`; visual phases also iterate with `./scripts/shoot.sh` against the PNG.

At cutover delete:

- `Views/Classic/*`, `AmpXSkinSprites`, `ContentView`, `AmpXApp`, `AmpXCommands`, and the 14 `AmpXSkin*` imagesets.
- The panel/dock family: `AmpXPanelWindowManager`, `AmpXDockGraph`, `AmpXPanelColumnPack`, `AmpXPanelDescriptor`, `AmpXPanelLayoutState`, `AmpXPanelPlacement`, `AmpXPanelPositionStore`, and `Utilities/AmpXWindowSnap`.
- Superseded utilities: `AmpXUIScale`, `AmpXTypography`, `ClassicMarqueeTypography`, `PanelTitleBarDrag`, `AmpXWindowConfigurator`, and `LegacyPanelMetrics`.
- Tests tied to deleted implementations: `AmpXDockGraphTests`, `AmpXPanelColumnPackTests`, `AmpXWindowSnapTests`, and `ClassicUITests`.

Add the app delegate and proposed UI families, bundle/register fonts, update `Resources/Info.plist` as needed, update the module map in `AGENTS.md`, and mark `docs/WINDOWING_REVIEW.md` superseded.

## Acceptance and verification

The behavior contracts above are acceptance requirements. Verify them with:

**Visual gates:** First render the complete static Player, including its header and controls, with reference-matching content at scale 1.0. Capture at 2× backing scale to match the source PNG, crop to the same panel bounds, and inspect side-by-side and overlaid comparisons. Correct geometry, typography, materials, and glyphs before requesting user approval of that concrete screenshot. Do not extend the visual treatment to EQ/Playlist until this Player checkpoint is approved.

Then compare EQ and Playlist individually and as a complete expanded stack with matching mock data. Repeat comparisons after replacing static drawings with interactive controls and after model wiring, using a deterministic presentation of the same production drawing path. Record reference/result crops, build revision, UI/backing scales, remaining differences, and approval of any deviations. Overlaps, missing labels, stretched digits, changed header composition, or substituted control shapes fail acceptance. Unit tests and screenshot generation alone cannot establish visual fidelity; unresolved differences keep that gate open.

| Area | Required evidence |
|---|---|
| Visual fidelity | Approved Player checkpoint and reference/result comparisons for all three panels through static, interactive, and wired states; only documented approved deviations. Check crisp geometry at 1×/2×/3× backing scales with fixed normal module dimensions; font registration and fallback. Identify offscreen checks separately from physical-display captures |
| Layout and scale | Full, collapsed, Player-only, right-side ENTHEA, and detached layouts; Player/EQ/ENTHEA keep 490 pt at every Playlist width; only Playlist responds to vertical and horizontal resizing |
| Playlist width | Minimum 490 pt with no maximum, docked and detached; host width follows the widest left module with the ENTHEA column shifted clear; stretched rows/scrollbar/footer anchors and header at a wide width; width persisted, restored, and defaulted when missing or too small |
| Module state and persistence | Reorder/collapse/detach/re-dock/close/reopen, anchor enforcement, idempotence, insertion targets; JSON round-trip and missing/corrupt/unknown-version/unknown-ID handling |
| Stack height | Window height follows the two-column composition; no stack scrollbar. On a short screen, shrink only Playlist toward three rows while Player/EQ and the right-side visualizer keep their normal dimensions |
| Drawing models | Pixel/stroke snapping, segment count/color boundaries/peak decay, volume/balance ramp colors at 0, center, and extremes (balance symmetric), playlist row geometry, duration column, and visible ranges |
| Input and accessibility | Playlist-adapter parity, focus-routing precedence, keyboard-only operation, and VoiceOver actions/values/focus in both hosts. Playlist resize handle: hit-test at the bottom strip and grip resolves to the handle (not a footer control), handle cursor is vertical resize, dragging resizes docked and detached Playlist with fixed top edge, collapsed Playlist has no handle |
| Live pointer acceptance | Resize cursor appearance, handle dragging, and slider color change observed in the running app. These are required checks; when automation permissions are unavailable, they stay open and block acceptance rather than being substituted by unit tests |
| Visibility and lifecycle | Each gate independently suspends work; viewport intersection cannot override other gates; ENTHEA stops while collapsed or hidden; close releases its host |
| Theater | Display-filling content, restored host/scale/frame/presentation options, identical view instance across transitions, and continued window-visibility gating |
| Regression and cutover | Existing audio/playlist/ENTHEA/visualization/parsing suites stay green; playlist action tests unchanged; retired UI, assets, panel family, and flag removed |

Geometry refinement remains Phase 1 discovery work. Custom interaction, visibility, accessibility, and cutover risks are covered by these checks; review rationale and resolved alternatives remain in the linked review document.

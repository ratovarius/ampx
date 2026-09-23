# AmpX UI: Functional Collapsed Modules

**Date:** 2026-09-15

**Status:** Implemented and verified 2026-09-19. Compact Player's concrete visual checkpoint and shared material treatment are approved. EQ/Playlist use that treatment with the confirmed behavior choices. Final native and deterministic captures are available for review; their generation is not a claim of additional user visual approval. See [validation evidence](../plans/shrunk-modules/validation.md).

**Foundation:** [AmpX UI design, Revision 9](./2026-09-11-ampx-ui-design.md), the 2026-09-18 removal of vertical stack gaps (`01fd492`), and [Player mini visualizers](./2026-09-17-mini-visualizers-design.md).

**Implementation plan:** [Functional Collapsed Modules](../plans/2026-09-19-shrunk-modules.md).

## Goal and scope

Give the collapsed Player, Equalizer, and Playlist complete, usable compact presentations matching [shrinked_modules.png](../../../screenshots/shrinked_modules.png), subject to the confirmed corrections below. Preserve the expanded UI's materials, controls, fixed Player/EQ dimensions, resizable Playlist, and working interactions. The historical expanded reference is [ampX_UI_v1.1.png](../../../screenshots/ampX_UI_v1.1.png); its availability is recorded under review evidence below.

“Shrunk,” “compact,” and “collapsed” describe the same module state. Continue using the existing `collapsed` state; this is not a second mode or a new window type. Collapsing switches the module's presentation, with useful controls remaining visible.

This is an addendum to the original UI spec, using the existing AppKit/Core Graphics controls, Metal mini visualizers, measurement process, deterministic captures, and visual approval gates. It does not repeat the Classic migration. ENTHEA retains its existing header-only collapsed presentation and rendering lifecycle. Library, DJ mode, new DSP, window magnetism, adjustable UI scale, and expanded-panel redesign are outside this scope.

### Reference precedence

- The collapsed reference governs compact composition, control order, proportions, branding placement, and material treatment.
- **User-confirmed screenshot correction:** the minimize buttons drawn on compact EQ and Playlist are mockup errors. Follow `ampX_UI_v1.1.png`: these modules have only Expand/Collapse and Close, in both docked and detached presentations. Only Player has a minimize button.
- **User-confirmed visualizer behavior, 2026-09-19:** the compact Player shares the expanded Player's selected visualizer style and palette. The mockup governs the display well's placement and proportions; its pictured green/yellow spectrum is not a fixed compact-only style. This is the user's latest answer and supersedes their earlier fixed-spectrum choice.
- **User-confirmed compact slider appearance, 2026-09-19:** compact EQ follows the mockup's warm volume color and segmented green balance, with fill ending at each thumb. Expanded Player retains its existing full-length, value-colored tracks.
- The actual-player screenshot governs compatibility with the successful expanded appearance. Its variable Playlist height and live data are examples, not replacement default dimensions.
- This addendum governs compact behavior and the explicit extensions below. All other behavior comes from the original spec.
- Exclude white canvas, explanatory headings, generous example spacing, and baked-in shadows from the compact reference. macOS supplies the window shadow; docked modules have no individual window shadow.
- Use the original custom-control primitives and fonts. Raster reference imagery must not become an image stretched behind interactive controls.

### Explicit changes to the original contract

1. Player, EQ, and Playlist collapse into functional compact strips rather than retaining only their expanded headers.
2. Their collapsed heights come from per-module compact metrics rather than `headerHeight`.
3. Collapsed Player metering and time remain live when visible. Expanded content still suspends while collapsed.
4. Compact bars use the reference's left-aligned AmpX wordmark and separators rather than the expanded centered titles and long decorative rules. The original Player three-button and EQ/Playlist two-button contracts remain unchanged.
5. Expanded and compact Player presentations share one visualizer style/palette selection. Collapsing or expanding preserves that selection.
6. Compact Playlist retains the user's chosen expanded width in both hosts. This supersedes the main Revision 9 spec's statement that collapsing Playlist returns the host to the fixed-width composition.
7. Expanded and compact Player timers share one elapsed/remaining display mode. Clicking either timer toggles the mode; collapsing or expanding preserves the choice.

## Approach and boundaries

**Chosen approach:** introduce dedicated compact presentations inside the existing `AmpXModuleView`. The module owns its expanded header/content and compact presentation, showing only the applicable presentation. Hosts continue to own windows and module operations.

Enriching the existing header with all module controls would couple expanded title layout to compact functionality. Separate mini-player windows would duplicate ownership and complicate docking. Dedicated presentations retain the same module identity, host, and state while isolating geometry.

The initial design inspected the modern UI at `4f53706` in `.worktrees/ampx-ui`. The 2026-09-19 review also inspected the newer Metal mini visualizers, horizontally resizable Playlist, and removal of vertical stack gaps. Implementation must begin from the current modern UI or its merged successor; do not implement this spec in `ClassicShadeView` or rebuild the retired panel system. File names below refer to the modern implementation and must be rechecked against the implementation revision.

## Visual contract

### Size and measurement

Player and EQ remain **490 logical points** wide. Playlist retains its chosen width in both expanded and compact presentations, with a **490 pt minimum and no maximum**, in docked and detached hosts. Collapsing changes its height without resetting its width. The compact strip stretches its track-summary well; branding and grip stay left-aligned, duration and trailing controls stay right-aligned, and type size, control sizes, and strip height remain unchanged.

Playlist resizing remains available only while expanded. A compact Playlist has no resize handles or resize cursors, and its host's resize constraints prevent changing its width or height through window-edge dragging. Expansion restores its preferred viewport height under the existing screen-fit rule, at the retained width.

Vertically stacked modules touch **edge-to-edge, with no gap**, preserving the 2026-09-18 correction. The **6 pt gap** applies only between the left column and docked ENTHEA. ENTHEA sits at `leftWidth + 6` pt, where `leftWidth` is the widest visible docked left-column module; x = 496 pt applies only when that column is 490 pt wide. Collapse never scales the interface.

The compact image is 1415 × 1111 source pixels. Approximate outer-frame crops, expressed as `(x, y, width, height)` from the image's top-left, are:

- Player: `(28, 276, 1361, 84)`.
- Equalizer: `(28, 557, 1361, 84)`.
- Playlist: `(28, 832, 1361, 76)`.

These are **visual estimates**, excluding the outer shadow, not finalized pixel measurements. Normalize each crop by `490 / cropWidth` on both axes; do not assume this mockup has the actual-player screenshot's backing scale. This gives starting heights of approximately **30.25 pt for Player/EQ** and **27.5 pt for Playlist**. Preserve the apparent height difference during the first comparison; do not silently standardize the strips to one height.

Before freezing geometry, record precise outer edges, bevel thicknesses, separators, black wells, text ink boxes/baselines, glyphs, button faces, slider tracks, thumbs, and thumb-center endpoints. Store logical geometry in shared compact metrics, with the crop origin and conversion factor recorded alongside measurement evidence. Snap to the current backing grid without allowing accumulated rounding to change the 490 pt width.

At the 490 pt reference width, the image suggests these horizontal allocations as starting estimates:

- Player: branding/grip in the first 18%; shared spectrum/time well from about 18–56%; five transport buttons from about 58–83%; window controls from about 86–99%.
- EQ: branding/grip in the first 18%; volume from about 19–50%; a narrow separator; balance starts at about 54%. Keep Expand/Close right-aligned at their reference positions; extend the balance track into the space recovered by removing the erroneous minimize button, preserving the separator and clearance before Expand.
- Playlist: branding/grip in the first 17%; track/duration well starts at about 17%. Keep Expand/Close right-aligned at their reference positions; move List Options and its separator right into the recovered space and extend the summary well accordingly.

These proportions guide measurement, not final hit rectangles. Measure individual button widths and gaps. Keep interactive targets within their module, disjoint from adjacent targets and drag regions. Enlarging a hit target must not enlarge the artwork. Any width/height or composition departure needed for legibility requires a reference/result comparison and approval.

### Shared appearance

- Dark navy panel, layered steel-blue outer edges, bright top/left highlights, dark bottom/right bevels, recessed black wells, metallic slider thumbs, and yellow waveform grip glyph.
- Left-aligned AmpX branding with the compact reference's slanted wordmark treatment. Reuse the brand drawing where possible; obtain the slant through drawing, without adding an unrelated font. Measure the result rather than substituting the expanded centered title.
- Thin vertical metallic separators divide branding, instruments, and trailing chrome. Do not carry over the expanded header's long paired yellow rules.
- Text uses the existing Roboto Mono family and fallback; timer uses existing custom segment drawing. Compact Playlist text follows the project's text system, with reference-matched size and spacing rather than introducing a bitmap font.
- Active play glyph and readouts are green; minimize and close glyphs are yellow/orange; inactive transport glyphs are pale. Maintain raised faces and recessed pressed states.
- Every control supports hover, pressed, disabled, keyboard focus, and appropriate active state, using the existing skin. No SF Symbols or standard native control chrome.

## Compact module composition

### Player

Left to right: waveform grip, AmpX wordmark, separator, black spectrum/time well, separator, **Previous / Play / Pause / Stop / Next**, separator, **Minimize / Expand / Close**.

Use the same transport actions and enablement as the expanded Player. These are real controls, not decorative copies. Omit track metadata, seek, volume, balance, EQ/PL toggles, eject, shuffle, repeat, and options from this compact presentation; existing menu/keyboard access remains available.

The well contains one compact visualizer on the left and the playback timer on the right. Reuse the existing mini-visualizer renderer, prepared audio data, styles, and palettes. All eight current styles remain available at the compact drawable size; adapt their geometry and density without distorting the timer or starting a second audio analysis pipeline. Do not copy the expanded well's surrounding labels or introduce a second display well. Stereo Bars retains its two-channel meaning inside the compact visualizer rectangle.

**Selection and interaction:** use one shared style/palette selection for both Player presentations, with the existing stable preference identifiers. A selection made in either presentation is reflected when the other becomes visible. Single-click cycles styles; the context menu selects style and palette; double-click keeps the existing ENTHEA toggle behavior and restores the style active before the first click. These interactions belong to the visualizer rectangle, not the adjacent timer or the whole well. Expose the same selection actions through accessibility.

Keep visualizer selection ownership outside the expanded-only content view. Retain the existing Metal failure fallback and playback/discontinuity handling. The compact renderer's lifecycle follows `compactVisible` below; the mini-visualizer spec's rule that collapsed expanded content stops rendering must not suppress the visible compact presentation.

**Timer interaction:** clicking the compact timer toggles elapsed/remaining time, just like the expanded timer. Both presentations read and update one shared display-mode value owned by the Player binding layer. Preserve the selected mode across collapse/expand; do not create independent per-view toggles or reset it when changing presentations. Keep the existing timer's initial default and lifetime behavior. Timer clicks do not cycle visualizer styles or begin window dragging.

Time uses a minimum two-digit minute field, matching `01:51`, with a leading minus sign in remaining mode. It reads the same playback clock and track duration as the expanded timer. Reserve geometry for long elapsed and remaining times; use an hours format for hour-long playback and fit it through a defined smaller digit style, never by stretching glyphs or overlapping the visualizer. Include `00:00`, `59:59`, `1:00:00`, `100:00:00`, and their remaining-time equivalents with a minus sign in geometry verification. Empty playback displays `00:00` and the selected visualizer's empty state without clearing the selected timer mode; unavailable duration must not produce a fabricated countdown. Paused/stopped behavior follows the existing clock and mini-visualizer semantics.

### Equalizer

Left to right: waveform grip, AmpX wordmark, separator, **master volume**, separator, **balance**, separator, **Expand / Close**.

The user confirmed that orange controls master volume and green controls balance, and that compact artwork follows the mockup's colors and fill up to the thumb. These are alternate access points to the expanded Player's controls; neither modifies preamp, EQ bands, EQ enabled, or AUTO state. Compact and expanded sliders share values and interactions, while retaining their respective drawing treatments.

- Orange volume: continuous warm-colored fill up to the metallic thumb in a recessed horizontal track, with the remainder unlit. Bind normalized 0…1 to the existing `setVolume`; accessible value is 0…100%. Preserve the mockup's warm color treatment as volume changes; do not apply the expanded Player's green/yellow/red value-color ramp.
- Green balance: segmented green fill up to the metallic thumb, with the remainder unlit. Bind normalized 0…1 to existing balance −1…+1; center is 0. Left-to-thumb fill follows the mockup, so centered balance fills half the track. The segments indicate position, not audio level, and remain green at all balance values.
- Use the same click-to-position, dragging, keyboard increments, and model clamping as the existing sliders. Thumb-center endpoints must keep the full thumb inside its allowed track region.
- Tooltips and accessibility labels identify Volume and Balance without adding visible labels to the reference. Balance announces left/center/right position rather than an unexplained normalized number.
- Changes through either presentation, menus, or media-related controls update the other presentation through existing model observation. Showing or hiding this strip never changes playback settings.

EQ ON/AUTO, presets, curve, preamp, and bands remain in the expanded presentation. Collapsing does not bypass or disable equalization.

### Playlist

Left to right: waveform grip, AmpX wordmark, separator, black **track summary and duration** well, yellow three-line **List Options** button, separator, **Expand / Close**.

Show the loaded playback track, independently of selection: `index. Artist - Title`, with that track's total duration right-aligned. The reference fixture is `7. SLEAZE - GOD DAMN` and `3:46`. This is track duration, not elapsed time, remaining time, or total playlist duration.

Use the existing metadata fallback rules. Obtain the index from the current playlist order and omit it when the loaded track is no longer in the playlist. With no loaded track, show `NO TRACK` and `--:--`; an unknown duration also uses `--:--`. Pause and stop retain the loaded-track summary while that track remains loaded.

Reserve a separate duration area whose width accommodates the formatted value. Clip long track text to its own rectangle; no wrapping, collision, or new marquee animation. Preserve title casing from metadata; the uppercase fixture is not an uppercase transformation rule.

The three-line button opens the existing **LIST OPTS** menu, anchored to the button, with the same commands and validation. It is not a reorder grip or an expand action. Track summary is read-only; expanding uses the square button or module command. The expanded selection, scroll position, preferred viewport, and chosen width survive collapse. Extra width extends the summary well without scaling its text or controls.

## Chrome, dragging, and windows

Player displays trailing **— / square / ×** controls. EQ and Playlist display only **square / ×**, matching the actual UI screenshot and the original spec. Do not reserve a blank button slot for the erroneous minimize control.

- **Minimize (Player only):** miniaturizes the stack NSWindow. Tooltip/accessibility label is `Minimize AmpX window`. This action does not alter `collapsed` or `closed`. EQ and Playlist expose no minimize button or associated button hit target/accessibility element, including when detached.
- **Expand:** clears that module's existing collapsed state and restores its expanded layout. The square is not fullscreen or maximize. Use the existing collapse keyboard command (`⌘⌥C`) to toggle either direction.
- **Close:** Player closes/hides the stack without quitting; EQ/Playlist close only that module. Existing reopening and detached-state restoration apply.

The left waveform remains the grip for reordering and tearing off eligible modules. Player can reorder within the left column and cannot detach. Noninteractive branding, separators, and panel background move the containing window. Wells, controls, and control hit areas must not initiate window or module dragging. Existing tear-off distance, insertion marker, screen-coordinate conversions, and re-docking rules continue to apply.

Keep the host's top-left anchor stable during collapse/expand; recompute all affected module frames and host height in the same update. Lower left-column modules move together. The right-column visualizer remains top-aligned, and host height is the larger column height. A compact left column beside expanded ENTHEA therefore does not force the host down to the left-column height.

Use the same compact heights in stack and detached hosts. A collapsed Playlist keeps its chosen width and cannot resize either dimension. Preserve its preferred expanded viewport and reapply existing short-screen fitting on expansion. A wide compact Playlist still determines the docked left-column width and ENTHEA's horizontal placement. Closing or detaching it removes its contribution to stack width and height; closed views must remain hidden after relayout.

**User update, 2026-09-19:** double-clicking a module's title, brand/grip, or empty title-bar background toggles between compact and normal size in docked and detached hosts. Compact controls and readouts retain their own interactions; double-clicking them does not toggle module size. Single-click grip dragging remains available. Cancel an active drag when changing presentation, without changing order or partially applying a module operation.

## State, rendering, and lifecycle

Retain `AmpXModuleOrder.collapsed` as the source of truth. Add no duplicate mini-mode boolean, playback model, audio engine, EQ state, or persistent compact slider values. Existing layout JSON remains compatible; restored collapsed IDs now select compact presentations. Recompute compact frame heights from metrics instead of trusting saved expanded frame heights.

Separate host visibility from presentation visibility:

```text
hostVisible = !closed && windowVisible && !miniaturized
    && !occluded && intersectsViewport
expandedVisible = hostVisible && !collapsed
compactVisible = hostVisible && collapsed && hasCompactPresentation
```

The coordinator supplies both presentation states. Do not globally remove the collapsed gate from the existing content visibility calculation: that would resume hidden EQ animation, Player displays, Playlist clocks, and ENTHEA rendering.

- Expanded continuous views run only under `expandedVisible`.
- Compact Player time/visualizer run only under `compactVisible`, using the existing playback clock and mini-visualizer frame source. Collapse switches active drawing paths; it does not freeze the visible compact timer. Only the visible visualizer presentation submits frames, with one frame driver for its rendering path; do not leave an autonomous Metal loop running beside it.
- Preserve the mini-visualizer pause/settle/park behavior and stop/seek/track-change resets. Shared style/palette selection survives presentation changes; hidden renderers do not keep advancing history or particles. Rendering suspension must not stop audio analysis still needed by another visible consumer.
- Compact EQ and Playlist use discrete model updates; no independent continuous redraw timer is needed for slider positions or total duration.
- Hide/minimize/occlusion stops all continuous work in the affected host. Detached visible modules continue independently.
- Collapse retains expanded views, controls, and transient UI state. Detach/re-dock reparents the same module container and does not duplicate subscriptions.
- ENTHEA remains header-only when collapsed, with content rendering and bridges suspended. Its close/teardown and theater behavior are unchanged.
- Set up model observation once per owning presentation/binding layer and tear it down with ownership. Repeated collapse/expand must not accumulate observers or display links. Invalidate only affected drawing regions.

## Implementation integration points

- `Components/AmpXModuleView.swift`: explicitly select expanded or compact presentation, draw the correct frame, lay out in full-module coordinates, and keep hidden presentation controls out of focus traversal.
- Shared compact chrome: owns frame, branding, separators, grip, and trailing buttons; emits module/window intents to the coordinator. Avoid three copies of window behavior.
- `Modules/Player`, `Modules/Equalizer`, `Modules/Playlist`: compact bodies reuse existing transport actions, slider bindings, metadata formatting, menus, clock, and mini-visualizer rendering. They do not access neighboring views. Player visualizer style/palette selection and elapsed/remaining timer mode are owned by a binding layer shared by its two presentations, rather than the expanded view alone.
- `Theme/AmpXMetrics.swift` and skin drawing helpers: per-module compact heights and measured compact geometry. Do not modify expanded metrics to make compact artwork fit.
- `Modules/AmpXLayout.swift`: calculate collapsed height by module ID, retaining header height for ENTHEA. Stack and detached sizing consume the same source.
- `Windows/AmpXHostCoordinator.swift` and `Modules/AmpXEffectiveVisibility.swift`: route both presentation visibility states, minimize intents, and existing module actions.
- Stack/detached controllers: retain fixed Player/EQ dimensions, anchor preservation, Playlist width across both presentations, expanded viewport restoration, and correct visibility after transfer. Compact Playlist disables resizing without discarding its preferred width.

Names and file splits may be refined in the implementation plan; these ownership boundaries and behavioral requirements are binding.

## Keyboard and accessibility

Collapsed controls participate in the existing focused-control-first key routing. Return/Enter activates focused buttons; Space remains global play/pause, preserving the user decision recorded in the main UI spec. Arrows adjust focused sliders without also seeking or changing playback globally. Preserve the existing text-entry exceptions. Hidden expanded Playlist rows must not consume navigation/deletion keys while collapsed. List Options must open and operate with the keyboard.

On collapse, remember the expanded responder and move focus to the compact presentation's expand control when focus was inside the collapsing module. On expansion, restore the remembered valid responder, otherwise the normal module header. Do not steal focus from another module. Rebuild traversal from visible controls after presentation changes and preserve it across detach/re-dock.

Expose each compact strip as its actual module (`Player`, `Equalizer`, `Playlist`) even though all display AmpX branding. Give every button and slider a meaningful role, label, value, and action. Expose the timer's current mode and elapsed/remaining toggle through keyboard and accessibility actions. Expose Playlist summary as static text. Announce collapse/expand and value changes through existing accessibility conventions, without announcing playback time every frame.

## Acceptance and verification

### Visual gates

1. Measure and render compact Player first using the production drawing path and deterministic visualizer/time (`01:51`). Record the chosen style/palette; inject capture settings without changing the user's saved selection. Compare the well geometry with the compact mockup and effect appearance with the current mini-visualizer contract, respecting the confirmed selectable-visualizer difference. Capture at 2× backing scale, normal width 490 pt. Normalize the source crop to matching output bounds with a recorded transform; retain an aspect-ratio-preserving comparison so resizing cannot conceal a height mismatch.
2. Compare reference/result side by side and with an overlay. Correct border layers, brand placement/slant, well geometry, timer proportions, spectrum, glyphs, individual control widths, and spacing. Obtain approval of the concrete Player capture before extending the treatment to compact EQ/Playlist.
3. Repeat for EQ with deterministic volume/balance positions matching the reference and Playlist with the specified track fixture. Repeat after controls and live models are wired.
4. Capture each compact module, all three compact in a stack, mixed expanded/compact states, reordered states, detached EQ/Playlist, and a compact stack beside expanded ENTHEA. Capture the original expanded panels with deterministic content to detect regressions; keep Playlist viewport sizes equal for comparisons.
5. Check 1×/2×/3× rasterization at the same logical width; identify offscreen raster checks separately from physical-display screenshots. Use `./scripts/shoot.sh` for rendered app evidence and document any deterministic capture support added.

Record build revision, crop measurements, logical dimensions, backing scale, reference/result images, unresolved differences, and approvals. Screenshot generation or passing tests alone cannot establish fidelity. Overlaps, clipped controls, flat substitutes for bevels, incorrectly scaled artwork, and stretched digits fail the visual gate.

### Behavior and regression evidence

- Layout tests cover each collapsed height, all eight Player/EQ/Playlist collapse combinations, zero vertical gaps, the horizontal ENTHEA gap, closed/detached exclusions, and restoration of preferred expanded Playlist size. In both hosts, a previously widened Playlist retains its width through collapse/expand and relaunch, stretches only the compact summary well, and cannot resize while compact. A wide docked compact Playlist keeps ENTHEA clear of its right edge.
- Visibility tests independently cover collapse, close, window hide, miniaturize, occlusion, and host transfer: visible compact Player updates while expanded content and collapsed ENTHEA remain suspended; hidden hosts run neither presentation.
- Interaction checks cover all five transports, volume/balance synchronization both ways, slider endpoints/center, List Options routing, module-specific close, and Player's stack-window minimize. Verify compact volume/balance retain their confirmed colors and fill-to-thumb appearance at minimum, center, and maximum, while expanded tracks retain their existing value-color behavior. Verify EQ/Playlist have exactly two trailing chrome buttons in both host types, with no hidden minimize hit target or accessibility element.
- Summary/time checks cover no loaded track, unknown duration, long text, long elapsed/remaining times including the minus sign, playlist reordering, removal of the loaded track from the list, selection differing from playback, and pause/stop. Toggle the timer in each presentation and verify that the other inherits the choice across repeated collapse/expand. Confirm that timer clicks do not change visualizer selection or initiate dragging.
- State checks cover repeated collapse/expand, reordering, detach/re-dock, close/reopen, relaunch with collapsed modules, and absence of duplicated subscriptions/display links.
- Visualizer checks cover all eight styles at compact size, palette changes, selection synchronization in both directions, click/double-click/context-menu behavior, pause/park/wake, discontinuities, and Metal fallback. Expanded rendering stops while compact rendering is active, and changing presentations never overwrites the shared saved selection.
- Keyboard and VoiceOver checks cover every visible control, module actions, focus restoration, hidden-content exclusion, and current control values.
- Build and run `./scripts/run-tests.sh` in the implementation checkout, preserving existing audio/playlist/ENTHEA suites. Run formatting/lint wrappers before committing if installed. Do not use `swift test`; the package has no test target.

## Review decisions

Volume and balance semantics and the two-button EQ/Playlist chrome are confirmed. The extra EQ/Playlist minimize buttons in the compact mockup are explicitly rejected as screenshot errors. The draft proposes the Playlist icon opening existing List Options, measured per-module compact heights, and using the recovered button space for the adjacent controls as described above. These choices are explicit so they can be reviewed before implementation. Further visual deviations require concrete comparison evidence and approval under the original spec's visual contract.

**2026-09-19 confirmed:** compact Player shares the expanded Player's selected visualizer style and palette. Its geometry follows the compact reference; its selectable effect appearance follows the current mini-visualizer design.

**2026-09-19 confirmed:** a widened Playlist keeps its wider width while shrunk, in both hosts. Its compact controls do not scale, and resizing remains an expanded-only action. This replaces the main UI spec's earlier collapse-to-fixed-width statement.

**2026-09-19 confirmed:** compact volume and balance follow the mockup's colors and fill up to the thumb. This is an intentional compact drawing treatment; expanded Player's full-length, value-colored tracks remain unchanged.

**2026-09-19 confirmed:** clicking the compact timer toggles elapsed/remaining time and shares the choice with the expanded timer. Both presentations use one display-mode value, preserved across collapse/expand.

### Review evidence and reference availability

The restored `screenshots/shrinked_modules.png` is present at 1415 × 1111 pixels. Its artwork includes the already-rejected EQ/Playlist minimize buttons; do not restore those controls when measuring it. `screenshots/ampX_UI_v1.1.png` remains absent from this checkout. The `screenshots/` directory is ignored by Git, so local restoration alone does not preserve the compact reference for other checkouts. Retain an accessible copy of the approved reference and record current expanded baseline captures before implementation visual checks.

# AmpX UI Design — Review

**Date:** 2026-09-11\
**Verdict:** Revision 4 is ready for implementation planning. No remaining blocking findings in this review; retain the visibility clarification below when translating the spec into code. Earlier findings are retained as review history.\
**Method:** Superpowers spec-review checks for consistency, ambiguity, scope, and compatibility with the current source.

## Reviewed material

- [UI design spec](./2026-09-11-ampx-ui-design.md)
- [AmpX UI.pdf](./AmpX%20UI.pdf), all 31 pages
- [AmpX.png](../../../screenshots/AmpX.png), visual reference
- Current application, playlist interaction, and ENTHEA host code

The PDF and image clarify the intended appearance and support the AppKit/Core Graphics direction. They do not resolve the lifecycle, scaling, and cutover gaps. PDF code examples should be treated as illustrative guidance, not production-ready contracts.

## Implementation findings

### 1. Scaling conflicts with variable module heights

**Priority: P1 — resolve before implementation.**\
**Spec:** §3 Hosting; Error handling & edge cases.

Both hosts use `scale = min(w/499, h/788)`. A detached 499 × 225-point EQ window therefore clamps to 0.85 instead of retaining scale 1.0. Collapsing or closing modules also changes the height ratio and can unexpectedly change zoom. This conflicts with the requirement that the stack shrink to its remaining modules. The playlist is described as resizable, but its independent resizing behavior is not defined.

The PDF's page 25 formula describes a fixed three-module composition. It does not establish the correct behavior for detached windows or changing stack contents.

**Recommended resolution:** Separate visual scale from content height. Define how width controls scale, how module heights determine host height, and how playlist resizing changes its viewport. Specify minimum window dimensions and behavior when the full stack exceeds the available screen height. Cover detached, collapsed, Player-only, and ENTHEA-expanded layouts in tests.

### 2. Cutover deletes playlist helpers required by retained tests

**Priority: P1 — resolve before implementation.**\
**Spec:** Files expected to change; §5 Playlist; Testing.

Deleting `Sources/Views/Classic/*` also deletes `PlaylistListInteractions.swift`. That file contains `PlaylistChromeActions`, which the retained `PlaylistChromeActionsTests` directly references. Following the deletion list literally breaks the promised unchanged playlist regression suite.

The same file contains `PlaylistKeyboardNavigation`, whose adapter uses SwiftUI `Binding` values. Reusing the selection model and keyboard routing protocol does not automatically preserve that adapter's behavior in AppKit.

**Recommended resolution:** Move the reusable playlist actions out of Classic before cutover. Explicitly scope an AppKit keyboard adapter that preserves selection, navigation, playback, removal, cropping, and reorder behavior. Retain the existing action tests.

### 3. ENTHEA needs an explicit visibility and teardown contract

**Priority: P1 — resolve before implementation.**\
**Spec:** §4 State wiring; §5 ENTHEA; Error handling & edge cases.

Invalidating the new UI display links does not stop ENTHEA's existing push timer or WebView rendering. `EntheaWKHostView` uses window occlusion and explicit bridge activation to control work. Collapsing a module inside a visible stack does not necessarily change window occlusion.

The current host also documents that releasing the WebView is necessary to stop its WebContent process; blanking the page alone is insufficient.

**Recommended resolution:** Define host lifecycle calls for collapse, expansion, close, detach, and re-dock. Deactivate the bridge and rendering on collapse; invoke teardown and release the host on close; restore activation when shown. Specify ownership during reparenting and verify that hidden content stops work even while the stack window remains visible.

### 4. Accessibility specifies metadata but not operations

**Priority: P2 — complete the interaction contract.**\
**Spec:** §7 Accessibility; Success criteria.

Roles, labels, values, and notifications do not specify how assistive technology activates buttons, adjusts sliders, selects rows, or performs module operations. Keyboard traversal alone also does not define keyboard equivalents for grip-based reorder and tear-off gestures.

**Recommended resolution:** Specify accessible actions, slider ranges and adjustment behavior, focus handling, row selection, and keyboard alternatives for module operations. Add keyboard-only and VoiceOver acceptance checks, including focus preservation after collapse or reparenting.

## Findings from the visual references

### 5. Image canvas dimensions are not module bounds

**Spec:** Theme layer / Metrics; the 788-point composition invariant.

The reference image includes outer background, especially below the playlist. Its full 998 × 1576-pixel canvas does not establish that the panel frames, gaps, and symmetric outer margins should fill exactly 499 × 788 logical points.

**Recommended resolution:** Measure actual panel bounds separately from the image canvas. Record panel heights, gaps, and intended app margins explicitly before finalizing the invariant. Keep 499 × 788 as a reference-canvas size unless the surrounding background is deliberately part of the shipped window. Exact panel measurements remain to be performed.

### 6. Seven-segment time digits conflict with the font requirement

**Spec:** UI font decision; §5 Player; Success criterion 10.

The reference timer uses seven-segment digits, while the spec requires Roboto Mono for all UI text. These produce materially different appearances.

**Recommended resolution:** Explicitly allow custom segment drawing for the timer, or document the Roboto Mono timer as an accepted deviation from the reference.

### 7. Spectrum color buckets do not describe the reference rendering

**Spec:** §5 Player; `AmpXSpectrumBarModel` tests.

The image shows segmented columns with green lower segments and yellow upper segments. The spec's level-based color buckets appear to select one color for an entire column, following the PDF's simplified example.

**Recommended resolution:** If the image is authoritative, specify segment height, segment gap, and vertical color bands separately from the signal level that determines how many segments are lit. Update the pure model tests accordingly.

### 8. Accepted visual deviations need to be explicit

**Spec:** Capability matrix; §5 Playlist; visual-fidelity success criteria.

The reference shows three header buttons on Player and a gold playlist scrollbar thumb. The spec deliberately omits Player's detach/close buttons and specifies a steel-blue thumb. These may be valid product decisions, but they make literal visual matching an ambiguous acceptance criterion.

**Recommended resolution:** Add an accepted-deviations list. Preserve the Player anchor policy if intentional, and explicitly choose which scrollbar treatment to implement.

## Additional clarifications

- Define how closed modules reopen, where they reappear in the order, and whether reopening restores their detached state.
- Fix the windowing-document links in the spec: from `docs/superpowers/specs/`, use `../../WINDOWING_REVIEW.md` and `../../DOCKING_MAGNETISM_OPTIONS.md`.
- Link the actual PDF and PNG directly from the spec so future implementation and visual review use the same references.

## Recommended source precedence

1. **PNG:** appearance and measured geometry, excluding incidental canvas background unless explicitly retained.
2. **Design spec:** behavior, architecture, and explicitly documented visual deviations.
3. **PDF:** rationale and illustrative implementation guidance where it does not conflict with the first two.

## Review limits

This was a source and document review. No application code was changed and no build or tests were run. The PDF text was read and the PNG was visually inspected; exact pixel-boundary measurements and rendered application comparisons remain future validation work.

## Revision 2 review

**Reviewed:** The rewritten spec marked “Revised after review — awaiting user approval,” on 2026-09-11.

The rewrite addresses the original fixed-height zoom calculation, playlist helper extraction, timer exception, spectrum segmentation, reference precedence, and documented visual deviations. It adds substantive ENTHEA lifecycle and accessibility contracts. The claim that all findings are resolved is premature because the following integration and behavior gaps remain.

### R2-1. The unchanged hotkey router depends on the deleted panel manager

**Priority: P1. Spec: §4 State wiring, currently line 226.**

`Sources/Utilities/AmpXHotkeys.swift` directly calls `AmpXPanelWindowManager.shared` to identify playlist and visualizer windows and route visualizer theater commands. The spec deletes that manager while explicitly requiring the hotkey router to remain unchanged. This fails to compile at cutover.

Window identity also cannot distinguish playlist focus from EQ or Player focus inside the new shared stack. The current global routing consumes Space and arrow keys, which can interfere with keyboard operation of the new custom buttons and sliders.

**Required resolution:** Add hotkey routing to the migration scope. Replace panel-window identification with focused-module/control context, define precedence between focused controls and global playback shortcuts, and route or explicitly retire theater commands. Verify playlist navigation, slider adjustment, and button activation in both hosts.

### R2-2. Screen-height clamping leaves overflow content inaccessible

**Priority: P2. Spec: §3 sizing table, currently line 211.**

After the playlist reaches its three-row minimum, the spec clamps the window to the visible screen without reducing the remaining content height or providing scrolling. For example, at scale 1.35 the Player, EQ, and ENTHEA alone total approximately 998 points before gaps or any Playlist content. A shorter visible frame therefore clips content. Expecting the user to collapse or detach modules does not define how to reach the clipped controls or complete a drop into that region.

**Required resolution:** Choose an explicit overflow policy: a reachable stack viewport, deterministic automatic collapse/detach, or a constraint that prevents expansion beyond the available space. Test all four modules on a short screen at maximum scale, including access to the final module and reorder targets.

### R2-3. Player window close and windowshade semantics remain ambiguous

**Priority: P2. Spec: §2 capability matrix and header semantics, currently lines 156–165; edge-case table, line 316.**

The spec says the stack window always exists, gives Player a window-close action, and later says Player has no close capability. These can be reconciled by distinguishing module membership from window visibility, but that distinction is not specified. Closing the main window while detached modules remain also needs defined recovery and lifecycle behavior.

Likewise, “collapse to header height (windowshade)” could mean collapsing only Player or shading the entire window, whereas the stack layout describes per-module collapse.

**Required resolution:** Keep Player out of the module `closed` set and define its close action separately. Specify playback behavior, detached-window behavior, main-window reopening through the Dock/menu, and ENTHEA handling on window close. State explicitly whether Player collapse affects only Player content or the whole stack.

### R2-4. Re-docking independently scaled hosts needs a scale policy

**Priority: P2. Spec: §3 sizing rules, currently lines 198–208; Success criterion 4.**

Both detached windows and the stack can be resized independently, so they can have different scales. A detached module at scale 1.35 cannot join a stack at scale 0.85 while retaining its zoom and also satisfying the rule that every module in the stack scales together. The current success criterion broadly says detaching never changes zoom, but the transfer rules do not define the destination scale or resize behavior.

**Required resolution:** State that tear-off initially inherits the source scale and that re-dock adopts the destination stack scale, documenting the exception to zoom preservation; alternatively make scale shared across all hosts. Test transfer between differently sized hosts.

### Minor consistency fixes

- The early `hostHeight` equation omits scaling the gap; the later equation includes it. Keep one authoritative formula.
- Preparation moves are variously assigned to Phase 0 and Phase 1. Use Phase 0 consistently.
- `Sources/Playlist/` is forbidden from changing in Non-goals but explicitly receives the extracted helper later. Add the stated exception there too.

**Validation:** Read the rewritten spec and inspected the current hotkey router and menu catalog. No application changes, build, or test execution were performed. This review records the rewritten spec's measurements without independently certifying their exact pixel boundaries.

## Revision 3 review

**Reviewed:** Spec marked “Revision 3 — awaiting user approval,” on 2026-09-11.

All four revision-2 findings are addressed at the design level:

- **R2-1:** `AmpXKeyRouter` replaces window-identity routing with explicit control/module/global precedence and is included in migration and tests.
- **R2-2:** Overflow now shrinks the playlist before introducing a scrollable stack viewport with drag auto-scroll.
- **R2-3:** Player module membership is distinct from window visibility; closing, reopening, playback, detached windows, and per-module collapse are specified.
- **R2-4:** Tear-off inherits source scale; re-dock adopts destination scale, with the zoom exception documented.

Two focused gaps remain in the newly specified paths.

### R3-1. Theater needs an explicit exception to normal content sizing

**Priority: P2. Spec: §4 Key routing, currently line 275; §3 Hosting, scaling and sizing.**

Theater enters a detached window sized to `screen.frame`, but the normal detached-host rules still cap scale at 1.35 and set height to the scaled module height. Under those rules ENTHEA remains roughly 662 × 392 points inside a full-screen window, or the sizing controller shrinks the window back to module height. Neither provides the specified full-display visualization.

The existing Classic visualizer explicitly hides chrome and removes content insets in theater mode. The revised spec does not yet state the equivalent exception for the new host.

**Required resolution:** Define theater as a distinct presentation mode: bypass ordinary module dimensions and scale limits for the visualization surface, fill the display, and specify chrome visibility. On exit, restore the previous host, scale/frame, and application presentation options. Add a test for content filling theater bounds and restoring normal sizing afterward.

### R3-2. Viewport clipping is missing from the rendering lifecycle

**Priority: P2. Spec: §3 Overflow; §4 State wiring and ENTHEA lifecycle, currently lines 253 and 287–293.**

The new stack viewport can scroll an expanded Player or ENTHEA module completely out of view while the stack window remains visible. The documented lifecycle triggers—collapse, close, window hide/miniaturize, and window occlusion—do not cover this case. Consequently the display links and ENTHEA bridge/rendering can continue while their module is fully clipped, contrary to the off-screen-work guarantee in the edge-case table.

**Required resolution:** Include intersection with the stack viewport in effective module visibility. Suspend display links and ENTHEA work when fully clipped, resume when visible again, and combine this with collapsed/window visibility so scrolling cannot reactivate a hidden module. Test scrolling ENTHEA completely out of and back into a visible stack window.

### Minor cleanup

The edge-case table retains an older “Stack taller than the screen” row that only mentions frame clamping. Replace it with a reference to the authoritative two-stage overflow policy, or remove the duplicate.

**Validation:** Read revision 3 and checked existing theater behavior in `ClassicVisualizerPanelView.swift` and `AmpXPanelWindowManager.swift`. No application code changed and no build or tests were run. The original visual decisions were not reopened in this review.

## Revision 4 review

**Reviewed:** Spec marked “Revision 4 — awaiting user approval,” on 2026-09-11.

**Verdict: Ready for implementation planning.** Both revision-3 findings are addressed at the design level:

- **R3-1 resolved:** Theater explicitly bypasses ordinary scale and height rules, fills the display without chrome, retains the mounted ENTHEA body, and restores the prior host, scale, frame, and application presentation options. The test requirements cover these transitions.
- **R3-2 resolved:** Effective visibility combines module state, window state, occlusion, and viewport intersection. Visibility transitions govern display links and ENTHEA bridge activity, with tests for scrolling out of and back into view and for independent visibility gates.
- The stale overflow-table row has been removed; the two-stage policy is authoritative.

### Non-blocking implementation clarification

The phrase “a module in theater is trivially visible” should mean **only that it passes the viewport-intersection gate**. Detached and theater hosts have no stack viewport; they should treat that gate as true while retaining all applicable module/window visibility and occlusion checks. Likewise, “bridges stay active throughout” theater reparenting applies while effectively visible, not as an override of those checks. This follows the spec's stronger rule that visibility terms combine and never override one another. Make this explicit in the implementation plan and include hidden/occluded theater and detached-host cases in visibility tests.

**Validation:** Reviewed the revised sizing, theater, visibility, lifecycle, edge-case, testing, and success-criteria sections. This is design-review approval for planning, not runtime verification or user approval to implement. No application code changed and no build or tests were run.

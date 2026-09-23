# Compact module validation

Player checkpoint status: **approved by the user on 2026-09-19**, including the shared bevel treatment. All three compact modules are implemented and verified. EQ/Playlist final captures are available for review; no additional user visual sign-off is implied.

Reference: `screenshots/shrinked_modules.png`, SHA-256 `d792a98ad96ae4d0792251256a644081c1f3fa08b4a5970e7d796e4f78781aed`.
Source rectangles, colors, normalization, and uncertainty are recorded in [measurements](reference/measurements.json).
Player/EQ source crops are 1361 × 84 px; Playlist is 1361 × 76 px.
Uniform normalization to 490 pt yields heights 30.24246877 / 30.24246877 / 27.36223365 pt.

## Deterministic Player

[Comparison and overlay](player/player-comparison.png), [native 1×](player/compact-player-1x.png), [2×](player/compact-player-2x.png), [3×](player/compact-player-3x.png).

These captures combine actual AppKit chrome/digits with the production Metal offscreen renderer at the visualizer's measured rectangle. BGRA texture data is composed through a color-managed Core Graphics context, with top-origin texture scanlines mapped into bottom-origin drawing coordinates. Capture choices never write user defaults. A regression test verifies actual green signal pixels in the resulting PNG, in addition to deterministic bytes.

The selected comparison style is **dotSpectrum / classic**. Its 32 columns, dark grid, and palette gradient differ from the old mockup as allowed by the confirmed choice to share the expanded Player's settings. The frozen signal is not the mockup's audio data. The app uses the existing skin's bevel material, whose edge bands are heavier than the source at this small size. Brand and timer are vector/font drawing, not extracted bitmaps.

The geometry, transport faces, separate control hit cells, branding placement, timer spacing, and square Expand glyph were inspected against the overlay. The user approved the running-host Player and shared treatment on 2026-09-19.

## Running Player checkpoint

[Live compact Player](player/player-live-host.png) was captured by window ID with `./scripts/shoot.sh --capture-only --output-prefix /tmp/ampx_compact_player`. It is 980 × 60 pixels at 2×: shared boundaries round the 30.24246877 pt logical height to 30 pt on this host. It uses the user's original **Waterfall / Amber** selection and a live `00:04` clock. This is separate from the frozen dotSpectrum/classic comparison.

[Expanded baseline](player/expanded-live-baseline.png) was captured after launching this worktree's build before collapsing Player. The old expanded source mockup remains unavailable.

Build environment: Debug, arm64, macOS 26.6.2, based on `98c15a1` with the host-integration changes in the commit containing this note. Exact command output and red/green runs are recorded in this plan's local execution ledger.

Verified in the app: collapse/expand, shared timer toggle, compact style change reflected in expanded Player, Stop/Play invocation, accessible chrome and transport controls, minimize, and restoration through Window → AmpX. Restored Waterfall/Amber and elapsed mode after inspecting temporary style/timer changes. The actual-window regression waits for AppKit's minimize/deminiaturize notifications before checking state.

**Review decision:** approved on 2026-09-19. The existing skin bevel is heavier than the source; the shared production visualizer intentionally differs from the pictured legacy spectrum.

## Compact Equalizer

[Comparison and overlay](equalizer/equalizer-comparison.png), [native 1×](equalizer/compact-equalizer-1x.png), [2×](equalizer/compact-equalizer-2x.png), [3×](equalizer/compact-equalizer-3x.png).

Uses the approved shared shell. Volume has an orange/yellow fill; balance has green segments, both clipped to the thumb. The source's erroneous minimize slot is removed and the balance track extends into that space. Both comparison values are 70%; the longer corrected balance track consequently puts its thumb farther right. Source and corrected geometry are separately recorded in the measurements.

Focused EQ, slider, accessibility, layout, interaction, and reference checks passed except for a detached-height regression caught in the same run. Detach placement reapplied a fractional frame after content sizing, making the native window one pixel too tall. Placement now retains the snapped compact view size. The final affected EQ/interaction run passed **19 tests**. Live docked/detached evidence is consolidated with the final three-module pass.

## Verification so far

- Baseline: 676 tests passed before Player behavior changed.
- Shared state/actions: 34 focused state, binding, settings-wiring, and expanded-reference tests passed.
- Compact display: 49 focused tests passed, including every style/palette at 1×/2×/3×.
- Compact shell: 28 focused tests passed; wordmark adjustment subsequently passed the deterministic capture test.
- Existing expanded reference tests remain green.
- Host integration full suite: **700 tests passed**.
- Final accessibility, compact controls, cancellation, host/visibility/keyboard, and reference checks: **34 tests passed**.
- Additional actual-window minimize/close/reopen regression: **1 test passed**, using animation-completion notifications.

## Compact Playlist

[Comparison and overlay](playlist/playlist-comparison.png), [native 1×](playlist/compact-playlist-1x.png), [2×](playlist/compact-playlist-2x.png), [3×](playlist/compact-playlist-3x.png), [800 pt](playlist/compact-playlist-wide-2x.png), [long Unicode title and duration](playlist/compact-playlist-long-2x.png).

Uses the approved shell, with fixed-size branding/chrome and a stretching summary well. List Options shifts right into the removed minimize slot; the title preserves original casing and clips before a separately measured duration column. The readout uses the existing bundled font at 11 pt; its glyphs differ from the reference's bitmap lettering. Source and corrected geometry are recorded separately. Duration follows loaded-track identity, including asynchronous loading when the old decoded duration remains temporarily in the audio model.

The initial focused run passed 60 tests and exposed two host checks. Detached native windows round to whole points: rounding the logical compact height before Retina alignment now gives a flush 27 pt Playlist, avoiding 27.36 → 27.5 → 28 double rounding. Seven host checks passed after that correction. The minimize test now activates the app and uses the actual Window → AmpX restoration path instead of invoking deminiaturize on an inactive app; that test and the final typography capture both passed. Live evidence follows in the complete matrix.

## Final visual matrix

Revision: `1348813` plus the final verification commit containing this note, Debug arm64 on macOS 26.6.2. Every offscreen composition below has native 1×, 2×, and 3× PNGs beside its linked 2× image. Captures use production AppKit drawing and the production offscreen Metal mini renderer. Long timer digits shrink uniformly within their reserved cell.

| State | Logical size (pt) | Evidence | Inspection / difference |
| --- | --- | --- | --- |
| All compact, deterministic | 490 × 87.847 | [2×](matrix/matrix-compact-2x.png) | Edge-to-edge; same approved shell; dotSpectrum/classic fixture |
| Mixed: expanded EQ | 490 × 283.105 | [2×](matrix/matrix-mixed-2x.png) | Expanded EQ geometry preserved |
| Reordered: Playlist first | 490 × 87.847 | [2×](matrix/matrix-reordered-2x.png) | No vertical seams or overlap |
| Wide Playlist, signed 100-hour timer | 800 × 87.847 | [2×](matrix/matrix-wide-2x.png) | Only Playlist well stretches; timer stays within its cell |
| Expanded ENTHEA at right | 986 × 290 | [2×](matrix/matrix-right-2x.png) | 6 pt horizontal gap; ENTHEA web content is not frozen/rendered in this offscreen check |
| Native all compact | 490 × 88 | [2×, 980 × 176 px](live/all-compact-2x.png) | Actual paused startup track, Stereo Bars/Amber; not fixture audio |
| Native wide/reordered | 800 × 88 | [2×](live/wide-reordered-2x.png) | Retained width after shrinking; Player/Playlist/EQ order |
| Native detached EQ | 490 × 30 | [2×](live/detached-equalizer-2x.png) | Two chrome buttons; whole-point native height |
| Native detached wide Playlist | 800 × 27 | [2×](live/detached-playlist-wide-2x.png) | Correct width, flush native height, no resize affordance |

Individual Player/EQ/Playlist reference overlays and 1×/2×/3× captures are linked above. Native screenshots were captured by window ID using `shoot.sh --capture-only`; offscreen rasters are not evidence of physical 1×/3× displays. The production ENTHEA switch is disabled, so its right-column composition is verified by the injected-feature layout tests and offscreen capture rather than a production live window. The old expanded mockup remains unavailable; existing expanded reference tests pass, and the pre-implementation live Player baseline is preserved.

Live interaction checks: collapse/expand all modules; EQ volume and balance increments; compact List Options by pointer and Return; grip detach and menu re-dock; widened Playlist collapse; compact edge resize rejection; close/reopen the detached wide Playlist. The earlier Player checkpoint covers timer/style sharing, transport, minimize, and restoration. Original width (490), Player/EQ/Playlist order, 75% volume, centered balance, elapsed timer, and the session's Stereo Bars/Amber selection were restored. The app is left showing the completed compact stack.

## Final verification and review

`./scripts/run-tests.sh -parallel-testing-enabled NO` passed **724 tests, zero failures**. Result bundle:

```text
/Users/santiagorodriguez/Library/Developer/Xcode/DerivedData/AmpX-deeoonschstsamebrcjyfpxsbbix/Logs/Test/Test-AmpX-2026.09.19_10-43-56--0300.xcresult
```

The final suite includes every collapse combination at 490/800 pt and in both orders, closed/detached exclusions, saved layout restoration, viewport/selection retention, weak-reference release checks, real compact keyboard routing, hidden compact GPU submission and renderer fallback checks, all eight visualizer styles and five palettes at compact 1×/2×/3× dimensions, and existing expanded rendering tests.

Independent source review found five issues, reproduced by four new regression methods: stale compact countdown during loading; a prior button reset cancelling a rapid second press; expansion stranding a compact grip drag; late scrollbar drag events; and wheel forwarding into hidden Playlist rows. All causes were fixed. The affected focused run passed 33 tests; the reviewer then confirmed all five findings resolved from source inspection.

SwiftFormat passed with 0/247 files requiring formatting. The lint script reported five pre-existing SwiftLint errors: AudioPlayer type length, AmpXKeyRouter complexity, two large tuples in existing tests, and an existing ENTHEA test identifier. Running against an archive of baseline `88684ef` reproduced the same five errors. These checks preceded the concurrent AGENTS update moving lint/static analysis to CI; no subsequent lint run is required by this task.

The isolated worktree and branch are retained. Concurrent AGENTS, CI, and script-tooling edits belong to separate work and are excluded from the compact-module commits.

## Title-bar double-click follow-up, 2026-09-19

Double-clicking a module's title, brand/grip, or empty title-bar background now toggles compact/normal size through the existing coordinator action. Compact controls and readouts keep their own actions. The second click does not begin a drag, and the expanded header consumes the corresponding mouse-up after changing presentation.

The five new regression methods reproduced the missing toggle before implementation. The affected title, compact chrome, host, interaction, and drag suites then passed **42 tests**, using `./scripts/run-tests.sh -parallel-testing-enabled NO` with those suites selected. Tests cover docked/detached modules, retained 800 pt Playlist width, unchanged host/content instances, single-click grip dragging, and protected controls. All three modules were also toggled in both directions by real title double-clicks in the running app. No lint/static analysis was run for this follow-up.

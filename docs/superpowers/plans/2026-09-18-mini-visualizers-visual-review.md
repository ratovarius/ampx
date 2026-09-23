# Mini visualizers — five-palette live review

**Date:** 2026-09-18\
**Scope:** the existing Player mini display, eight styles, five palettes.

**Later follow-up:** the user requested a red maximum for Classic and the EQ
sliders. Both use the main volume's `#F02008` red. Classic now reaches yellow at
50% of the display range instead of 72%; its peak caps use the gradient color
at their held height rather than a fixed red. The comparison captures below
document the preceding review, before these adjustments.

[Updated Classic gradient and held-peak examples](mini-visualizer-live-review/classic-gradient-and-peaks.png)
show the current behavior using the production Metal renderer. Both regressions
failed before the correction; all 41 focused tests then passed with Metal API
and GPU validation enabled. The 64 captures covering the other four palettes at
1×/2× remained byte-identical. Logs: `/tmp/ampx-classic-gradient-red.log` and
`/tmp/ampx-classic-gradient-green.log`.

Added Red, Green, and the user-approved Amber alongside Blue and Classic.
Blue remains the default. Selection, persistence, the native menu, and the
accessible palette action all support the same five-palette order.

## Actual playback captures

All **40 combinations** were captured from the running macOS app while its
existing music playlist played. Each original is a 980×1768 Retina capture of
the entire Player/EQ/Playlist stack. The sheets below crop those actual pixels;
they do not substitute generated audio frames or mockup artwork.

- [All 40 mini displays, at original Retina pixel size](mini-visualizer-live-review/all-minis.png)
- Full Player context: [Blue](mini-visualizer-live-review/player-blue.png),
  [Classic](mini-visualizer-live-review/player-classic.png),
  [Red](mini-visualizer-live-review/player-red.png),
  [Green](mini-visualizer-live-review/player-green.png),
  [Amber](mini-visualizer-live-review/player-amber.png).
- [All original full-stack captures](mini-visualizer-live-review/full/)
- [Blue before the readability refinements](mini-visualizer-live-review/before/player-blue.png)

Every style and palette was viewed in the mini matrix and in the full Player
context. Captures are sequential moments from the playing playlist, so their
audio levels and waveform shapes differ. The Blue Waterfall capture initially
landed in a track's closing silence; it was replaced during an active passage.

## Visual decisions

The black well, navy frame, gold trim, and green controls already establish a
strong visual identity. The mini effects fit that frame when their background
stays black, their peaks stay crisp, and glow remains close to the trace.

| Palette | Character | Fit with the Player |
|---|---|---|
| Blue | Blue body, cyan trace and highlights | Cool contrast against the warm trim; retained default |
| Classic | Original green/yellow spectrum colors | Strongest connection to the classic player character |
| Red | Crimson body, coral trace, pale warm peaks | Distinct, readable accent without a solid red glow |
| Green | Emerald body, mint trace and highlights | Cleaner and softer than Classic; echoes the green controls |
| Amber | Copper body, gold trace, cream peaks | Closest match to the gold trim and warm slider colors |

**Preferred combinations:** Smooth Spectrum in Amber for a cohesive warm look;
Smooth Spectrum in Blue or Green for a modern luminous trace; Dot Spectrum for
the clearest connection to the display's pixel grid. All five remain selectable.

| Style | Review result |
|---|---|
| Classic Spectrum | Fine bars and separate peak caps remain legible in all palettes |
| Smooth Spectrum | Restrained glow and a dark fill give the strongest modern appearance |
| Dot Spectrum | Cell spacing fits the surrounding pixel display without filling its entire background |
| Mirrored Spectrum | Both halves are visible and centered, including quiet passages |
| Line Waveform | The bright trace remains readable; its shape reflects actual PCM, including strong transients |
| Waterfall | Revised energy mapping separates strong rows from quieter history |
| Particle Waveform | Revised opacity makes quiet particles visible while preserving black negative space |
| Stereo Bars | Two distinct meter rows and independent peak markers remain clear at mini size |

The initial live captures showed particles disappearing at moderate levels:
their opacity multiplied two already-small signal values. Square-root opacity
mapping now preserves low-level visibility while retaining zero opacity for
silence and the existing bounded particle count.

Waterfall previously mapped moderate energy too close to bright energy. A
smoothstep intensity curve with a linear palette ramp restores separation.
Neither change modifies audio analysis, meter calibration, animation timing,
or the surrounding Player UI. No image generation was needed: the review used
the production Metal effects and real app pixels.

## Verification

The new accessibility-cycle, quiet-particle, and Waterfall-contrast regressions
failed before the corresponding fixes. The final Metal/API validation run passed
**23 tests with zero failures**, including **80 deterministic captures**
(eight styles × five palettes × two backing scales), drawable/lifecycle checks,
palette changes, and performance checks.

Metal API and GPU validation were confirmed enabled in the test log. The live
host sample recorded **59.96 FPS**, **1.546 ms CPU encoding p95**, **1.441 ms GPU
p95**, and **zero dropped frames**. Device allocation was unchanged at
28,573,696 bytes across the warmed live sample. These are short Debug measurements
on the existing M1 Pro test machine with validation enabled, not an hours-long
memory or battery test.

Evidence:

- `/tmp/ampx-mini-palette-review-red.log`
- `/tmp/ampx-mini-five-palettes-metal.log`
- `/tmp/ampx-mini-five-palettes-metal.xcresult`
- `/tmp/ampx-mini-five-palettes-full.log`
- `/tmp/ampx-mini-five-palettes-enthea-repeat.log`
- `/tmp/ampx-mini-five-palettes-full-confirm.log`
- `/tmp/ampx-mini-five-palettes-seek-repeat.log`

The first complete serial run passed 651 of 652 tests. The existing ENTHEA
`testTrackChangeEmitsSetTimeline` missed its five-second analysis deadline; it
then passed all three isolated repetitions (0.063–0.700 seconds), with no ENTHEA
changes.

The confirmation run also passed **651 of 652**: ENTHEA passed, but
`AudioPlayerTests.testSeekWhilePlayingSnapshotIncludesSegmentOffset` exceeded the
existing helper's 1.1-second “brief wait” deadline. Its playback-value assertions
did not fail. That test passed in the preceding full run and all three subsequent
isolated repetitions. No audio code, test timeouts, or expectations were changed
for this visual review. The full suite therefore has timing failures recorded;
it is not reported as wholly green.

SwiftFormat and SwiftLint passed for all five affected Swift source/test files.
`git diff --check` and `bash -n scripts/shoot.sh` passed. All 40 original PNG files
were checked for expected dimensions and complete content.

An independent, read-only review found no actionable issues in the scoped code
and five Player contact sheets. The replacement Blue Waterfall capture was
inspected by the implementing agent, outside that independent review.
The app was restored to Particle Waveform / Blue with the current playlist playing.

## Repeatable capture workflow

Select the style and palette in the running Player, allow history to populate
for Waterfall, and capture without relaunching or interrupting playback:

```sh
./scripts/shoot.sh --capture-only \
  --output-prefix docs/superpowers/plans/mini-visualizer-live-review/full/waterfall-blue-
```

The filename convention is `<style>-<palette>-0.png`; style identifiers are
`classic`, `smooth`, `dot`, `mirrored`, `line`, `waterfall`, `particle`, and `stereo`.
Rebuild the sheets from the saved captures:

```sh
xcrun swift -module-cache-path /tmp/ampx-mini-contact-cache \
  scripts/mini-visualizer-contact.swift \
  docs/superpowers/plans/mini-visualizer-live-review/full \
  docs/superpowers/plans/mini-visualizer-live-review
```

The contact-sheet script uses the current 490-point window geometry and Retina
scale to preserve the mini pixels. It is a review utility, not part of the app.

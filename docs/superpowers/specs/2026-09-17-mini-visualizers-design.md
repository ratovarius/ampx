# Player mini visualizers

**Date:** 2026-09-17\
**Status:** Approved by the user on 2026-09-18\
**Reference:** `screenshots/spectrum_analizer_ideas.png`

## Goal and confirmed decisions

Implement the eight retained visual styles from the reference inside the existing Player mini display.
Keep the current Player geometry, timer, chrome, and module behavior.

**2026-09-18 refinement:** the user requested removal of Retro, a clearly visible
mirrored lower half, and a more responsive Stereo Bars display. These corrections
supersede the original nine-style selection and slow meter response.

The user confirmed:

- The styles are available in the existing mini display only for this release.
- Blue, Classic, Red, Green, and Amber are selectable palettes, independent of
  the visual style. Red and Green were requested in the live visual review;
  Amber was explicitly approved as the fifth palette.
- Blue is the default palette.

The renderer accepts an explicit drawable size so a future larger host can reuse it.
An expanded view, new visualization window, effect editor, and external plugin loader
are outside this feature.

## Technology decision

Use an AppKit-hosted `MTKView` with Metal shaders for drawing, and the existing
Accelerate/vDSP analysis path for FFT and signal measurements.

Three approaches were considered:

1. **Metal/MetalKit and Accelerate — selected.** Fits the existing native stack and
   offers a common rendering substrate for bars, curves, texture history, and
   particles. Requires explicit resource lifetime, synchronization, and shader tests.
2. **Extend Core Graphics.** A reasonable option for bars and simple traces, with
   less rendering infrastructure. The full requested collection would also require
   managing history images, glow, and particle drawing through that path.
3. **A SpriteKit scene.** A scene and particle system could implement these looks,
   but adds a separate rendering abstraction alongside the existing Metal code.
   This collection does not need a game scene or node hierarchy.

The choice is based on integration and effect flexibility. It is not a claim that
Metal is faster than Core Graphics for every tiny bar display; validation includes
measuring the implemented result at its actual size.

Use ordinary Metal rendering and compute facilities as needed. This feature does
not require adopting Metal 4-specific APIs or adding a third-party engine.

## Visual behavior

All styles fit the existing `AmpXMetrics.playerSpectrum` rectangle. The surrounding
display well remains AppKit-drawn. The reference is an appearance guide at a larger
size: segment count, trace thickness, and particle density must remain legible at
the actual mini size and at both 1× and 2× backing scales.

The selection order and distinct behavior are:

1. **Classic Spectrum:** narrow continuous frequency bars, with floating peak caps.
2. **Smooth Spectrum:** a smooth frequency curve with a filled area beneath it,
   a bright outline, and restrained glow.
3. **Dot Spectrum:** fine square cells, with dim cells above the active level.
4. **Mirrored Spectrum:** equal frequency-column shapes above and below the exact
   center baseline, with a clearly visible, slightly dimmer lower reflection.
5. **Line Waveform:** a centered bipolar time-domain trace.
6. **Waterfall:** frequency on the horizontal axis and time on the vertical axis;
   the newest spectrum enters at the bottom and older rows move upward.
7. **Particle Waveform:** a bounded field of particles distributed around the
   current waveform, with audio-driven displacement and fading trails.
8. **Stereo Bars:** separate horizontal L/R signal meters showing short-window RMS
   with a fast attack/release and an independent sample-peak marker.

**Reference interpretation for approval:** the image labels its smooth filled
frequency-shaped curve “Smooth Waveform.” This design matches its appearance and
names it “Smooth Spectrum” to describe the data correctly. Line Waveform and
Particle Waveform use time-domain samples.

Waveform rendering should retain short transients when reducing samples to display
columns. It must not create the impression of a time-domain waveform by drawing
frequency bands. Particle motion is decorative, but its underlying trace follows
the waveform.

Blue uses cyan highlights, deeper blue fill/history, and a dark background.
Classic uses green/yellow/red, with red at maximum as requested in the follow-up
color review. Yellow is centered at 50% of the display's level range. Classic
spectrum and stereo peak markers sample that same gradient at their held level,
so a low peak stays green and only a high peak approaches red. Red uses coral
highlights over crimson; Green uses mint highlights over emerald; Amber uses
warm gold highlights over copper to complement the player's gold trim.
All five palettes keep a black background. Palette data also
defines trace, peak, dim-cell, and history colors; it does not change signal mapping
or animation timing. Pixel styles remain crisp; smooth styles use antialiasing and
restrained glow. Color output and blending are defined consistently across all
pipelines to avoid brightness changes when switching modes.

## Interaction and preferences

- A single click advances to the next style immediately.
- Preserve the current double-click behavior: toggle the existing visualizer module
  and restore the style that was active before the first click.
- A native context menu lists all eight styles and a Palette submenu with Blue,
  Classic, Red, Green, and Amber. Checkmarks reflect the current selections.
- Expose the current style and accessible actions for changing style and palette
  through the Player's accessibility model.
- A palette change updates the current frame without resetting peaks or history.
- A style change resets that style's transient animation state and draws immediately,
  including while playback is paused.

Persist style and palette using stable identifiers. Do not derive persistence from
the ordering of the menu or enum cases.

On first use of the new settings:

- Legacy `visualizationMode = 0` and saved `miniVisualizer.style = "retro"` map to
  Classic Spectrum after removal of Retro.
- Legacy `visualizationMode = 1` maps to Line Waveform.
- Legacy `visualizationMode = 2` maps to Classic Spectrum.
- An absent or invalid legacy value defaults to Classic Spectrum.
- An absent or invalid palette defaults to Blue.

Existing new-format preferences take precedence over legacy values. The old key
is not deleted. Unknown style/palette identifiers fall back independently so a
valid palette can survive an unknown style, and vice versa.

## Responsibilities and extension points

Keep these boundaries small and explicit:

### Audio data, in `Sources/Audio/`

The existing analysis tap remains the single audio source. Extend its analysis
publication with the data and timing the mini visualizers need. Spectrum, waveform,
and stereo measurements come from this common stream.

Publish immutable analysis data with sequence/sample positions, sample rate,
playback generation, and timing. Audio data types must not import AppKit or Metal.

Preserve the existing `AudioFeatureBus` and ENTHEA contracts through adapters or
additive publication. Do not change ENTHEA's raw-bin format or calibration.

### Display state, in `Sources/Visualization/`

A frame source samples the analysis timeline. An injectable clock and frame-source
protocol allow deterministic tests without a playing `AudioPlayer` or the shared bus.

Pure state components handle band mapping, attack/release, peaks, waveform reduction,
meter ballistics, and history progression. Their updates use elapsed time and audio
sequence positions rather than “one step per draw.”

Keep spectrum visual height separate from calibrated signal measurements. Stereo
RMS and sample peaks are calculated from PCM, not reconstructed from normalized
spectrum bars or downsampled display points.

### Rendering, in `Sources/Visualization/` and `Sources/Shaders/`

A mini renderer owns frame submission and its per-view GPU resources. A small style
registry selects an effect strategy and its configuration.

Share drawing logic within effect families: spectrum styles, waveform, particles,
waterfall, and meters. Do not duplicate audio processing or the host lifecycle
for each style.

An effect receives prepared frame data, palette parameters, render dimensions, and
explicit GPU resources. It can encode the passes it needs, allowing history or
particle updates before the final render pass. It never accesses `AudioPlayer`,
UserDefaults, or the view hierarchy.

The shared Metal device and compiled pipelines may be reused. Mutable buffers,
particle state, and history textures belong to the renderer instance. Pipeline
lookup should be keyed by a descriptor rather than adding a property for every
style to a growing global singleton.

This is an internal strategy interface, not a dynamic plugin system.

### Player integration, in `Sources/Modules/Player/`

The Player owns selection, context menus, persistence, accessibility, and forwarding
of playback/visibility events. A small AppKit host positions the Metal surface
inside the current spectrum rectangle.

Retain the existing display-well labels and reference-presentation contract. A
deterministic presentation injects data into the production rendering path.

Theme code owns the palette definitions. The audio layer is unaware of themes.

## Audio quality and timing

Preserve the existing post-EQ, post-preamp, pre-volume-fader signal contract in
`2026-09-03-spectrum-signal-path-design.md`, including the existing calibrated
−72…0 dBFS spectrum mapping and disabled auto-range.

Retain the current spectrum FFT/band calibration initially; interpolation of a
smooth curve does not claim to add frequency resolution. The new feature must not
silently change the existing shared FFT size or ENTHEA's frequency-bin layout.

The current spectrum path paces intra-buffer analysis frames, while the waveform
reader returns only the latest window. Extend the mini frame source so its waveform
window and stereo measurements advance on the same visual timeline as its spectrum.
Sequence numbers prevent adding the same frame repeatedly to waterfall history.
Late data holds the latest valid state; it does not move backward or build an
unbounded rendering backlog.

Use sample-rate-aware waveform windows and retention capacity. Cover 44.1, 48, 96,
and 192 kHz with tests, including callbacks longer than the current staging capacity.
Oversized input must have a defined bounded policy; silently losing samples and
presenting them as a contiguous stream is unacceptable.

The tap performs bounded sample capture and timestamping. Rendering, FFT work, heap
allocation, and waits for consumers stay off the audio callback. Audit the existing
staging locks and queue scheduling where this new publication integrates; comments
claiming real-time safety are not sufficient evidence. Use preallocated bounded
storage and an explicit overflow/discontinuity policy.

This design aligns the mini effects to a shared visual timeline. It does not promise
sample-accurate synchronization to hardware output without measuring and accounting
for the existing AVAudioEngine buffering.

Stereo meters use a 20 ms RMS/sample-peak window aligned with the waveform and
fast, time-based display ballistics, with a −72…0 dBFS display range.
Mono audio drives both meters equally.
These are signal meters, not loudness-standard or intersample true-peak meters.

## Lifecycle, resources, and failure behavior

- Target 60 frames per second while the visible mini display is active. Animation
  timing also works correctly at 30 Hz, 120 Hz, and after an interrupted frame.
- Hidden, collapsed, occluded, or detached-from-window hosts stop submitting frames.
  Reuse the existing effective-visibility rules.
- Use one frame driver. Do not leave an AppKit display link and an autonomous
  `MTKView` loop running simultaneously.
- Preserve the repository's macOS 26 callback/executor precautions. Enter a valid
  actor context from framework callbacks, and prevent queued frame work from growing.
- Pause lets bars, meters, traces, and particles settle. Waterfall stops scrolling
  and retains a static history. Once settled, the frame driver parks.
- Playback, style/palette selection, and visibility changes redraw or wake the host
  as appropriate. A selection made while paused renders once and can park again.
- Stop, seek, track replacement, or sample-rate discontinuity clears stale signal,
  peaks, particles, and history. A generation identifier distinguishes new audio
  from an older analysis result that completes late.
- Keep waterfall history bounded to four seconds and particle storage bounded to
  512 particles. Allocate effect-specific resources only when needed. Those limits
  can be reduced if profiling requires it without changing mode semantics.
- Reuse pipeline states and buffers in steady state. Use bounded in-flight GPU
  buffers and nonblocking frame admission so a busy GPU drops a visual frame rather
  than stalling the Player.
- History resources must not be overwritten while an earlier GPU frame reads them.
  Reset and resize operations observe the same lifetime rules.
- Acquire drawables only when drawing. Release references promptly after submission.
- Metal initialization or pipeline failure must not crash audio playback. Use a
  minimal Core Graphics bars/trace fallback, retain the selected preference, and
  expose the renderer error through existing diagnostics.
- Stopping mini rendering must not disable analysis required by ENTHEA or another
  consumer. Do not claim zero application-wide analysis cost merely because the
  mini renderer is parked.

## Validation and acceptance

Use the Xcode test target through `./scripts/run-tests.sh`, which generates fixtures.
New tests cover behavior and boundaries rather than mirroring implementation.

Required checks:

- Preference round trips, legacy migration, invalid values, all eight selectable modes,
  independent palette changes, and click/double-click semantics.
- Deterministic silence, sine, sweep, impulse, unequal L/R, mono, clipping, and
  sample-rate-change inputs. Verify real signal correspondence and finite output.
- Shared spectrum/waveform timing, repeated and late frames, discontinuities,
  bounded overflow, and frame-rate-independent decay/history.
- Visibility, pause/resume, style changes while parked, seek/track reset, missing
  Metal device, and failed pipeline behavior.
- Headless Metal pipeline compilation and offscreen rendering for all eight modes
  in both palettes. Enable Metal validation for resource and synchronization checks.
- Fixed-seed, fixed-time captures of all 16 style/palette combinations at 1× and 2×.
  Inspect actual Player captures using `scripts/shoot.sh`; enlarged contact sheets
  supplement, but do not replace, evaluation at the real mini size.
- Existing audio, ENTHEA, Player interaction, and reference-rendering regressions.
  Do not blanket-update unrelated reference snapshots to hide differences.

Record CPU frame encoding time, GPU time, frame cadence, and resource growth during
steady playback and repeated style switches, using existing signposts where possible.
At the native mini size, target p95 CPU encoding and p95 GPU execution each below
2 ms on the development Mac, with stable memory after warm-up. Record the hardware
and build configuration. These are acceptance targets, not measurements already made.
If a target is missed, profile and resolve it or explicitly review the tradeoff.

Verify that no GPU frames are submitted while hidden or parked. Shader compilation,
texture creation, and preference writes must not recur in the steady-state draw loop.

## Scope of repository changes

Expected areas are the Player mini host/settings, visualization state and renderer,
Metal shaders, theme palettes, additive shared analysis/timing support, and relevant
tests. The old SwiftUI visualization wrappers need only compatibility changes if
shared infrastructure is adjusted.

The worktree already contains uncommitted UI and mini-visualizer changes. Build on
the current contents, preserve those changes, and record baseline failures separately.
Do not replace the current worktree with an older committed implementation.

Implementation follows `../plans/2026-09-18-mini-visualizers.md`.

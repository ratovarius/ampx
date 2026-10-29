# Future work

Deferred ideas that are intentionally out of the current delivery path. Prefer linking a
superpowers plan/spec when one exists.

---

## ENTHEA: optional further Metal port (former Stage / Task 10)

**Status:** skip unless explicitly requested.  
**Spec / plan:** `docs/superpowers/specs/2026-08-02-enthea-visualizer-design.md`,
`docs/superpowers/plans/2026-08-02-enthea-visualizer.md` (Task 10).

### What it is

Rewrite more of ENTHEA’s visual modes (and eventually the panel body) as native **Metal**
shaders / plugins, so the Visualizer panel no longer depends on vendored WebGL in
`WKWebView`.

Stage 8 (ENTHEA-styled mini LCD) was **skipped** by product choice, so there is no
mini-LCD porting pattern to reuse; a Stage 10 effort would start from the existing
fullscreen / mini Metal stack and ENTHEA’s GLSL as reference.

### Benefits (honest)

| Claim | Reality |
|---|---|
| **Performance / power** | **Yes, the main win.** Drops the WebContent process, JS `evaluateJavaScript` audio IPC, and WebGL stack. Better for sustained battery use and Activity Monitor noise. At current panel sizes the WebKit path already holds ~60 fps with the 2.0 Mpx clamp — this is not “we can’t hit frame rate today.” |
| **Real-time / sync** | **Marginal.** Playback → features → viz is already real-time on the WebKit path. Metal might shave IPC jitter; it does not unlock a new class of audio locking unless you also port ENTHEA’s DSP (BPM, drops, etc.), which is a large separate chunk of work. |
| **Better visualizations** | **No.** Same modes, same look (or slightly worse if the port is incomplete). Quality comes from ENTHEA’s shaders and analysis, not from Metal vs WebGL. |

### Other reasons you might still want it

- **License / distribution:** escaping the vendored AGPL WebGL blob if the app is ever published or App Store–bound (`Resources/Enthea/VENDOR.md`).
- **Process model:** one fewer helper process; teardown is just releasing Metal views.
- **One graphics stack:** panel and mini LCD both Metal (today the panel is WebKit, mini stays Classic Metal).

### Cost / risk

- Large: ~29 mode branches in one uber-shader, plus analysis if you want feature parity.
- Easy to ship a thinner, less reactive viz if only the pretty fragment is ported and ENTHEA’s `updateAudio` chain is not.

**Do not start by default.** Pursue only if WebKit cost, battery, or distribution constraints justify the rewrite.

---

## Smart playlists (DJ mode)

**Status:** taken out of DJ mode on 2026-10-28; not designed.  
**Spec:** `docs/superpowers/specs/2026-09-11-dj-mode-design.md` (Revision 1, § Smart playlists) has the
original sketch.

### What it is

Saved, live-updating queries over the library: a Codable `LibraryPredicate` that extends `LibraryQuery`
with comparisons on BPM, bitrate, codec and Camelot key, evaluated against the in-memory `LibraryIndex`
and re-evaluated on every `LibraryChange`. The sketch's four defaults: *Gig-ready* (≥ 315 kbps or
lossless), *Needs replacing* (< 192 kbps), *Energy bands* (118–124 … 138+ BPM) and *Key-compatible*
(Camelot neighbours of the playing track).

### Open questions

- **How they are used:** browsed and picked from by hand, or sent whole to the Playlist. This decides
  whether they need a list in the Library window, their own window, or only a menu.
- **Where they live in the UI:** the Library window has no pane for them (GENRE, ARTIST, table,
  MIXES WELL); placing one needs an AmpX UI spec amendment first.
- **Persistence:** `SmartPlaylistRecord` needs a new schema stage, `LibrarySchemaV4` (V2 is the rekordbox
  sync's, V3 DJ mode's library data).
- **Lossless list:** include ALAC (`.m4a`) alongside FLAC, WAV and AIFF.
- **Party queue** (DJ mode phase B) was meant to draw from a smart playlist; without them it needs
  another source, such as the current Playlist or a genre.

---

## Cue UI (DJ mode)

**Status:** deferred on 2026-10-28 until cues are set by hand in rekordbox.  
**Spec:** `docs/superpowers/specs/2026-09-11-dj-mode-design.md` (Revision 2, § Cues).

DJ mode Revision 2 stores every hot cue and memory cue from the rekordbox export but shows none: today the
export only has rekordbox's automatic hot cue A at the first downbeat. When hand-set cues exist, add marks
on the seek bar and jumps to hot cues 1–8 from the keyboard.

---

## Native BPM and key detection (DJ mode)

**Status:** dropped from DJ mode Revision 2 on 2026-10-28; every DJ track has rekordbox BPM and key.  
**Spec:** `docs/superpowers/specs/2026-09-11-dj-mode-design.md` (Revision 1, § Native analyser) has the
original sketch: spectral-flux onsets with autocorrelation for tempo, chroma against Krumhansl–Schmuckler
profiles for key.

Worth reviving only for libraries without a rekordbox export.

---

## Mix-point scan (DJ mode)

**Status:** moved out of DJ mode on 2026-10-29 (it was Delivery 2 of Revision 2); designed, not built.  
**Spec:** `docs/superpowers/specs/2026-09-11-dj-mode-design.md` (Revision 2, § Mix points).

### What it is

AmpX's own per-bar energy scan, giving Automix's Intro / Outro method intro and outro lengths for tracks
that have a beatgrid but no rekordbox phrases. Today such tracks fall back to Last Phrase.

- **Decode** with `AVAudioFile` through the root's security scope, mixed to mono, off the playback graph.
- **Filter:** two cascaded high-pass at 300 Hz and a low-pass at 4 kHz (`vDSP` biquads), the melody-and-vocals
  band. DJ intros and outros keep the drums and drop the melody, so the kick-and-bass band cannot find them.
- **Measure:** RMS per bar from the grid's first downbeat, full range and filtered band, each normalised to its
  95th percentile and stored as `UInt8` in `mixScan` (already in `LibrarySchemaV3`, always nil): version byte,
  the `duration` and grid hash it was computed for, then two bytes per bar.
- **Edges:** intro = bars before the first run of 4 bars at or above 0.6 in the filtered band; outro = bars
  between the last such run and the last bar above the silence floor (0.08) in the full range, which is also
  `A.end` when there are no phrases.
- **Cache:** invalid only when `duration` changes by more than 10 ms or the grid hash changes. Not keyed by
  `contentFingerprint`, which covers the ID3 tags, so a tag write would invalidate every scan.
- **Run:** `.utility`, 4 tracks at a time, cancellable, after the scanner and sync jobs; the footer shows
  `ANALYSING n/m`. Measured cost: ~0.66 s per track.

### Why it was dropped

On the real library (2,232 tracks) every track with a beatgrid has rekordbox phrases, and the grid comes from
rekordbox too, so the scan would cover almost nothing. Worth building if rekordbox turns out to skip phrases for
a noticeable share of tracks, or for libraries analysed without phrase analysis.

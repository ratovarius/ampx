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
- **Persistence:** `SmartPlaylistRecord` needs `LibrarySchemaV3` (V2 is the rekordbox sync's).
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

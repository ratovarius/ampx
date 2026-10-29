# DJ Mode (MIXES WELL, rekordbox Tags and Phrases, Automix)

**Date:** 2026-09-11 · **Revised:** 2026-10-28 (Revision 2: smart playlists moved to future work; tag writing, cues, rekordbox phrases and Automix designed with the user) · 2026-10-29: the mix-point scan (former Delivery 2) moved to future work
**Status:** Delivery 1 implemented on `feature/dj-mode-library-data` (PR #16); Delivery 2 (Automix) implemented on `feature/dj-mode-automix`, pending the listening check
**Depends on:** [Music Library](./2026-09-11-music-library-design.md), [Library Module](./2026-09-27-library-module-design.md) and [rekordbox Collection Sync](./2026-09-28-rekordbox-sync-design.md), all merged to `develop` in PR #15 (`502b1aa`)
**Related:** [2026-09-03-spectrum-signal-path-design.md](./2026-09-03-spectrum-signal-path-design.md) (tap point)

## Goal

Make AmpX usable for **playing electronic music at home without the Pioneer controller**: build playlists from tracks that mix well, keep rekordbox's data in the files where other apps can read it, and play a Playlist as a continuous, beat-matched set.

## What changed since Revision 1

| Revision 1 | Revision 2 |
|---|---|
| rekordbox import, Camelot, `LibrarySchemaV2`, re-parse rule | Already shipped by the rekordbox sync spec in PR #15. Not repeated here |
| Smart playlists in phase A | Out of scope. Recorded in `docs/future-work.md` |
| Party queue drawing from a smart playlist, ±4 BPM window | Replaced by **continue with MIXES WELL** when the Playlist runs out. One tempo rule (±6%) everywhere |
| Native BPM/key analyser (phase B′) | Dropped from this revision: every DJ track has rekordbox BPM and key. Recorded in `docs/future-work.md` |
| Tag write-back of computed BPM/key | Tag writing of **rekordbox** data, opt-in, standard fields only |
| Cues listed as imported, never used | Stored now; no UI until the user sets cues by hand (future work) |
| Auto-mix: crossfade aligned to the first beat | **Automix** with mix points from rekordbox phrases or the beatgrid, Crossfade or Bass Swap, tempo kept after the blend |

## Deliveries

Built and landed **in this order** (user's choice: data first, then playback). Each is usable on its own.

| # | Delivery | Contents | Audio code |
|---|---|---|---|
| 1 | **Library data** | `LibrarySchemaV3`; MIXES WELL; set and variable-tempo classification; tag writing; cue import; rekordbox phrase import and the access grant | None |
| 2 | **Automix** | Two-deck `AudioGraph`, `MixScheduler`, mix points, Crossfade / Bass Swap, tempo matching and glide, continue with MIXES WELL, plain crossfade | Yes |

The **mix-point scan** (AmpX's own per-bar energy scan for tracks without rekordbox phrases, Delivery 2 in the first draft of this revision) moved to `docs/future-work.md` on 2026-10-29 (user). On the real library every track with a beatgrid has rekordbox phrases, and the grid also comes from rekordbox, so the scan would cover almost nothing: the 10 tracks the phrase import skips are five pairs of duplicate files, fixed by removing one copy of each. Without phrases, Intro / Outro falls back to Last Phrase.

## Approaches considered

| Approach | Trade-off | Outcome |
|---|---|---|
| **Data first, then playback** | MIXES WELL and tags are useful weeks before Automix; the risky audio work builds on tested data | **Chosen** |
| Automix first | Transitions are heard sooner, but the riskiest code goes first and Automix cannot continue past the Playlist until MIXES WELL exists | Rejected |
| Pre-rendered transitions on the existing single player | No graph change, but the matched tempo cannot be kept for the rest of the track, the glide is impossible, and every pause or change of the next track forces a re-render | Dropped |

## Non-goals

- Being a DJ controller: no jog wheels, no user-facing per-deck EQ, no MIDI, no DVS. Bass Swap's automatic low cut is internal to a transition.
- Live pitch-bend or manual beatmatching.
- Smart playlists (future work).
- Cue UI: seek-bar marks and keys 1–8 (future work).
- Native BPM/key detection (future work).
- Writing anything back to rekordbox.
- Writing non-standard tags: rating, beatgrid, cues, play count and mix stay AmpX-only.
- Recording the mix output.
- Changing the spectrum tap point or FFT calibration.

## Decisions (user, 2026-10-28)

| Topic | Choice |
|---|---|
| Tags | rekordbox data is written into the files **only for standard fields**; everything else stays as today (AmpX database only) |
| Tag writing trigger | Opt-in setting. Once on, AmpX keeps tags updated automatically after every rekordbox sync. Also available per track |
| Tag conflicts | rekordbox overwrites a differing tag, **except** a BPM tag that is half or double rekordbox's: that is never written and is listed for the user to check in rekordbox |
| Smart playlists | Out of this design |
| Hot cues | Stored; no UI now. The user may set cues by hand later |
| Mix points | Two methods, named **Last Phrase** (beatgrid only) and **Intro / Outro** (rekordbox phrases; Last Phrase when a track has none). The AmpX scan fallback moved to future work (2026-10-29) |
| Naming | Industry terms: **Automix**, mix points, **Crossfade** / **Bass Swap**, lengths in bars |
| Tempo after the blend | The incoming track **keeps the matched tempo** to its end. Optional, configurable **glide back** toward the track's original tempo when the next track's tempo lies that way |
| What Automix plays | The Playlist, **in its order**. MIXES WELL is for building playlists and never overrides the Playlist |
| Playlist runs out | MIXES WELL picks the next track |
| Pick pool | Setting: **Whole library** or **Current view** (the Library window's genre/artist/search filter) |
| Half / double tempo | A match, but a **change of chapter**, not a normal next track |
| Variable tempo | Handled by how much the tempo varies (see *Track classes*) |
| DJ sets and mixes | Left out of Automix and MIXES WELL |
| rekordbox analysis folder | One-time access grant through an open panel; without it, no phrases (Intro / Outro falls back to Last Phrase) |

## Measured collection (2026-10-28, rekordbox 7.2.19 export, `~/Music/DJ`, 2,232 tracks)

| Measure | Value |
|---|---|
| Formats | 2,032 mp3, 119 wav, 36 aif/aiff, 29 m4a, 16 flac |
| Files with a BPM tag | 404: 349 agree with rekordbox, 21 are half or double, 34 differ otherwise (e.g. `12497`) |
| The 21 half/double | rekordbox likely right on 14 (mostly DnB at 162–176), the tag likely right on 6 (4 DnB tracks rekordbox reads at 87; 2 organic-house tracks it reads at 170/180), 1 unclear |
| Cues in the export | 2,198 tracks have one: rekordbox's automatic hot cue A at the first downbeat (median 0.165 s). 34 have none. No memory cues |
| Tracks with more than one `TEMPO` | 678: 518 vary ≤ 0.5%, 72 vary 0.5–8%, 88 vary > 8% (26 of those are recorded sets) |
| Sets | 26 with genre `Sets & Mixes` (shortest 3¾ min) plus 10 untagged mixes of 45–120 min. Longest real track: 28½ min |
| rekordbox analysis files | `~/Library/Pioneer/rekordbox/share/PIONEER/USBANLZ/*/*/ANLZ0000.DAT` / `.EXT`; 2,235 map to a path; 397 of a 400-file sample have phrase data |
| AmpX scan cost (future work) | ~0.66 s per track (prototype with ffmpeg, including process start); ~5 min for the whole library with 4 workers; ~600 B per track cached |

## Data model: `LibrarySchemaV3`

A lightweight migration from `LibrarySchemaV2` under `LibraryMigrationPlan`. Every new field is optional or defaulted.

`LibraryTrack` gains:

| Field | Source | Rule |
|---|---|---|
| `cues: Data?` | XML `POSITION_MARK` | Packed like `beatGrid`: version byte, then per mark `Num` (−1 memory, 0–7 hot), `Type` (0 cue, 4 loop), `Start`, `End` (loops), name. Written by the sync; never displayed in this revision |
| `tempoSpread: Double?` | derived from `beatGrid` | `(max − min) / median` of the grid's BPMs, in percent. Recomputed whenever `beatGrid` changes |
| `phrases: Data?` | rekordbox `PSSI` | Packed: version, mood, end beat, then per phrase `(beat, kind)`. Kinds are normalised to `intro`, `outro`, `other` (see *rekordbox phrases*) |
| `phrasesStamp: Data?` | — | `(size, modificationDate)` of the `.EXT` file the phrases came from |
| `mixScan: Data?` | AmpX scan (future work) | Reserved, always nil: added in V3 so the scan needs no migration. Format in `docs/future-work.md` |
| `tagsWrittenHash: Data?` | tag writer | Hash of the tag values last written or confirmed in the file. A row is due for writing when the hash of its current values differs |

`LibraryRow` gains `tempoSpread`, `hasPhrases` and `isSet` (derived, below). The parser and planner gain `cues`; the sync writes them like the other imported fields.

## Track classes

Computed in `LibraryIndex`, never stored:

| Class | Rule | Automix | MIXES WELL |
|---|---|---|---|
| **Set** | Genre `Sets & Mixes` (case-insensitive) **or** duration > 30 min | Plays if the user put it in the Playlist; plain crossfade in and out | Never listed, never picked |
| **Steady** | `tempoSpread` ≤ 0.5% | Normal | Normal |
| **Drifting** | 0.5% < `tempoSpread` ≤ 8% | Normal, with the rate taken from the grid's **local** tempo at the blend bars, updated per bar | Normal |
| **Changing** | `tempoSpread` > 8% | Plain crossfade, no tempo matching | Listed with a `VAR` tag; never picked on its own |
| **No grid** | `beatGrid` nil | Plain crossfade | Listed if BPM is known; never picked on its own |

## Delivery 1: Library data

### MIXES WELL

Per the Library Module spec's handoff: the reference track follows the PLAYING / SELECTED switch, matches are BPM within ±6% and a Camelot-compatible key (same, ±1, relative), reason tags `SAME KEY`, `+1`, `−1`, `REL`, `±n%`, and **+ QUEUE** appends to the Playlist. This revision adds:

- **Exclusions:** sets, unavailable rows and the reference track itself.
- **Ranking** (my call): key relation (same, then ±1, then relative), then the smallest BPM difference.
- **Change chapter:** a second group below the normal matches, headed `CHANGE CHAPTER`, for tracks whose **half or double** BPM is within ±6% and whose key is compatible. Tagged `½×` or `2×`.
- **`VAR` tag** on tracks of the Changing class.

### Continue with MIXES WELL (used by Automix, defined here)

A pure function: given the reference track, the reference tempo, the pool, and the set of excluded tracks, it returns the next track or nothing.

- **Reference tempo** (my call): the **effective** tempo the live deck is playing at, not the file's BPM. After a few kept-tempo blends the two can differ by up to 6%, and matching against the file BPM could pick a track outside the ±6% clamp. The MIXES WELL list does the same when its reference is PLAYING and Automix is on, and shows the tempo it used.
- **Pool:** setting **Pick from: Whole library | Current view**, default **Current view** (my call: a set usually stays in one style). Current view is the Library window's genre, artist, search and BPM-range filter **at the moment of the pick**. Missing rows are never in the pool, so the MISSING view adds nothing.
- **Filter persistence** (my call): the Library window keeps updating a separate, persisted copy of its filter, used only by the pick. The window itself still opens unfiltered after relaunch, as the Library Module spec settled.
- **Candidates:** the normal MIXES WELL group only (never a chapter change), excluding sets, Changing and No-grid tracks, anything played since Automix was turned on, and any `AUTO` track the user removed from the Playlist in that time (my call: removing one is a way to steer the set, so it must not come straight back).
- **Choice:** the top-ranked candidate. If there is none, the closest BPM in the pool among the same exclusions, ignoring key. If the pool has nothing left, nothing: Automix stops after the current track.

### Tag writing

**Setting:** *Keep rekordbox Data in File Tags*, default **off**.

- **Turning it on** reads every matched file's tags and shows a one-time summary overlay in the Library window (like the rekordbox report): files to update, per field; files skipped (read-only, unreachable); half/double BPM tracks. **Write Tags** or **Cancel**.
- **After that,** each rekordbox sync queues rows whose `tagsWrittenHash` differs from their current values. Only changed fields are written.
- **Per track:** *Write rekordbox Tags* for the selected rows, available whether or not the setting is on.

**Fields** (standard only):

| Data | ID3v2 (mp3, wav, aiff) | Vorbis comment (flac) | MP4 (m4a) |
|---|---|---|---|
| BPM | `TBPM` | `BPM` | `tmpo` |
| Key, musical notation as rekordbox spells it (`Am`, `F#m`, `Dbm`) | `TKEY` | `INITIALKEY` | `----:com.apple.iTunes:initialkey` |
| Label | `TPUB` | `LABEL` | `----:com.apple.iTunes:LABEL` |
| Remixer | `TPE4` | `REMIXER` | `----:com.apple.iTunes:REMIXER` |
| Composer | `TCOM` | `COMPOSER` | `©wrt` |
| Grouping | `TIT1` | `GROUPING` | `©grp` |

BPM is written as a rounded integer: ID3 defines `TBPM` as an integer and MP4 `tmpo` is one (my call to use the same everywhere). Camelot is not written; `TKEY` is musical notation by definition.

**Rules:**

- Every other tag, picture and chunk is preserved. The existing ID3 version of a file is kept.
- A rekordbox value replaces a differing tag. An empty rekordbox value never clears a tag.
- **Half/double guard:** when the file's BPM tag is within 1% of half or double rekordbox's BPM, BPM is not written (the other fields are). The track is listed under **Tempo half or double: check in rekordbox** in the summary and in the sync report, until the two agree. The fix is made in rekordbox (beatgrid edit, ×2 or ÷2) and arrives with the next export.
- **Atomic:** write to a temporary copy in the same folder, read the copy back and check the written values and its audio duration, then replace the original with `FileManager.replaceItemAt`. Never edit in place.
- **Read-only file:** skipped, listed in the report. **Unreachable root:** retried when the root becomes available.
- **After a write:** the file's size and mtime change, so the next scan re-parses it. `analysisSource` stays `.rekordbox`, so the existing re-parse rule keeps the imported values.
- **Access:** library roots are user-selected with read-write security-scoped bookmarks, which cover writing inside them.
- **Library** (my call): **TagLib**, vendored as source and built as a static library (MPL 1.1 option, compatible with AmpX's MIT licence). Hand-written writers for five containers are not worth the corruption risk.
- **Scheduling:** writes run as a job kind in the scanner's FIFO, after the sync that produced them, one root at a time.

### Cues

The parser reads `POSITION_MARK` into `cues`. Nothing displays them. Automix lines beats up on the beatgrid's first downbeat, which the grid already has; the automatic hot cue A sits on the same point.

### rekordbox phrases

**Access:** *Allow Access to rekordbox Analysis…* opens an `NSOpenPanel` pointed at `~/Library/Pioneer/rekordbox`, for folders only. The chosen folder is stored as an app-scope security-scoped bookmark in `UserDefaults`. Without it, phrases are simply not imported and Intro / Outro falls back to Last Phrase. A stale or failed bookmark is logged (category `RekordboxPhrases`) and treated as no access; nothing is shown in the UI, as with the sync.

**Reading** (format reverse-engineered by Deep Symmetry; not published by AlphaTheta):

- Files are tagged sections: a 4-byte code, header length and total length (big-endian), from the offset in bytes 4–8 of the file header.
- `ANLZ0000.DAT`, section `PPTH`: UTF-16BE, length at section offset 12. rekordbox stores only `?/` plus the **file name**, never the folder (all 2,240 files, measured 2026-10-28). A folder therefore matches the row with that file name (NFC) whose beatgrid's first beat (section `PQTZ`: count at section offset 20, then per beat UInt16 beat number, UInt16 BPM × 100, UInt32 time in ms) agrees with the row's rekordbox grid within 20 ms and 0.05 BPM. A row without a grid matches only a unique name. Several candidates, or a row two folders claim, are ambiguous and skipped. On the real library this links 2,222 of 2,232 tracks; the other 10 are five pairs of identical copies inside `~/Music/DJ`.
- `ANLZ0000.EXT` in the same folder, section `PSSI`: phrase analysis. Entry count is a big-endian `UInt16` at section offset 16. In current rekordbox versions the body from offset 6 is XOR-masked with the 19-byte key `CB E1 EE FA E5 EE AD EE E9 D2 E9 EB E1 E9 F3 E8 E9 F4 E1`, each byte plus the entry count (mod 256). A mood value above 20 at body offset 6 means the mask is present.
- After unmasking: mood (`UInt16`, body offset 6: 1 high, 2 mid, 3 low), end beat (offset 14), then 24-byte entries from offset 20: index, beat, kind (`UInt16` each).
- **Kinds:** high mood: 1 Intro, 6 Outro. Mid and low mood: 1 Intro, 10 Outro. Everything else is `other`.
- Beat numbers index the track's beatgrid from its first beat. A phrase's bar is counted from the first downbeat.
- Any unexpected value (unknown mood, entries past the section end, beats past the grid) means **no phrases** for that track, logged once.

**When:** after each rekordbox sync for a root, and at launch. Only `.EXT` files whose `(size, modificationDate)` differs from `phrasesStamp` are read. Runs as a scanner FIFO job, like the sync's check.

**Licence:** the decoder is written from the published format description, not ported from any code. The terms of that description and rekordbox's own licence are checked before a release, as for the database-access future work.

## Delivery 2: Automix

### User-facing settings

There is no Settings window, so these live in the menus (my call): **Playback ▸ Automix** (toggle), and **Playback ▸ Automix Options**:

| Setting | Values | Default |
|---|---|---|
| Mix points | Last Phrase · Intro / Outro | Intro / Outro |
| Transition | Crossfade · Bass Swap | Crossfade |
| Blend (Last Phrase) | 8 · 16 · 32 bars | 16 |
| Longest blend (Intro / Outro) | 16 · 32 · 64 bars | 32 |
| Glide back to original tempo | on / off | off |
| Glide speed | 0.05 · 0.1 · 0.2 BPM per 4 bars | 0.1 |
| Continue with MIXES WELL when the Playlist ends | on / off | on |
| Pick from | Whole library · Current view | Current view |

The tag and phrase-access items live in the Library window's ROOTS menu, in a **rekordbox** section, next to the existing rekordbox lines (my call; there is no settings window).

Constants not exposed: the phrase length (16 bars) and the 4-bar rounding. The explainer prototype showed these do not need user tuning.

### What plays next

1. The Playlist's next track as `PlaylistManager` defines it, including **Shuffle**. Automix never reorders.
2. **Repeat on:** the Playlist starts over; MIXES WELL never picks.
3. **No next track, Repeat off, continuation on:** as soon as the last Playlist track starts, the continuation pick is appended to the Playlist, marked with a small `AUTO` tag in its row, so the user can remove or replace it before the mix. If the pick returns nothing, Automix stops after the current track.
4. The next track is re-read whenever the Playlist changes, until 5 s before the mix-out.

### Mix points

Bars are counted from each track's first downbeat. A's content end, `A.end`, is, in order of preference (my call):

1. the rekordbox phrase end beat, when A has phrases (it is rekordbox's own "end of music" mark);
2. the last full bar of the grid.

Both mix-point methods use this `A.end`. Whether the phrase end beat is a good mix-out anchor is checked by ear during Automix testing.

- **Last Phrase:** A mixes out at the last 16-bar phrase boundary `b` such that `b + blend ≤ A.end`. B mixes in at its bar 1. Blend: the setting.
- **Intro / Outro:**
  - B's intro: bars before the end of its leading `intro` phrases.
  - A's outro: from the start of its trailing `outro` phrases to the phrase end beat.
  - Blend = min(intro, outro, longest blend), rounded down to 4 bars. A mixes out at `A.end − blend`; B mixes in at `intro − blend`, so B's main part arrives as A's content ends.
  - If the blend comes out below 4 bars, or one of the tracks has no phrases, Last Phrase is used for that transition.
- **Plain crossfade** (Set, Changing or No-grid on either side, or tempos outside the clamp): 6 s, equal-power, starting 6 s before A's content end (or its end), with B from its start. No tempo change.

### Tempo

- **Matching:** B's rate = A's current effective BPM ÷ B's local BPM at the mix-in bar, via `AVAudioUnitTimePitch` (pitch kept). If the rate is beyond ±6%, the transition is a plain crossfade and B plays at its own tempo.
- **Half / double:** when the user put a half- or double-tempo track next, B's BPM is first doubled or halved to the nearer octave of A's, then the same ±6% rule applies, so beats line up one for two.
- **After the blend:** B keeps its rate to its end.
- **Glide back** (off by default): once the next track is known, if moving the live track's tempo toward its original BPM also moves it toward the next track's (octave-normalised) BPM, the rate eases toward the original at the glide speed, changing only on bar boundaries, and stops at the original. It never overshoots. It runs in both directions (my call: a set that only ever glides down would creep up over a night). If the next track changes, the glide target is recomputed.
- **Manual play** (double-click, Play on a stopped player) starts the track at its original tempo. **Automix turned off** mid-track: the live track keeps its rate until it ends, then playback continues at original tempos.

### Transitions

- **Crossfade:** equal-power (`cos`/`sin`) envelopes on the deck mixers over the blend.
- **Bass Swap:** the same volume envelopes, plus a low cut (high-pass at 150 Hz via a per-deck `AVAudioUnitEQ` band) on B for the first half of the blend. At the bar nearest the midpoint, B's cut is removed and A's applied in the same render quantum.

### Audio graph

Revision 1's two-deck design stands: `deckSum` becomes the chain's single upstream, so `reconnect()` and `tapPoint` keep their one-input logic; `AudioGraph.source` becomes a computed accessor for the live deck's player; ReplayGain stays on each deck's player node and the fade envelope on each deck's mixer (*two gain stages*). Changes:

- Each deck is `player → timePitch → eq → fade mixer → deckSum`. **Both** decks have a time-pitch unit (the incoming deck becomes the live deck and keeps its rate). A deck at rate 1 with no cut has both units bypassed.
- **Beat alignment:** B is scheduled from its mix-in time with `play(at:)` at the output sample time where A's mix-out downbeat will be heard, computed from A's player sample time and its current rate.
- **Drifting class:** B's rate is recomputed at each bar of the blend from both grids' local tempos.

### Clock, completion and transport

- **Ramps follow audio time, not wall time.** `MixScheduler` derives blend progress from the live deck's `playerTime.sampleTime`, ticking about every 10 ms on its own queue. Pausing stops the sample clock, so ramps freeze; resuming continues them. No separate pausable timer.
- **Completion ownership:** each deck has its own completion generation, checked on `audioQueue` as in `1bd1449`. In Automix, the outgoing deck's natural completion is consumed by `MixScheduler` and never calls `onTrackFinished`; the Playlist advances at the blend midpoint. Outside Automix, completion behaves as `08adc7f` defines.
- **Transport** (Revision 1, unchanged): the live deck reports `currentTime`, `duration` and Now Playing; the switch happens once, at the blend midpoint, with the track-change notifications.
- **During a blend:** Next completes the transition at once (B at full gain, A stopped). Previous or a double-click stops both decks and plays the chosen track at its original tempo. A seek aborts the blend and applies to the live deck. Pause freezes both.
- **Next outside a blend** (user, 2026-10-28): skip now. The next track starts at once, at its original tempo, exactly like manual play. No transition is computed.
- **Seek outside a blend** (my call): the planned mix-out stands if the new position is before it. A seek past it makes this transition a plain crossfade at `A.end`.
- **B fails to load:** A plays to its end and the Playlist advances normally.
- **Automix off:** single-deck playback, exactly as today.

## Error handling & edge cases

| Case | Behaviour |
|---|---|
| Tag write: temp copy fails its read-back check | Original untouched, temp removed, logged; row stays due |
| Tag write: disk full / folder not writable | Same as above; listed in the report as skipped |
| File BPM tag half or double rekordbox's | BPM not written; listed under *Tempo half or double* |
| rekordbox access not granted / stale | Silent; Intro / Outro uses Last Phrase for every track |
| `PSSI` missing or unreadable for a track | No phrases; Intro / Outro uses Last Phrase for its transitions |
| rekordbox changes the ANLZ format | Decoder rejects unknown values; every track falls back to Last Phrase; logged once |
| Next track is a Set / Changing / No grid | Plain crossfade |
| Next track shorter than the blend | Blend shortened to a third of B's duration, rounded down to 4 bars; plain crossfade if under 4 bars |
| Next track removed from the Playlist after B is scheduled but before the mix-out | B is unscheduled; the next track is re-read |
| Continuation pool empty | Automix stops after the current track |
| ReplayGain read lands mid-blend | Written to that deck's player; envelope unaffected (Revision 1) |
| Library window closed during continuation | Last persisted filter used |
| Schema V2 store | Migrates to V3 on open; new fields nil; the sync and the phrase import fill them |

## Testing

| Area | Checks |
|---|---|
| `LibraryMigrationTests` | V2 store opens as V3 with every value kept |
| `RekordboxCollectionParserTests` (added) | `POSITION_MARK` → cues, including hot, memory and loop marks; tracks without marks |
| Track classes | Boundaries at 0.5% and 8%; the set rule (genre, 30 min, the 28½-min track is not a set) |
| MIXES WELL | Ranking; exclusions; the chapter group with ½× and 2×; `VAR` tags |
| Continuation | Current view vs. whole library; no chapter changes; no repeats; closest-BPM fallback; empty pool |
| Tag writer | Per format (mp3 ID3v2.3 and 2.4, wav, aiff, flac, m4a fixtures): only changed fields written, other tags and artwork preserved, empty value never clears, half/double guard, read-only skip, failed read-back leaves the original byte-identical |
| `PSSI` decoder | Masked and unmasked fixtures (trimmed from real files), all three moods, a corrupt section rejected, `PPTH` path mapping with NFD names |
| Mix points | Last Phrase and Intro / Outro on fixture grids and phrases, including the 14-bar intro, the fallback to Last Phrase, and the 4-bar rounding |
| Tempo | ±6% clamp; octave normalisation; glide direction, speed, stop at the original, recompute on next-track change |
| `MixScheduler` | Equal-power sum; Bass Swap switch on one bar; ramps freeze with the sample clock; Next/Previous/seek mid-blend; outgoing completion never advances the Playlist; transport switches once |
| `AudioGraph` | `tapPoint` unchanged with `deckSum`; `AudioGraphTests` pass unmodified |
| Regression | `AudioPlayerTests`, `PlaybackIntegrationTests` green with Automix off |
| Gate (opt-in, `TEST_RUNNER_AMPX_LIBRARY_GATE=1`) | On `~/Music/DJ`: the share of tracks with phrases (≥ 95%) |

## Success criteria

**Delivery 1**

1. MIXES WELL lists sensible matches for any playing DnB, techno or house track, never lists a set, and shows half/double tracks only under CHANGE CHAPTER.
2. Turning tag writing on shows the summary, and after Write Tags every writable file carries rekordbox's BPM and key in the standard field, with no other tag lost. The 21 half/double files keep their BPM and are listed.
3. A BPM change made in rekordbox and re-exported reaches the file's tag with no clicks.
4. With access granted, phrases are imported for the large majority of tracks.

**Delivery 2**

5. A Playlist of steady 4/4 tracks within ±6% plays as a continuous set: beats stay aligned through every blend, B's main part arrives as A's content ends, and no level jump is heard.
6. After a blend, the track stays at the matched tempo; with glide on, it drifts back without an audible step.
7. When the Playlist ends, the continuation keeps the set going from the current view, without repeats, until the pool runs out.
8. The spectrum display, seek bar and Now Playing behave correctly through blends; `AudioGraphTests` pass unmodified.

**All:** `./scripts/run-tests.sh` green.

## Files expected to change

- **New:** `Sources/Library/LibrarySchemaV3.swift`; `Sources/Library/Rekordbox/RekordboxPhrases.swift` (ANLZ reader), `RekordboxPhraseSync.swift`; `Sources/DJ/MixesWell.swift` (matching, ranking, continuation), `TrackClass.swift`, `TagWriter.swift` (TagLib bridge), `MixPoints.swift`, `MixScheduler.swift`, `TempoPlan.swift`; vendored TagLib under `Vendor/taglib/`.
- **Changed:** `RekordboxCollectionParser.swift`, `RekordboxImportPlanner.swift` (cues); `LibraryScanner+Scheduling.swift` (phrase and tag-write job kinds); `LibraryIndex.swift`, `LibraryValues.swift` (new row fields, classes); the Library module's MIXES WELL pane, ROOTS menu and report overlay; `Sources/Audio/AudioGraph.swift`, `Sources/AudioPlayer.swift` (decks); `PlaylistManager.swift` (next-track query, `AUTO` mark); `AmpXMenuCatalog.swift` and the menu wiring (Automix items).
- **Docs:** the rekordbox sync spec's cue count and non-goals point here; `docs/future-work.md` gains smart playlists, cue UI, native BPM/key detection and the mix-point scan.

## Risks

| Risk | Mitigation |
|---|---|
| Tag writing corrupts a file | TagLib; temp copy, read-back check, atomic replace; opt-in; per-format tests |
| rekordbox's ANLZ format changes | Strict decoder; fallback to Last Phrase; logged |
| Phrase decoder licence or rekordbox terms | Checked before a release; written from the format description, not ported code |
| Time-stretch artefacts | ±6% clamp; the matched tempo usually sits within 2–3% |
| Beat drift over a long blend | Sample-accurate scheduling; per-bar rate updates for Drifting tracks |
| Two decks disturb the tap or ReplayGain | Revision 1's `deckSum` and two-gain-stage design, with its regression tests |
| Continuation picks something unwanted | It lands visibly in the Playlist with an `AUTO` mark before the mix |

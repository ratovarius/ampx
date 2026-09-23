# DJ Mode (Analysis Import, Smart Playlists, Mixed Playback)

**Date:** 2026-09-11 · **Revised:** 2026-09-14
**Status:** Proposed — aligned with music library spec Revision 5
**Depends on:** [2026-09-11-music-library-design.md](./2026-09-11-music-library-design.md) Revision 5. Its phase L1 (engine) is needed for all engine work here; its phase L2 (the Library module, after the AmpX UI cutover) is needed for every UI item
**Related:** [2026-09-03-spectrum-signal-path-design.md](./2026-09-03-spectrum-signal-path-design.md) (tap point, FFT reuse)

## Goal

Make the player usable for **playing electronic music at home without the Pioneer controller**: know every track's BPM and key, filter by them, and move between tracks without a gap or a jarring cut.

## Phasing

This spec covers two bodies of work that share a goal but almost no code. They are planned and landed **separately**, and each has its own success criteria below:

| Phase | Scope | Depends on |
|---|---|---|
| **A — Knowing the collection** | rekordbox import, Camelot conversion, `LibrarySchemaV2` migration, scanner re-parse rule, smart-playlist evaluation and persistence | Library L1 |
| **A-UI** | BPM/Key (Camelot) columns, smart-playlist list, import report, derived-bitrate marking in the Library module | Phase A **and** Library L2, and therefore the AmpX UI cutover |
| **B — Playing it** | Two-deck `AudioGraph`, `MixScheduler`, crossfade, auto-mix, party queue | Phase A (auto-mix needs BPM) |
| **B′ — Native analysis** | `TempoEstimator` / `KeyEstimator` / `AnalysisQueue`, tag write-back | Phase A; **optional**, may never ship |

Phase A is cheap and delivers most of the value. Its engine work can land as soon as library L1 does; A-UI waits for L2 like the rest of the library UI. Phase B is the audio-engine risk. B′ is explicitly the one to drop if time runs out — the rekordbox import is what makes the collection navigable, not our own beat detector.

## Non-goals

- Being a DJ controller. No jog wheels, no per-deck EQ kills, no MIDI mapping, no vinyl/DVS
- Live pitch-bend or manual beatmatching
- Stem separation
- Writing back to rekordbox (import is one-way)
- Recording the mix output (separate concern; macOS-level capture is the current answer)
- Changing the analysis tap point or FFT calibration settled in the spectrum spec

## Decisions (locked)

| Topic | Choice |
|---|---|
| First source of BPM/key | **Import rekordbox `collection.xml`**, not native analysis. rekordbox's free plan already analyses the library; parsing its export is a few hundred lines versus a beat detector that needs tuning |
| Import parser | `XMLParser` (Foundation), streaming — the export for 2,232 tracks is large and should not be loaded as a DOM |
| Match strategy | File path first: the rekordbox `Location` is mapped to a library root plus `relativePath`, the library's row key. Fall back to `(fileSize, duration ±1 s)` across all rows, including rows in unavailable roots. Unmatched and ambiguous tracks are reported, never guessed |
| Native analysis | **Phase B′, optional.** Only runs for tracks with no imported BPM. Accelerate/vDSP, reusing `FFTSpectrumAnalyzer`'s window plumbing |
| Key notation | Two fields. The library spec's `musicalKey` keeps the key **as tagged** (`Am`); this spec adds `camelotKey` (`8A`) as a derived, always-recomputable value. The UI shows Camelot, because that is what mixing uses; the classical value is what gets written back to TKEY |
| Schema change | The added fields (`camelotKey`, `analysisSource`, `beatGridAnchor`, cues, `isUserOverridden`) ship as **`LibrarySchemaV2`**, the successor of the library spec's `LibrarySchemaV1`, under its `LibraryMigrationPlan`. Lightweight migration: all new fields are optional or defaulted, and the new `SmartPlaylistRecord` model is additive |
| Analysis results | Written to the index **and** back to the file's ID3 tags (TBPM/TKEY). This is the **one** write-back path in the project; the library spec explicitly does not open files for writing, and user-facing tag editing remains a later spec. Opt-in setting, default off |
| Smart playlists | A Codable `LibraryPredicate` that extends the library's `LibraryQuery`. It is evaluated against the in-memory `LibraryIndex` snapshot, never through the writer. Saved as `SmartPlaylistRecord` in `LibrarySchemaV2` and re-evaluated on every `LibraryChange` |
| Re-scan vs. analysis | The library scanner re-parses a file whenever `(size, mtime)` changes. From V2 it refreshes `bpm` / `musicalKey` from tags **only** when `analysisSource` is nil or `.fileTag` and `isUserOverridden` is false. Rekordbox, computed and overridden values survive a re-parse; without this rule, any external tag edit would silently revert imported BPM/key |
| Rating import | rekordbox `Rating` fills `rating` only on unrated rows (`0`). A differing non-zero rating is listed as a conflict in the report and nothing is overwritten. The library spec reserves `rating`; this import is its first writer |
| Crossfade | Two `AVAudioPlayerNode`s, each behind its **own `AVAudioMixerNode`**, summed into the existing effect chain. Equal-power curve, 0–12 s |
| Gain separation | The fade envelope is written to the **deck mixer's** `volume`; ReplayGain stays on the **player node's** `volume`, untouched. See *Two gain stages* below — this is the one place where "reuse the existing graph" would otherwise silently break normalization |
| Auto-mix | `AVAudioUnitTimePitch` on the incoming node only, clamped to **±6 %** rate; beyond that, plain crossfade |
| Auto-mix default | **Off.** It is a party feature, not the default playback path |

## Problem

Most of the collection carries no BPM or key tag. Without them, "play electronic music at home" means hand-picking every track, and the library's genre crates are the only navigation — which is how the collection got unwieldy in the first place.

**To be measured before planning this spec**, not asserted: the library spec's index already stores `bpm` and `musicalKey` from tags, so the first scan answers this exactly. Record the real counts here — `N of 2,232 with BPM`, `M with key` — and let them set the expectation for how much the rekordbox import has to fill in. If it turns out most files are already tagged, Phase A shrinks to a verification pass and this spec gets cheaper.

Writing a beat detector first is the expensive path. rekordbox already computed this data for free; the cheap move is to read it.

## Architecture

### Analysis provenance

Every BPM/key value carries where it came from, because the three sources have very different trust levels:

```swift
enum AnalysisSource: String, Codable {
    case fileTag      // TBPM/TKEY already in the file
    case rekordbox    // imported from collection.xml
    case computed     // our own analyser
}
```

Precedence on conflict: `rekordbox` > `fileTag` > `computed`. A user override pins the value and is never recomputed.

### rekordbox import

`RekordboxCollectionImporter` streams the export and maps each `<TRACK>`:

| rekordbox attribute | Destination |
|---|---|
| `Location` (URL-encoded `file://`) | match key |
| `AverageBpm` | `bpm` |
| `Tonality` | `musicalKey` verbatim, **and** `camelotKey` derived from it |
| `TotalTime`, `Size` | fallback match key |
| `Rating` (0–255, steps of 51) | `rating` (0–5), unrated rows only |
| `<TEMPO Inizio=… Bpm=…>` | first beat offset → `beatGridAnchor` |
| `<POSITION_MARK>` | cue points |

Result is a report: matched / unmatched / conflicting, shown before anything is written. Import is idempotent — running it twice changes nothing.

**Location mapping.** `Location` is URL-decoded, standardized and symlink-resolved, then compared with each available root's resolved URL; the remainder of the path is the candidate `relativePath`. Tracks outside every root go straight to the size + duration fallback and are reported unmatched if that fails. The import never creates rows or roots. A fallback hit with more than one candidate row is a conflict, not a match.

### Native analyser (phase B')

Only for rows where `bpm == nil` after import and whose root is available. The decoder reads through the root security scope that `LibraryStore` holds.

- **Tempo** — spectral-flux onset envelope from existing FFT magnitudes → autocorrelation over lags for 60–200 BPM → parabolic peak interpolation. Octave correction prefers the 85–175 range.
- **Key** — 12-bin chroma folded from FFT magnitudes, averaged over the track body (skip first/last 10 %), correlated against Krumhansl–Schmuckler major/minor profiles; best correlation wins.

Runs on an `OperationQueue`, `.utility`, `maxConcurrentOperationCount = ProcessInfo.activeProcessorCount / 2`, cancellable, progress through the same `AsyncStream` idiom as the scanner. Decode via `AVAudioFile` reads — **not** through the live playback graph.

### Smart playlists

```swift
struct SmartPlaylist {
    var name: String
    var predicate: LibraryPredicate   // composable, Codable
    var sort: LibrarySort
    var limit: Int?
}
```

`LibraryPredicate` extends `LibraryQuery` with comparisons on `bpm`, `bitrate`, `codec` and `camelotKey`, plus a dynamic *current track* reference. It runs in `LibraryIndex` alongside ordinary queries, so the library's generation and cancellation rules apply. In V2, `LibraryRow` gains `camelotKey`, `analysisSource` and `isUserOverridden`. The current track is resolved to a row by URL through the index; a track that is not in the library makes Key-compatible empty. Smart playlists exclude unavailable rows from enqueue exactly as the browser does. "Live-updating" means re-evaluated on each `LibraryChange` and, for Key-compatible, on track change.

Ships with four defaults, which are the ones that actually matter for this collection:

| Name | Predicate |
|---|---|
| Gig-ready | `bitrate >= 315_000 OR codec IN {flac, wav, aiff}` |
| Needs replacing | `bitrate < 192_000` |
| Energy band | `bpm BETWEEN lower AND upper` — instantiated per band (118–124, 124–128, 128–132, 132–138, 138+) |
| Key-compatible | Camelot neighbours of the current track: same number ±1, and the relative major/minor toggle |

"Key-compatible" is dynamic — it re-evaluates against whatever is playing.

**On the bitrate thresholds.** For VBR MP3 the library's `bitrate` is an average either way — AVFoundation's `estimatedDataRate`, or `fileSize * 8 / duration` when that is unavailable. That average lands a few kbps either side of the nominal rate, so a strict `>= 320_000` would drop genuine V0/320 VBR files out of "Gig-ready" for arithmetic reasons. Hence **315 kbps** as the practical floor. `LibraryTrack` also records whether the bitrate was **reported or derived**; the Library module marks derived values (phase A-UI) so a surprising bucket is explainable rather than mysterious. The 192 kbps floor needs no such slack — nothing sits within rounding distance of it.

### Mixed playback

```
deckA.player ──► deckA.mixer ──┐
  (ReplayGain)   (fade env)    │
                               ├──► deckSum ──► EQ preamp ──► AVAudioUnitEQ ──► tap ──► mainMixer
deckB.player ──► deckB.mixer ──┘   (mixer)                                       ▲     (listening fader)
  (ReplayGain)   (fade env)                                                      │
     └─ optional AVAudioUnitTimePitch, incoming deck only      unchanged from spectrum spec
```

#### Changes to `AudioGraph`

`AudioGraph` today owns exactly one source: `let source: AVAudioPlayerNode`, attached in `init`, wired by `reconnect()` as the single upstream of `effects[0]`, and doubling as `tapPoint` when the chain is empty. `AudioPlayer` caches it (`self.playerNode = graph.source`) and hangs its sample-time bookkeeping off that one node. "Add a second player node" is therefore a real change to the graph's shape, not an addition beside it:

- `source` becomes a **`deckSum: AVAudioMixerNode`** — the chain's single upstream, so `reconnect()` and `tapPoint` keep their current one-input logic **unchanged**. This is what makes the spectrum spec's tap guarantee survive: the tap still reads the last effect output, and the effect chain still has exactly one thing feeding it.
- Each deck is a `(player: AVAudioPlayerNode, fade: AVAudioMixerNode, pitch: AVAudioUnitTimePitch?)` triple attached by the graph and connected into `deckSum`.
- `AudioGraph.source` is kept as a computed property returning the **live deck's** player node, so existing `AudioPlayer` call sites and `AudioGraphTests` continue to compile and pass. Single-deck playback is the case where deck B is simply silent.

#### Two gain stages

This is the part that would break quietly if left implicit. ReplayGain is applied **as `playerNode.volume`** by `AudioPlayer.applyPlayerVolume()`, deliberately upstream of the tap so the post-EQ analysis never sees the listening fader. A crossfade that also writes `playerNode.volume` would overwrite the normalization gain — and worse, any `applyPlayerVolume()` landing mid-fade (a ReplayGain read completing, a preamp change) would snap the level.

So the two gains live on different nodes:

| Stage | Node | Written by | Meaning |
|---|---|---|---|
| Normalization | `deck.player.volume` | `AudioPlayer.applyPlayerVolume()`, per deck | ReplayGain for the track on that deck |
| Fade envelope | `deck.fade.volume` | `MixScheduler` only | 0→1 equal-power ramp |
| Listening | `mainMixer.outputVolume` | existing volume model | unchanged |

`applyPlayerVolume()` becomes per-deck (it takes a deck, reads that deck's `currentReplayGain`) and `MixScheduler` never touches a player node. The product of the two is the audible gain, so a quiet track still gets its boost mid-blend and the fade is still exactly equal-power.

`MixScheduler` owns which deck is live, pre-schedules the next track `crossfadeSeconds + 2` before the end, and ramps `deckA.fade.volume` down / `deckB.fade.volume` up on an equal-power curve (`cos/sin`, so perceived loudness is constant).

#### Position and transport during two-deck playback

`AudioPlayer`'s `currentTime` is derived from the live player node's `playerTime.sampleTime` plus the segment offset. With two decks that needs one rule, stated here so it is not decided ad hoc in code:

- **The live deck is the transport.** `currentTime`, `duration`, `isPlaying`, Now Playing info and the seek bar all report the outgoing deck until the crossfade's **midpoint**, then the incoming deck — a single switch, not a blend, so time never runs backwards visibly within one track's display.
- Track-change notifications (`NowPlayingInfo`, the marquee, the visualizer's track-change hook) fire at that same midpoint, once.
- `seek` applies to the live deck only and aborts any running crossfade (see edge cases).
- `pause` pauses both decks and freezes the ramp in place; `play` resumes it from where it stopped.

With auto-mix on and both BPMs known, the incoming deck's `AVAudioUnitTimePitch.rate` is set to `outgoingBPM / incomingBPM`, clamped to ±6 %, and the crossfade is aligned to the incoming beat-grid anchor. Outside the clamp it degrades silently to a plain crossfade.

### Party queue

Pulls from a chosen smart playlist, refuses to repeat anything played in the last N tracks, and keeps successive BPMs within a configurable window (default ±4). Fills continuously so a night runs unattended.

## Error handling & edge cases

| Case | Behavior |
|---|---|
| No rekordbox export present | Import menu item explains where to produce one; nothing else changes |
| Export references files not in the library | Counted as unmatched in the report; no rows created |
| Same track matched twice | Conflict listed; user resolves; no silent overwrite |
| BPM detected as exactly half/double a sane value | Octave correction to 85–175; flagged `lowConfidence` for review |
| Key detection on a beatless or ambient track | Low correlation → store `nil` rather than a wrong key |
| Tag write-back on a read-only file | Index still updated; write-back failure logged, surfaced once, not fatal |
| Crossfade when the next track is shorter than the fade | Fade shortened to `min(crossfade, nextDuration / 3)` |
| User hits Next mid-crossfade | Both ramps cancelled; incoming deck jumps to full gain |
| Auto-mix with one BPM unknown | Plain crossfade, no time-stretch |
| Tracks at wildly different BPM (e.g. 90 vs 140) | Outside the ±6 % clamp → plain crossfade, no stretch |
| Seeking during a crossfade | Crossfade aborts; live deck honours the seek (existing absolute-time behaviour preserved) |
| ReplayGain read completes mid-crossfade | Written to that deck's **player** node; the fade envelope on the deck mixer is untouched, so the ramp does not jump |
| Pause mid-crossfade | Both decks pause, ramp frozen at its current position; resume continues from there rather than restarting or snapping |
| VBR file straddling a bitrate threshold | Derived bitrates get the 315 kbps floor and are marked derived in the browser; no silent misclassification |
| Container is still schema V1 when DJ mode first runs | `LibraryMigrationPlan` migrates `LibrarySchemaV1` → `LibrarySchemaV2` on open; new fields default to nil/false; no re-scan needed |
| Write-back disabled (default) | Analysis lands in the index only. A later re-parse, when the file changes on disk, keeps it, because the scanner refreshes `bpm`/`musicalKey` only for `fileTag`/nil sources |
| Write-back enabled | The atomic temp-file replace gives the file new tag bytes and a new mtime but the same path. The library keeps the same row ("same path = same track") and re-parses and re-fingerprints it on the next scan; `analysisSource` is unchanged, so the value is not demoted to `fileTag` |
| Tag edited externally after import | Re-parse updates title, genre and other tag fields; imported BPM/key are kept per the re-scan rule |
| rekordbox `Location` inside an unavailable root | Path mapping skipped; the size + duration fallback still runs against that root's rows |

## Testing

| Area | Expectations |
|---|---|
| `RekordboxCollectionImporter` | Fixture XML parses; URL-decodes `Location` and maps it to root + `relativePath`; outside-root and ambiguous fallback matches reported, not invented; Tonality → Camelot table; rating fills unrated rows only; idempotent re-import |
| Camelot conversion | All 24 keys round-trip both directions |
| Tempo estimator | Synthesised click tracks at 120 / 128 / 174 BPM detected within ±1; a 64 BPM track not reported as 128 |
| Key estimator | Synthesised C-major and A-minor chord progressions classified correctly; white noise → `nil` |
| `SmartPlaylist` | Each default predicate returns the expected fixture subset; key-compatible follows the current track |
| `MixScheduler` | Equal-power ramp sums to constant power; short-next-track clamp; Next mid-fade cancels cleanly; pause freezes and resumes the ramp |
| Gain separation | `MixScheduler` never writes `player.volume` (spy); an `applyPlayerVolume()` call mid-fade leaves the fade envelope unchanged; audible gain equals normalization × envelope at every sample of the ramp |
| Two-deck transport | `currentTime` follows the outgoing deck before the fade midpoint and the incoming deck after, switching exactly once; track-change fires once |
| `AudioGraph` | `tapPoint` is unchanged with `deckSum` in place; `AudioGraph.source` still returns the live deck's player node so existing `AudioGraphTests` pass untouched |
| Schema V2 | A `LibrarySchemaV1` container migrates to `LibrarySchemaV2` with rows, ratings and play counts intact; new fields default cleanly |
| Re-scan preservation | After import, changing a file's mtime re-parses it without replacing rekordbox, computed or overridden BPM/key; a `fileTag`-sourced value is refreshed |
| Regression | Spectrum tap assertions from the spectrum spec still hold with two player nodes present; existing `AudioPlayerTests` and `PlaybackIntegrationTests` green with a single deck in use |

## Files expected to change

- **New** `Sources/DJ/RekordboxCollectionImporter.swift`
- **New** `Sources/DJ/CamelotKey.swift`
- **New** `Sources/DJ/TempoEstimator.swift`, `KeyEstimator.swift` (phase B')
- **New** `Sources/DJ/AnalysisQueue.swift`
- **New** `Sources/DJ/SmartPlaylist.swift`, `LibraryPredicate.swift`
- **New** `Sources/DJ/MixScheduler.swift`, `PartyQueue.swift`
- `Sources/Audio/AudioGraph.swift` — `deckSum` mixer as the chain's single upstream; two deck triples attached; `source` becomes a computed live-deck accessor; `tapPoint` logic unchanged
- `Sources/AudioPlayer.swift` — deck ownership, `applyPlayerVolume()` becomes per-deck, transport follows the live deck
- **New** `Sources/Library/LibrarySchemaV2.swift` — `camelotKey`, `analysisSource`, `beatGridAnchor`, cues, `isUserOverridden`, `SmartPlaylistRecord`; V1→V2 stage added to `LibraryMigrationPlan` in `LibrarySchemaV1.swift`
- `Sources/Library/LibraryScanner.swift` — re-parse honours `analysisSource` / `isUserOverridden`
- `Sources/Library/LibraryIndex.swift`, `LibraryQuery.swift` — V2 row fields; `LibraryPredicate` evaluation
- `Sources/Modules/Library/` (phase A-UI, after library L2) — BPM/Key columns in Camelot, smart-playlist list, import report
- `Sources/Utilities/AmpXMenuCatalog.swift` — `File ▸ Import rekordbox Collection…`; crossfade and auto-mix toggles under Playback
- **New** tests per the table above

## Success criteria

**Phase A — knowing the collection**

1. Importing a rekordbox `collection.xml` populates BPM and key for the great majority of the 2,232 DJ tracks, with an honest report of what did not match.
2. The four default smart playlists return sensible sets immediately after import, and "Gig-ready" does not exclude VBR 320 files on rounding.
3. An existing V1 library container opens as V2 with every row, rating and play count intact, and a later re-scan never reverts imported BPM/key.

**Phase B — playing it**

4. Consecutive tracks crossfade with no audible gap or level jump, at any configured fade length — including when one track is ReplayGain-boosted and the other is not.
5. With auto-mix on and two tracks inside ±6 %, the transition is beat-aligned; outside it, it degrades to a plain crossfade without any glitch.
6. The spectrum display still behaves per the spectrum spec with two decks in the graph, and `AudioGraphTests` passes unmodified.
7. The seek bar and Now Playing never show time running backwards through a crossfade.

**Both**

8. `./scripts/run-tests.sh` green.

## Risks

| Risk | Mitigation |
|---|---|
| rekordbox XML schema varies by version | Parse defensively, attribute-by-attribute; never assume an element exists; fixture from the actual installed version |
| Path matching fails at scale (moved files, rekordbox paths outside library roots) | `Location` → root + `relativePath` mapping, size + duration fallback, and an explicit unmatched/conflict report rather than silent partial success |
| Two player nodes disturb the tap semantics just settled | Both decks sum into `deckSum`, which is the chain's single upstream — so `reconnect()` and `tapPoint` keep one-input logic. Regression test asserts `tapPoint` is unchanged |
| Crossfade silently overwrites ReplayGain | The two gains are on different nodes by design (player = normalization, deck mixer = envelope), with a test spying that `MixScheduler` never writes a player node's `volume`. This is the failure that would have been found only by ear |
| Transport reporting becomes ad hoc across two decks | One stated rule — live deck is the transport, switching at the fade midpoint — with a test, rather than a decision made per call site |
| `AVAudioUnitTimePitch` artefacts on large stretches | ±6 % clamp is deliberately conservative; beyond it, do not stretch at all |
| Tag write-back corrupts files | Write to a temp file and atomically replace; never edit in place; opt-in setting |
| Native analyser becomes a time sink | It is explicitly phase B' and optional — the rekordbox import is what delivers the value |

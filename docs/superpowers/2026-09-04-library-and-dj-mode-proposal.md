> **Superseded — kept for context.**
> This was written as a proposal before the spec step, and does not follow the
> plans/ format (no Global Constraints, no file map, no checkbox tasks).
> It has been split into three specs, which are the current source of truth:
>
> - [specs/2026-09-11-music-library-design.md](./specs/2026-09-11-music-library-design.md)
> - [specs/2026-09-11-dj-mode-design.md](./specs/2026-09-11-dj-mode-design.md)
> - [specs/2026-09-11-app-identity-design.md](./specs/2026-09-11-app-identity-design.md)
>
> Implementation plans are written per-spec, after the spec is agreed.

# Plan — Library, DJ mode, and rename

Status: proposal · 2026-09-04

## Where the project actually stands

The audio half is solid: `AudioPlayer` (AVAudioEngine + 10-band EQ + media keys),
`FFTSpectrumAnalyzer`, ReplayGain, the Metal visualizer, ENTHEA, Classic 275 px UI.
~35k lines of Swift.

The **library half does not exist**. `Track` carries `title / artist / duration /
fileSize / url` and nothing else — a grep for genre, album, BPM or key across
`Sources/` returns only ReplayGain's album-gain handling. `PlaylistManager` is a
flat `[Track]` with M3U + bookmark persistence.

That is fine for "open a folder, press play". It does not work for a 2,232-track
DJ collection in 17 genre crates, and it is the single thing blocking the goal of
using this as the main player at home.

---

## Phase 1 — A real library (the missing half)

**1.1 Widen `Track`.** Add: `album`, `albumArtist`, `genre`, `year`, `trackNumber`,
`bitrate`, `sampleRate`, `channels`, `codec`, `bpm`, `musicalKey`, `comment`,
`dateAdded`, `dateModified`, `lastPlayed`, `playCount`, `rating`.

`AVAsset` metadata already gives most of this — `TrackMetadataParser` just isn't
asking for it. `.commonKeyAlbumName`, `.id3MetadataKeyContentType` (TCON/genre),
`.id3MetadataKeyBeatsPerMinute` (TBPM), `.id3MetadataKeyInitialKey` (TKEY).
Bitrate/sample rate come from `AVAudioFile.processingFormat` + file size.

**1.2 Persist an index.** The no-third-party-packages rule points at **SwiftData**
(or Core Data) — Apple frameworks, no SPM dependency. A `LibraryStore` actor
owning the model container, queried off the main thread.

Do *not* re-read tags on every launch. Key each row on
`(bookmark, fileSize, mtime)` and only re-parse when those change.

**1.3 Scan + watch.** `LibraryScanner` walks a set of watched roots
(`~/Music/DJ` first), enumerating with `FileManager.enumerator` and
`.isRegularFileKey / .contentModificationDateKey` prefetched. Incremental on
subsequent runs. `FSEventStreamCreate` for live updates — an Apple API, no package.

Security-scoped bookmarks are already solved in
`Playlist/SecurityScopedBookmarkStore.swift`; reuse it for library roots rather
than inventing a second mechanism.

**1.4 Free win:** every track in `~/Music/DJ` already carries a genre tag equal to
its crate name. A scan reproduces all 17 crates as genre facets with zero extra work.

**Deliverable:** a browser panel — sidebar of genres/crates, track table sortable
by any column, live search. Must match the Classic aesthetic per AGENTS.md; a
resizable list panel in the existing chrome, not a full-window redesign.

---

## Phase 2 — DJ mode (the actual differentiator)

This is what makes it worth using when the Pioneer controller isn't around.

**2.1 Import rekordbox's analysis instead of computing it.**
This is the highest-value idea in this document. rekordbox's free plan analyses
the library and can export `collection.xml` containing **BPM, musical key, beat
grid, cue points and ratings** for every track. Parsing that XML with
`XMLParser` (Foundation) gets 2,232 tracks fully analysed for a few hundred lines
of code — versus writing and tuning a beat detector.

Match rows to library entries by file path, falling back to size + duration.

**2.2 Only then, a native analyser** for anything rekordbox hasn't seen.
Accelerate/vDSP is already a dependency via `FFTSpectrumAnalyzer`:
- **BPM** — spectral-flux onset envelope → autocorrelation over a 60–200 BPM
  lag range → parabolic interpolation of the peak. Octave-error correction by
  preferring the 85–175 range.
- **Key** — 12-bin chroma from the existing FFT magnitudes, averaged over the
  track, correlated against Krumhansl-Schmuckler profiles. Display in **Camelot**
  notation (8A, 5B …) since that is what mixing actually uses.
Run as a background `OperationQueue` at low QoS, write results to both the index
and the file's ID3 tags so the work survives a re-scan.

**2.3 Smart playlists.** Predicate-based, saved, live-updating. The three that
matter, mirroring the rekordbox advice:
- **Gig-ready** — `bitrate >= 320 OR codec in {flac, wav, aiff}`
- **Energy bands** — BPM ranges rather than genre: 118–124, 124–128, 128–132,
  132–138, 138+
- **Needs replacing** — `bitrate < 192`
- **Key-compatible with current track** — ±1 on the Camelot wheel, plus the
  relative major/minor. This one is only possible once 2.1 or 2.2 has run.

---

## Phase 3 — Playing a set without the controller

**3.1 Gapless + crossfade.** Two `AVAudioPlayerNode`s on the existing graph,
pre-scheduling the next buffer. Configurable crossfade 0–12 s with an
equal-power curve.

**3.2 Auto-mix.** With BPM known, time-stretch the incoming track to match using
`AVAudioUnitTimePitch` and crossfade on a bar boundary. Not a DJ controller —
but enough for unattended music at a party, which is the stated use case.

**3.3 Cue points + hot cues.** Store per-track cues in the index; keyboard
triggers. If 2.1 ran, rekordbox's own cue points are already there.

**3.4 A "party queue"** — pull from a smart playlist, avoid repeats, keep the BPM
inside a band. Effectively a personal radio over your own crates.

---

## Phase 4 — Housekeeping

- `startup.mp3` and the Classic sprite work stay as they are.
- Consider a small `LibraryStats` panel — it would have surfaced the fact that
  `Hard Groove (128k)` is 218 tracks at 128 kbps without a separate audit.
- Write-back of edited tags, so fixing an artist in the player fixes the file.

---

## Sequencing

1. Phase 1.1 + 1.2 (widen model, persist) — everything else depends on it
2. Phase 1.3 + browser UI — the point at which it becomes usable daily
3. Phase 2.1 (rekordbox XML import) — cheap, huge payoff
4. Phase 2.3 smart playlists
5. Phase 3.1 crossfade
6. Phase 2.2 native analyser, Phase 3.2 auto-mix — the expensive, optional ones

---

## Rename

`Reamp` is **not available** — `Reamp.app` sitting in the repo root is a
third-party macOS player (Russian localisation, ZIPFoundation, PLCrashReporter,
a SkinsQuickLook extension). Not a build of this project.

Candidates:

| Name | Why |
|---|---|
| **Enthea** | Already yours, already in this codebase as the visualizer. Distinctive, no obvious conflict, and promoting it unifies the project's identity. |
| **Vitrola** | Record player in Spanish/Portuguese. Personal resonance, warm, unmistakably not Winamp. |
| **Kilohertz / kHz** | Technical, era-appropriate, short. Check for conflicts — plausible someone has it. |
| **Sonabar** | Invented, so most likely to be clear. |
| **Deka** | From "deck". Very short, good for a compact player. |

Trademark clearance is not something to take on faith — search EUIPO and USPTO
for the shortlisted name before committing, and check the macOS App Store and
GitHub.

**Rename checklist:** `PRODUCT_BUNDLE_IDENTIFIER` (currently `com.ampx.macos`
and `com.ampx.macos.tests`), Xcode target/scheme/project names, `Info.plist`
`CFBundleName`/`CFBundleDisplayName`, `build.sh` `PROJECT_NAME`,
`create-dmg.sh`, `AppIcon`, the `Winamp*` type prefixes in `Sources/`
(`AmpXApp`, `AmpXColors`, `AmpXSkinSprites`, `AmpXPanel*` — ~10 files),
the `AmpXTests` target, README/AGENTS/CLAUDE/USAGE, and the GitHub repo name.

### One thing worth deciding deliberately

The rename addresses the *word* Winamp. The Classic UI is a close reproduction of
Winamp 2.x's visual design — README says sprite coordinates and geometry come from
Webamp. If the goal of renaming is to be clear of the legacy, the interface is the
larger exposure, not the name.

That does not mean abandoning the compact-player idea, which is the good part and
is not owned by anyone. It means drawing your own 275 px skin: your own sprite
sheet, type, and colours, keeping the *shape* of the thing — small floating
window, detachable playlist and EQ, visualizer panel — without reproducing
Winamp's artwork. ENTHEA already shows you can do original visual work here.

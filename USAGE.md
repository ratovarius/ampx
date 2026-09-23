# Using AmpX

AmpX opens as one window with three stacked modules: **Player**, **Equalizer** and **Playlist**.

## Add music

- **File → Add Files…** (`L`) or **Add Folder…** (`⇧L`); folders are scanned recursively
- Drag files or folders onto the playlist
- The eject button on the player
- **File → Load Playlist… / Save Playlist…** for M3U files

Supported formats: MP3, FLAC and WAV.

## Modules

- **Move:** drag a module by the logo at the left of its title bar. Drop it inside the stack to reorder it, or outside to detach it into its own window. Drag it back to re-dock it.
- **Title bar buttons:** minimize (player only), collapse/expand, close.
- **Show/hide:** the **EQ** and **PL** buttons on the player, or the **View** menu.
- **Window menu:** move up/down (`⌥⌘↑` / `⌥⌘↓`), detach/re-dock (`⌥⌘D`), collapse (`⌥⌘C`).

## Player

- Transport buttons, seek bar, volume and balance, **Shuffle** and **Repeat**
- **Mini visualizer:** click to cycle through modes. Right-click to choose a mode or color palette.

## Equalizer

- 10 bands (60 Hz to 16 kHz) plus preamp, ±12 dB
- **ON** enables the EQ. **PRESETS** has built-in presets, **Load EQF…** and **Reset**.

## Playlist

- Double-click or `Return` plays a track. Click, `⇧`-click and `⌘`-click to select.
- Footer menus: **ADD**, **REM** (remove/crop/clear), **SEL**, **MISC** (sort, reverse, randomize, file info), **LIST OPTS** (new/save/load).
- Drag the bottom-right corner to resize.

## Keyboard shortcuts

| Key | Action |
|---|---|
| `Space` | Play / pause |
| `X` | Play (restarts a playing track) |
| `C` | Pause / unpause |
| `V` | Stop |
| `Z` / `B` | Previous / next track |
| `S` / `R` | Shuffle / repeat |
| `←` / `→` | Seek −/+ 5 s (also with the playlist focused) |
| `↑` / `↓` | Volume |
| `L` / `⇧L` | Add files / add folder |
| `⌘O` / `⌘S` | Load / save playlist |
| `⌥3` | File info (selected track in the playlist, otherwise the current track) |
| `⌘T` | Elapsed / remaining time |

With the playlist focused:

| Key | Action |
|---|---|
| `↑` `↓` `Home` `End` `PgUp` `PgDn` | Move the selection (add `⇧` to extend it) |
| `Return` | Play |
| `Delete` | Remove selected |
| `⌘⌫` / `⌘⇧⌫` | Crop to selection / clear playlist |
| `⌥↑` / `⌥↓` | Move selected tracks |
| `⌘A` / `⌘I` | Select all / invert |
| `⌘⇧1` / `⌘⇧2` / `⌘⇧3` | Sort by title / file name / path |
| `⌘R` / `⌘⇧R` | Reverse / randomize |

Right-click a playlist row for Play, Get Info, Remove from Playlist and Remove from Disk.

## Troubleshooting

- **A file won't play:** make sure it is MP3, FLAC or WAV, and check the volume and system output device.
- **A file can't be opened:** add it with Add Files or Add Folder so macOS grants access.

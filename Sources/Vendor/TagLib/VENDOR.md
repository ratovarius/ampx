# TagLib (vendored)

- **Version:** 2.3.2 (released 2026-09-05)
- **Source:** https://github.com/taglib/taglib/releases/download/v2.3.2/taglib-2.3.2.tar.gz
  (SHA-256 `3ca2d8afaa7f1cf7f6ed10e511ebc368bfacd6dcaa3dbfa690b89e502e8963dc`)
- **Licence:** dual LGPL-2.1 / MPL-1.1 (`COPYING.LGPL`, `COPYING.MPL`). AmpX uses it under the **MPL-1.1**, which allows
  static linking into an MIT-licensed app; the TagLib sources here are unmodified.
- **Used for:** DJ mode's opt-in writing of rekordbox data into standard tags (`Sources/TagLibBridge/AmpXTagFile.mm`).

## What is included

Copied by `scripts/vendor-taglib.sh <extracted source dir>`, which replaces this folder:

- `taglib/toolkit`, `taglib/mpeg` (ID3v1, ID3v2), `taglib/ape` (APE tags inside MPEG files), `taglib/riff` (WAV, AIFF),
  `taglib/flac`, `taglib/mp4`, and from `taglib/ogg` only the Xiph comment and the Ogg page code it needs;
- `tag`, `tagunion`, `tagutils`, `audioproperties`, `taglib_export.h`;
- `3rdparty/utfcpp` headers.

Left out: `fileref.cpp` and every other format (ASF, DSF, DSDIFF, Matroska, MOD/IT/S3M/XM, MPC, Ogg Vorbis/Opus/Speex/FLAC,
Shorten, TrueAudio, WavPack), the bindings, tests and CMake files.

`config.h` and `taglib/taglib_config.h` are hand-written in place of the CMake-generated ones (macOS byte swapping, zlib from
the SDK, linked with `-lz`).

## Build

`Sources/` is a synchronized group, so the `.cpp` files compile into the app target. Header search paths,
`TAGLIB_STATIC=1` and `HAVE_CONFIG_H=1` are set on the app target; `COPYING.*` and this file are excluded from the target's
membership. Without `HAVE_CONFIG_H`, `config.h` is never included and zlib support compiles out silently, so compressed ID3
frames would be kept as opaque frames.

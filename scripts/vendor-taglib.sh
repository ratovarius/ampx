#!/usr/bin/env bash
# Copies the parts of a TagLib 2.x release AmpX uses into Sources/Vendor/TagLib (DJ mode tag writing).
# Usage: scripts/vendor-taglib.sh <extracted taglib-X.Y.Z directory>
# Only sources, headers and template implementations are copied: Sources/ is a synchronized group, so any
# other file type would end up in the app bundle.
set -euo pipefail

src="${1:?usage: vendor-taglib.sh <taglib source dir>}"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$repo/Sources/Vendor/TagLib"

rm -rf "$dest"
mkdir -p "$dest/taglib" "$dest/3rdparty"

# Formats AmpX writes (mp3, wav, aiff, flac, m4a) plus what they depend on: APE tags in MPEG files and
# Xiph comments in FLAC files. FileRef and every other format are left out.
copy_dir() {
    local from="$src/taglib/$1"
    (cd "$from" && find . \( -name '*.cpp' -o -name '*.h' -o -name '*.tcc' \) -print0 \
        | xargs -0 -I{} rsync -R {} "$dest/taglib/$1/")
}
mkdir -p "$dest/taglib"
for dir in toolkit mpeg ape riff flac mp4; do
    mkdir -p "$dest/taglib/$dir"
    copy_dir "$dir"
done
mkdir -p "$dest/taglib/ogg"
for file in oggfile oggpage oggpageheader xiphcomment; do
    cp "$src/taglib/ogg/$file.cpp" "$src/taglib/ogg/$file.h" "$dest/taglib/ogg/"
done
for file in tag tagunion tagutils audioproperties; do
    cp "$src/taglib/$file.cpp" "$src/taglib/$file.h" "$dest/taglib/"
done
cp "$src/taglib/taglib_export.h" "$dest/taglib/"
cp -R "$src/3rdparty/utfcpp" "$dest/3rdparty/"
find "$dest/3rdparty" -type f ! \( -name '*.h' \) -delete
find "$dest/3rdparty" -type d -empty -delete

cat > "$dest/config.h" <<'CONFIG'
/* Hand-written for AmpX in place of TagLib's CMake-generated config.h (macOS, zlib from the SDK). */
#ifndef TAGLIB_CONFIG_H
#define TAGLIB_CONFIG_H
#define HAVE_MAC_BYTESWAP 1
#define HAVE_ZLIB 1
#endif
CONFIG

cat > "$dest/taglib/taglib_config.h" <<'CONFIG'
/* Hand-written for AmpX in place of TagLib's CMake-generated taglib_config.h. */
#ifndef TAGLIB_TAGLIB_CONFIG_H
#define TAGLIB_TAGLIB_CONFIG_H
#define TAGLIB_WITH_APE 1
#define TAGLIB_WITH_MP4 1
#define TAGLIB_WITH_RIFF 1
#endif
CONFIG

cp "$src/COPYING.LGPL" "$src/COPYING.MPL" "$dest/"
echo "Vendored $(find "$dest" -name '*.cpp' | wc -l | tr -d ' ') sources into $dest"

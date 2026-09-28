"""Generate the tagged and untagged audio fixtures used by the music library tests.

Encoding uses the system `afconvert` (FLAC, AIFF, M4A) and `lameenc` (MP3); tags are written
with `mutagen`. No FFmpeg, so CI can generate them on a stock macOS runner.
"""

from __future__ import annotations

import json
import math
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

import lameenc
from mutagen.aiff import AIFF
from mutagen.flac import FLAC
from mutagen.id3 import COMM, ID3, TALB, TBPM, TCON, TDRC, TIT2, TKEY, TPE1, TPE2, TRCK
from mutagen.mp4 import MP4, MP4FreeForm
from mutagen.wave import WAVE

SAMPLE_RATE = 44100
CHANNELS = 2
DURATION_SECONDS = 2
FREQUENCY = 440

TAGS = {
    "title": "Library Song",
    "artist": "Library Artist",
    "album": "Library Album",
    "albumArtist": "Album Artist",
    "genre": "Techno",
    "year": 2024,
    "trackNumber": 3,
    "trackTotal": 12,
    "bpm": 130,
    "musicalKey": "Am",
    "comment": "Library fixture",
}


def sine_pcm() -> bytes:
    """Interleaved 16-bit little-endian stereo PCM of a 440 Hz sine at half scale."""
    frames = SAMPLE_RATE * DURATION_SECONDS
    samples = []
    for index in range(frames):
        value = int(16383 * math.sin(2 * math.pi * FREQUENCY * index / SAMPLE_RATE))
        samples.extend((value, value))
    return struct.pack(f"<{len(samples)}h", *samples)


def write_wav(path: Path, pcm: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(CHANNELS)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE)
        wav_file.writeframes(pcm)


def write_mp3(path: Path, pcm: bytes) -> None:
    encoder = lameenc.Encoder()
    encoder.set_bit_rate(192)
    encoder.set_in_sample_rate(SAMPLE_RATE)
    encoder.set_channels(CHANNELS)
    encoder.set_quality(2)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(encoder.encode(pcm) + encoder.flush()))


def afconvert(source: Path, destination: Path, file_format: str, data_format: str) -> None:
    subprocess.run(
        ["afconvert", "-f", file_format, "-d", data_format, str(source), str(destination)],
        check=True,
    )


def id3_frames(*, title: bool = True, artist: bool = True, full: bool = True) -> ID3:
    tags = ID3()
    if title:
        tags.add(TIT2(encoding=3, text=TAGS["title"]))
    if artist:
        tags.add(TPE1(encoding=3, text=TAGS["artist"]))
    if full:
        tags.add(TALB(encoding=3, text=TAGS["album"]))
        tags.add(TPE2(encoding=3, text=TAGS["albumArtist"]))
        tags.add(TCON(encoding=3, text=TAGS["genre"]))
        # Converted to TYER by save_id3/tag_id3_file for ID3v2.3; stays TDRC for ID3v2.4.
        tags.add(TDRC(encoding=3, text=str(TAGS["year"])))
        tags.add(TRCK(encoding=3, text=f"{TAGS['trackNumber']}/{TAGS['trackTotal']}"))
        tags.add(TBPM(encoding=3, text=str(TAGS["bpm"])))
        tags.add(TKEY(encoding=3, text=TAGS["musicalKey"]))
        tags.add(COMM(encoding=3, lang="eng", desc="", text=TAGS["comment"]))
    return tags


def save_id3(tags: ID3, path: Path, version: int) -> None:
    # mutagen keeps v2.4 frames (TDRC) in a v2.3 tag unless converted first; real v2.3 files carry TYER.
    if version == 3:
        tags.update_to_v23()
    tags.save(str(path), v2_version=version)


def tag_id3_file(tagged: WAVE | AIFF, version: int) -> None:
    tagged.add_tags()
    for frame in id3_frames().values():
        tagged.tags.add(frame)
    if version == 3:
        tagged.tags.update_to_v23()
    tagged.save(v2_version=version)


def tag_flac(path: Path) -> None:
    flac = FLAC(str(path))
    flac["TITLE"] = TAGS["title"]
    flac["ARTIST"] = TAGS["artist"]
    flac["ALBUM"] = TAGS["album"]
    flac["ALBUMARTIST"] = TAGS["albumArtist"]
    flac["GENRE"] = TAGS["genre"]
    flac["DATE"] = str(TAGS["year"])
    flac["TRACKNUMBER"] = str(TAGS["trackNumber"])
    flac["TRACKTOTAL"] = str(TAGS["trackTotal"])
    flac["BPM"] = str(TAGS["bpm"])
    flac["INITIALKEY"] = TAGS["musicalKey"]
    flac["COMMENT"] = TAGS["comment"]
    flac.save()


def tag_m4a(path: Path) -> None:
    mp4 = MP4(str(path))
    mp4["\xa9nam"] = [TAGS["title"]]
    mp4["\xa9ART"] = [TAGS["artist"]]
    mp4["\xa9alb"] = [TAGS["album"]]
    mp4["aART"] = [TAGS["albumArtist"]]
    mp4["\xa9gen"] = [TAGS["genre"]]
    mp4["\xa9day"] = [str(TAGS["year"])]
    mp4["trkn"] = [(TAGS["trackNumber"], TAGS["trackTotal"])]
    mp4["tmpo"] = [TAGS["bpm"]]
    mp4["\xa9cmt"] = [TAGS["comment"]]
    mp4["----:com.apple.iTunes:initialkey"] = [MP4FreeForm(TAGS["musicalKey"].encode("utf-8"))]
    mp4.save()


def write_library_fixtures(fixtures_dir: Path) -> Path:
    """Write every library fixture plus manifest.json under `fixtures_dir / "Library"`."""
    root = fixtures_dir / "Library"
    root.mkdir(parents=True, exist_ok=True)
    pcm = sine_pcm()
    manifest: dict[str, dict[str, object]] = {}

    def record(name: str, container: str, expected: dict[str, object]) -> None:
        manifest[name] = {"container": container, "expected": expected, "size": (root / name).stat().st_size}

    for name, version, container in (
        ("tagged-v23.mp3", 3, "mp3-id3v2.3"),
        ("tagged-v24.mp3", 4, "mp3-id3v2.4"),
    ):
        write_mp3(root / name, pcm)
        save_id3(id3_frames(), root / name, version)
        record(name, container, TAGS)

    for name, title, artist in (("title-only.mp3", True, False), ("artist-only.mp3", False, True)):
        write_mp3(root / name, pcm)
        save_id3(id3_frames(title=title, artist=artist, full=False), root / name, 3)
        expected = {"title": TAGS["title"]} if title else {"artist": TAGS["artist"]}
        record(name, "mp3-id3v2.3", expected)

    for name in ("untagged/Library Artist - Library Song.mp3", "untagged/Library Song.mp3"):
        write_mp3(root / name, pcm)
        record(name, "mp3-untagged", {})

    write_wav(root / "tagged.wav", pcm)
    tag_id3_file(WAVE(str(root / "tagged.wav")), 3)
    record("tagged.wav", "wav-id3v2.3", TAGS)

    with tempfile.TemporaryDirectory() as scratch:
        base = Path(scratch) / "base.wav"
        write_wav(base, pcm)

        afconvert(base, root / "tagged.flac", "flac", "flac")
        tag_flac(root / "tagged.flac")
        record("tagged.flac", "flac-vorbis", TAGS)

        afconvert(base, root / "tagged.aiff", "AIFF", "BEI16")
        tag_id3_file(AIFF(str(root / "tagged.aiff")), 3)
        record("tagged.aiff", "aiff-id3v2.3", TAGS)

        afconvert(base, root / "tagged.m4a", "m4af", "aac")
        tag_m4a(root / "tagged.m4a")
        record("tagged.m4a", "m4a-itunes", TAGS)

    (root / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return root

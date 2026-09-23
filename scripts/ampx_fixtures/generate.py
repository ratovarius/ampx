"""Generate binary test fixtures consumed by AmpXTests."""

from __future__ import annotations

import struct
import wave
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES_DIR = REPO_ROOT / "Tests" / "Fixtures"


def write_short_wav(path: Path, *, sample_rate: int = 44100, duration_seconds: float = 0.1) -> None:
    """Write a minimal mono 16-bit PCM WAV file."""
    frame_count = int(sample_rate * duration_seconds)
    path.parent.mkdir(parents=True, exist_ok=True)

    with wave.open(str(path), "w") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(struct.pack("<" + "h" * frame_count, *([0] * frame_count)))


def write_sample_m3u(path: Path) -> None:
    """Write the bundled M3U parser fixture referenced by AmpXTests resources."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "#EXTM3U\n"
        "# comment line\n"
        "\n"
        "relative-track.wav\n"
        "/absolute/track.mp3\n"
        "file:///tmp/absolute.flac\n"
        "unsupported.ogg\n",
        encoding="utf-8",
    )


def main() -> None:
    write_short_wav(FIXTURES_DIR / "short.wav")
    print(f"Wrote {FIXTURES_DIR / 'short.wav'}")
    write_sample_m3u(FIXTURES_DIR / "sample.m3u")
    print(f"Wrote {FIXTURES_DIR / 'sample.m3u'}")


if __name__ == "__main__":
    main()

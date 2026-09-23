"""Generate RobotoMono-SemiBold.ttf from the official v3.001 variable font."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

REPO = "https://github.com/googlefonts/RobotoMono.git"
TAG = "v3.001"
VARIABLE_REL = "fonts/variable/RobotoMono[wght].ttf"
WEIGHT = 600
POSTSCRIPT_NAME = "RobotoMono-SemiBold"


def fetch_variable_font(dest: Path) -> Path:
    with tempfile.TemporaryDirectory(prefix="robotomono-") as tmp:
        repo = Path(tmp) / "RobotoMono"
        subprocess.run(
            ["git", "clone", "--depth", "1", "--branch", TAG, REPO, str(repo)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        source = repo / VARIABLE_REL
        if not source.is_file():
            raise FileNotFoundError(f"Expected variable font at {VARIABLE_REL} in {REPO}@{TAG}")
        shutil.copy2(source, dest)
        return dest


def patch_names(font: TTFont) -> None:
    name = font["name"]
    family = "Roboto Mono SemiBold"
    subfamily = "SemiBold"
    full_name = "Roboto Mono SemiBold"

    for record in name.names:
        if record.nameID == 1:
            record.string = family
        elif record.nameID == 2:
            record.string = subfamily
        elif record.nameID == 4:
            record.string = full_name
        elif record.nameID == 6:
            record.string = POSTSCRIPT_NAME
        elif record.nameID == 17:
            record.string = subfamily

    font["OS/2"].usWeightClass = WEIGHT


def generate(source: Path, output: Path) -> None:
    variable = TTFont(source)
    instance = instantiateVariableFont(variable, {"wght": WEIGHT})
    patch_names(instance)
    output.parent.mkdir(parents=True, exist_ok=True)
    instance.save(output)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--variable-font",
        type=Path,
        help="Path to RobotoMono[wght].ttf (default: fetch from googlefonts/RobotoMono v3.001)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "Resources" / "Fonts" / "RobotoMono-SemiBold.ttf",
        help="Output path for RobotoMono-SemiBold.ttf",
    )
    args = parser.parse_args(argv)

    if args.variable_font:
        source = args.variable_font
    else:
        with tempfile.NamedTemporaryFile(suffix=".ttf", delete=False) as tmp:
            source = fetch_variable_font(Path(tmp.name))

    generate(source, args.output)
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

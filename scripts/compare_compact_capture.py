"""Export native captures and a labeled reference/result/overlay review sheet."""
import argparse
from pathlib import Path
import shutil

from PIL import Image, ImageDraw


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("captures", type=Path)
    parser.add_argument("reference", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--module", default="player", choices=["player", "equalizer", "playlist"])
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for scale in (1, 2, 3):
        name = f"compact-{args.module}-{scale}x.png"
        shutil.copyfile(args.captures / name, args.output / name)
    result = Image.open(args.output / f"compact-{args.module}-2x.png").convert("RGB")
    reference = Image.open(args.reference).convert("RGB")
    assert reference.size == result.size
    overlay = Image.blend(reference, result, 0.5)
    overlay.save(args.output / f"{args.module}-overlay-2x.png")
    sheet = Image.new("RGB", (result.width + 32, (result.height + 36) * 3 + 16), "#eeeeee")
    draw = ImageDraw.Draw(sheet)
    for index, (title, image) in enumerate([
        ("Reference — normalized to 490 pt at 2x", reference),
        (f"Implemented {args.module.title()} - approved compact shell", result),
        ("50% overlay", overlay),
    ]):
        y = 16 + index * (result.height + 36)
        draw.text((16, y), title, fill="#222222")
        sheet.paste(image, (16, y + 20))
    sheet.save(args.output / f"{args.module}-comparison.png")


if __name__ == "__main__":
    main()

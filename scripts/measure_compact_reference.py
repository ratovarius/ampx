"""Preserve inspectable source-pixel measurements for the compact module artwork."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

CROPS = {
    "player": (28, 276, 1361, 84),
    "equalizer": (28, 557, 1361, 84),
    "playlist": (28, 832, 1361, 76),
}
PLAYER = {
    "inner_frame": (35, 283, 1347, 70),
    "grip_glyph": (53, 303, 43, 38),
    "wordmark": (123, 306, 97, 35),
    "brand_separator": (254, 302, 6, 38),
    "well": (276, 292, 512, 56),
    "visualizer": (292, 302, 279, 38),
    "timer_cell": (617, 298, 150, 46),
    "timer_ink": (636, 303, 126, 35),
    "transport_separator": (796, 287, 6, 65),
    "previous": (814, 291, 64, 58),
    "play": (885, 291, 63, 58),
    "pause": (956, 291, 62, 58),
    "stop": (1026, 291, 63, 58),
    "next": (1097, 291, 64, 58),
    "previous_glyph": (834, 308, 23, 25),
    "play_glyph": (907, 308, 22, 25),
    "pause_glyph": (978, 310, 19, 22),
    "stop_glyph": (1047, 311, 20, 20),
    "next_glyph": (1117, 308, 24, 25),
    "chrome_separator": (1175, 285, 7, 69),
    "minimize": (1200, 294, 50, 51),
    "expand": (1263, 294, 51, 51),
    "close": (1325, 294, 50, 51),
}
EQUALIZER = {
    "volume_track": (285, 591, 422, 22),
    "volume_thumb": (551, 581, 45, 42),
    "middle_separator": (728, 582, 7, 38),
    "balance_track": (757, 591, 399, 22),
    "balance_thumb": (999, 581, 50, 42),
    "balance_first_segment": (762, 597, 21, 12),
    "balance_second_segment": (788, 597, 21, 12),
    "corrected_balance_track": (757, 591, 465, 22),
}
PLAYLIST = {
    "well": (262, 846, 859, 49),
    "list_options": (1133, 845, 51, 49),
    "corrected_well": (262, 846, 923, 49),
    "corrected_list_options": (1197, 845, 51, 49),
    "corrected_chrome_separator": (1250, 841, 7, 61),
}


def logical_rect(rect, crop):
    x, y, width, height = rect
    cx, cy, crop_width, _ = crop
    factor = 490 / crop_width
    return [(x - cx) * factor, (y - cy) * factor, width * factor, height * factor]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    image = Image.open(args.source).convert("RGB")
    args.output.mkdir(parents=True, exist_ok=True)
    data = {
        "source": str(args.source),
        "sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
        "size": image.size,
        "normalization": "uniform 490 / 1361, preserve aspect ratio; PNG heights rounded only at raster export",
        "uncertainty": "Manual edge measurements ±1–2 source px; outer crops exclude drop shadow. EQ/Playlist minimize is rejected artwork.",
        "crops": {},
        "player": {},
        "equalizer": {},
        "playlist": {},
        "sample_colors": {},
    }
    for name, crop in CROPS.items():
        x, y, w, h = crop
        panel = image.crop((x, y, x + w, y + h))
        panel.save(args.output / f"{name}-source.png")
        panel.resize((980, round(h * 980 / w)), Image.Resampling.LANCZOS).save(args.output / f"{name}-reference-2x.png")
        data["crops"][name] = {"source_rect": crop, "logical_size": [490, h * 490 / w]}
    annotated = image.copy()
    draw = ImageDraw.Draw(annotated)
    for name, rect in PLAYER.items():
        x, y, w, h = rect
        draw.rectangle((x, y, x + w - 1, y + h - 1), outline="#ff4466", width=1)
        data["player"][name] = {"source_rect": rect, "logical_rect": logical_rect(rect, CROPS["player"])}
    annotated.crop((20, 270, 1400, 365)).save(args.output / "player-annotated.png")
    for name, rect in EQUALIZER.items():
        data["equalizer"][name] = {"source_rect": rect, "logical_rect": logical_rect(rect, CROPS["equalizer"])}
        x, y, w, h = rect
        draw.rectangle((x, y, x + w - 1, y + h - 1), outline="#ff4466", width=1)
    data["equalizer"]["correction"] = "Omit minimize; extend balance track by 66 source px. Segment pitch 26 px, width 21 px. Thumb travel keeps its face inside the track."
    annotated.crop((20, 550, 1400, 645)).save(args.output / "equalizer-annotated.png")
    for name, rect in PLAYLIST.items():
        data["playlist"][name] = {"source_rect": rect, "logical_rect": logical_rect(rect, CROPS["playlist"])}
        x, y, w, h = rect
        draw.rectangle((x, y, x + w - 1, y + h - 1), outline="#ff4466", width=1)
    data["playlist"]["correction"] = "Omit minimize; shift List Options and extend well by 64 source px. Center common chrome in the shorter 76 px strip. Extra Playlist width extends only the well."
    annotated.crop((20, 825, 1400, 915)).save(args.output / "playlist-annotated.png")
    for name, point in {"panel": (400, 287), "well": (600, 320), "bevel_highlight": (910, 294), "bevel_face": (900, 322),
                        "brand": (148, 320), "spectrum_green": (298, 336), "timer_green": (641, 320)}.items():
        data["sample_colors"][name] = {"source_point": point, "rgb": image.getpixel(point)}
    (args.output / "measurements.json").write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps({"sha256": data["sha256"], "crops": data["crops"]}, indent=2))


if __name__ == "__main__":
    main()

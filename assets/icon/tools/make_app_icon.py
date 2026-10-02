#!/usr/bin/env python3
"""Turns assets/icon/source.png into the app icon.

The source is a rounded tile on a white square. The tile is cut out with
transparent corners and placed on Apple's icon grid (824pt tile on 1024).

Needs pillow:  uv run --with pillow make_app_icon.py
Writes Resources/AppIcon.icns. The menu bar icon comes from make_menubar_icon.py.
"""

import os
import subprocess
import tempfile

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..")
SOURCE = os.path.join(HERE, "..", "source.png")
RESOURCES = os.path.join(ROOT, "Resources")

TILE_BOX = (40, 40, 1214, 1214)  # where the tile sits in source.png
TILE, RADIUS, INSET = 824, 185, 3  # inset drops the white anti-aliased fringe


def tile():
    im = Image.open(SOURCE).convert("RGBA").crop(TILE_BOX).resize((TILE, TILE), Image.LANCZOS)
    big = 4  # draw the mask large, then shrink, for smooth corners
    mask = Image.new("L", (TILE * big, TILE * big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (INSET * big, INSET * big, (TILE - INSET) * big, (TILE - INSET) * big), RADIUS * big, fill=255)
    im.putalpha(mask.resize((TILE, TILE), Image.LANCZOS))
    return im


def app_icon(t):
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    canvas.alpha_composite(t, (100, 100))
    return canvas


if __name__ == "__main__":
    t = tile()
    icon = app_icon(t)
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.mkdir(iconset)
        for pt in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px = pt * scale
                name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
                icon.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(RESOURCES, "AppIcon.icns")], check=True)
    print("wrote AppIcon.icns")

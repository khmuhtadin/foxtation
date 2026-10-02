#!/usr/bin/env python3
"""Cleans the generated fox pose PNGs for the HUD.

Removes the stray speckles around the fox (keeps only the shape connected to
the body), makes the body fully opaque, trims, and saves 512px squares into
Resources/Fox/ for the app.

Usage (from assets/mascot):
    uv run --with pillow tools/clean_poses.py emerge-wave=source/emerge-wave.png fly-out=source/fly-out.png \
        fly-back=source/fly-back.png swing-in=source/swing-in.png dash=source/dash.png face=source/face.png
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "Resources", "Fox")
SIZE = 512


def clean(path):
    im = Image.open(path).convert("RGBA")
    alpha = im.getchannel("A")
    solid = alpha.point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MaxFilter(5))
    # Seed the fill on the most central opaque pixel; everything not connected is a speckle.
    w, h = solid.size
    seed = min(((x, y) for y in range(0, h, 8) for x in range(0, w, 8) if solid.getpixel((x, y)) == 255),
               key=lambda p: (p[0] - w / 2) ** 2 + (p[1] - h / 2) ** 2)
    ImageDraw.floodfill(solid, seed, 128)
    keep = solid.point(lambda v: 255 if v == 128 else 0)
    alpha = Image.composite(alpha.point(lambda v: 255 if v >= 224 else v), Image.new("L", im.size, 0), keep)
    im.putalpha(alpha)
    im = im.crop(alpha.getbbox())
    side = max(im.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
    return square.resize((SIZE, SIZE), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for arg in sys.argv[1:]:
        name, path = arg.split("=", 1)
        clean(path).save(os.path.join(OUT, f"{name}.png"))
        print("wrote", name)

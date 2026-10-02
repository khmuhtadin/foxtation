#!/usr/bin/env python3
"""Menu bar template icon: the fox silhouette from source.png with the eyes,
nose and waveform mark cut out. macOS tints template images to match the bar.

Needs pillow:  uv run --with pillow make_menubar_icon.py
Writes Resources/MenuBarIcon.png (64px; shown at 18pt).
"""

import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "..", "source.png")
OUT = os.path.join(HERE, "..", "..", "..", "Resources", "MenuBarIcon.png")

BG = (206, 226, 253)  # the icon's ice-blue tile
FOX_SEED = (627, 900)  # a pixel on the fox's white fur

im = Image.open(SOURCE).convert("RGB")
src = im.load()
fox = Image.new("L", im.size, 0)
holes = Image.new("L", im.size, 0)
f, h = fox.load(), holes.load()
for y in range(im.height):
    for x in range(im.width):
        r, g, b = src[x, y]
        if abs(r - BG[0]) + abs(g - BG[1]) + abs(b - BG[2]) > 28:
            f[x, y] = 255
        if r + g + b < 330 or (b - r > 90 and r < 160):  # eyes/nose, waveform
            h[x, y] = 255

fox = fox.filter(ImageFilter.MedianFilter(5))
# Keep only the fox: the region connected to the fur seed, not the white corners.
ImageDraw.floodfill(fox, FOX_SEED, 128)
fox = fox.point(lambda v: 255 if v == 128 else 0)
alpha = Image.composite(Image.new("L", im.size, 0), fox, holes)

bbox = fox.getbbox()
alpha = alpha.crop(bbox)
side = max(alpha.size)
square = Image.new("L", (side, side), 0)
square.paste(alpha, ((side - alpha.width) // 2, (side - alpha.height) // 2))
out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
out.putalpha(square)
out.resize((64, 64), Image.LANCZOS).save(OUT)
print("wrote", OUT)

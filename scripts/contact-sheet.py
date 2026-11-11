"""Puts screenshots side by side, labelled, in one image: contact-sheet.py out.png shot.png...  (needs Pillow)"""
import sys
from PIL import Image, ImageDraw

out, paths = sys.argv[1], sys.argv[2:]
h = 900
tiles = []
for p in paths:
    im = Image.open(p).convert("RGB")
    im = im.resize((round(im.width * h / im.height), h))
    ImageDraw.Draw(im).text((10, 10), p.rsplit("/", 1)[-1], fill=(255, 0, 0))
    tiles.append(im)
cols = 4 if tiles[0].width < tiles[0].height else 2
rows = (len(tiles) + cols - 1) // cols
w = max(t.width for t in tiles)
sheet = Image.new("RGB", (cols * w, rows * h), "white")
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % cols) * w, (i // cols) * h))
sheet.save(out)

"""Makes the iOS app icon (1024 x 1024, no transparency) from the Android repo's tools/icon-source.png.

The source is a violet rounded square on white. iOS masks its own rounded shape, so the icon is the
square's inside, cropped in from its edges so neither the white margin nor the source's own rounded
corners ever show.

    python tools/make_icon.py C:/dev/Talis-Notes/tools/icon-source.png
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

src = Image.open(sys.argv[1] if len(sys.argv) > 1 else "C:/dev/Talis-Notes/tools/icon-source.png").convert("RGB")
a = np.asarray(src).astype(int)
violet = a.min(2) < 235
ys, xs = np.where(violet)
x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
side = min(x1 - x0, y1 - y0)
inset = side * 0.075  # past the rounded corners
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
half = side / 2 - inset
box = (int(cx - half), int(cy - half), int(cx + half), int(cy + half))
icon = src.crop(box).resize((1024, 1024), Image.LANCZOS)
out = Path(__file__).resolve().parent.parent / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"
out.parent.mkdir(parents=True, exist_ok=True)
icon.save(out)
print("wrote", out, box)

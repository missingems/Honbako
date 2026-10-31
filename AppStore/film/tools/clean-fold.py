"""Removes the faint vertical shading the iPhone Duo simulator draws along the fold in inner-display
screenshots. The app draws nothing there; the simulator darkens a few columns either side of the
centre by 1-2%. Each pixel near the centre is replaced by the blend of the columns just outside the
band, but only where it is already close to that blend, so real content on the fold (a manga
spread's gutter, a photo) is left alone.

usage: python3 tools/clean-fold.py image.jpg [image.jpg ...]   (rewrites each file in place)
"""
import sys

import numpy as np
from PIL import Image

BAND = 8          # columns either side of the centre
TOLERANCE = 14    # max difference from the blend, per channel, that counts as shading

for path in sys.argv[1:]:
    img = Image.open(path).convert('RGB')
    a = np.asarray(img).astype(np.int16)
    h, w, _ = a.shape
    c = w // 2
    left, right = a[:, c - BAND - 1], a[:, c + BAND]
    changed = 0
    for x in range(c - BAND, c + BAND):
        u = (x - (c - BAND - 1)) / (2 * BAND + 1)
        blend = np.rint(left * (1 - u) + right * u).astype(np.int16)
        close = np.all(np.abs(a[:, x] - blend) <= TOLERANCE, axis=1)
        a[close, x] = blend[close]
        changed += int(close.sum())
    Image.fromarray(a.astype(np.uint8)).save(path, quality=95, subsampling=0)
    print(f'{path.split("/")[-1]}: {changed} pixels cleaned')

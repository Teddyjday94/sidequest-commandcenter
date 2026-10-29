#!/usr/bin/env python3
"""Elsewhere Supply Co.: turn a generated artwork image into a Printify-ready print file.

    python3 prep_print.py in.png out.png --width-in 11 [--bg auto|none|#hex] [--tolerance 38]

1. Knocks out the flat background the art was generated on (prompts ask for a plain solid color).
   It flood-fills from the image border only, so the same color inside the art (a black outline,
   white teeth) stays. --bg none keeps everything (art meant to print as a full rectangle).
2. Trims to the artwork and pads it a little.
3. Scales to the print width at 300 DPI with Lanczos and writes an RGBA PNG.
Prints JSON: size in px and inches, effective source DPI (what the original pixels really give at that
width), and warnings. Under 150 effective DPI the print will look soft: generate at a higher resolution.
"""
import argparse
import json
from collections import deque

import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument('src')
ap.add_argument('dst')
ap.add_argument('--width-in', type=float, default=11.0)
ap.add_argument('--bg', default='auto')
ap.add_argument('--tolerance', type=float, default=38.0)
a = ap.parse_args()

im = Image.open(a.src).convert('RGBA')
px = np.asarray(im).astype(np.int16)
h, w = px.shape[:2]
warnings = []

if a.bg != 'none':
    if a.bg == 'auto':
        border = np.concatenate([px[0, :, :3], px[-1, :, :3], px[:, 0, :3], px[:, -1, :3]])
        bg = np.median(border, axis=0)
        spread = np.abs(border - bg).max(axis=1)
        if (spread > a.tolerance).mean() > 0.2:
            warnings.append('Background is not one flat color; knock-out may be rough. Regenerate on a plain solid background.')
    else:
        hx = a.bg.lstrip('#')
        bg = np.array([int(hx[i:i + 2], 16) for i in (0, 2, 4)])
    near = np.sqrt(((px[:, :, :3] - bg) ** 2).sum(axis=2)) <= a.tolerance
    # Flood fill from the border through background-colored pixels only.
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if near[y, x] and not seen[y, x]:
                seen[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if near[y, x] and not seen[y, x]:
                seen[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True; q.append((ny, nx))
    out = np.asarray(im).copy()
    out[seen, 3] = 0
    # Soften the cut edge: pixels touching the knocked-out area that are close to the background color
    # get partial transparency, so no halo of background color prints around the art.
    dist = np.sqrt(((px[:, :, :3] - bg) ** 2).sum(axis=2))
    edge = np.zeros((h, w), bool)
    edge[1:, :] |= seen[:-1, :]; edge[:-1, :] |= seen[1:, :]; edge[:, 1:] |= seen[:, :-1]; edge[:, :-1] |= seen[:, 1:]
    edge &= ~seen
    soft = edge & (dist < a.tolerance * 2.5)
    out[soft, 3] = (np.clip(dist[soft] / (a.tolerance * 2.5), 0, 1) * 255).astype(np.uint8)
    im = Image.fromarray(out, 'RGBA')

box = im.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
if not box:
    raise SystemExit('Nothing left after removing the background.')
im = im.crop(box)
pad = max(4, int(max(im.size) * 0.01))
canvas = Image.new('RGBA', (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0, 0))
canvas.alpha_composite(im, (pad, pad))
src_w = canvas.width
target_w = int(round(a.width_in * 300))
target_h = int(round(canvas.height * target_w / canvas.width))
final = canvas.resize((target_w, target_h), Image.LANCZOS)
final.save(a.dst, dpi=(300, 300), optimize=True)
eff = round(src_w / a.width_in)
if eff < 150:
    warnings.append(f'Only {eff} real DPI at {a.width_in} in wide: it will print soft. Use a 4K or vector model, or print smaller.')
print(json.dumps({'file': a.dst, 'px': [target_w, target_h], 'inches': [a.width_in, round(target_h / 300, 2)], 'source_dpi': eff, 'warnings': warnings}))

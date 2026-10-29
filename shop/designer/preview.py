#!/usr/bin/env python3
"""Quick look at a design on garment colors: python3 preview.py out_dir name [light_hex dark_hex] -> name-preview.png"""
import sys
from PIL import Image

out, name = sys.argv[1], sys.argv[2]
light = sys.argv[3] if len(sys.argv) > 3 else '#e9e1cf'
dark = sys.argv[4] if len(sys.argv) > 4 else '#262626'
tiles = []
for ink, bg in (('dark-ink', light), ('light-ink', dark)):
    art = Image.open(f'{out}/{name}-{ink}.png').convert('RGBA')
    art.thumbnail((900, 900), Image.LANCZOS)
    tile = Image.new('RGBA', (1000, 1000), bg)
    tile.alpha_composite(art, ((1000 - art.width) // 2, (1000 - art.height) // 2))
    tiles.append(tile)
sheet = Image.new('RGBA', (2000, 1000))
sheet.paste(tiles[0], (0, 0)); sheet.paste(tiles[1], (1000, 0))
sheet.convert('RGB').save(f'{out}/{name}-preview.png')
print(f'{out}/{name}-preview.png')

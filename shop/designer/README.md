# Elsewhere design renderer

Print-ready shirt artwork for Elsewhere Supply Co., made from real fonts instead of AI image generation (AI tools still garble lettering).

```
node render.js designs/<name>.html out/      # 300 DPI transparent PNGs: <name>-dark-ink.png, <name>-light-ink.png
python3 preview.py out/ <name>               # both inks on garment colors, for a quick look
```

A design file draws inside `#art` with 100 CSS px = 1 inch and colors every mark with `var(--ink)`. Rules for print: one ink color, no opacity or gradients (DTG turns them into speckle), no element outside `#art` (the renderer refuses to save a design that spills), fonts from Google Fonts only.

Finished files go to `shop/idea-board/designs/` (PNG plus a 700px webp thumbnail), get published as files of the Idea Board artifact, and are linked to their idea with `ops.shop_ideas.design_slug` and `print_note`.

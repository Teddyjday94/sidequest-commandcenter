#!/usr/bin/env python3
"""Sidequest site kit: turn one spec JSON into a finished, mobile-first website.

    python3 render.py spec.json out_dir

The agent writes only the spec (real facts from the case file and lead row, plus short copy).
Layout, palette, type, icons, illustrations and responsive behavior all come from here, so
every mockup and client site starts from the same tested design. Standard library only.

package "mockup"  -> one page, yellow concept ribbon, noindex, the form says nothing was sent.
package "starter" -> one page client site, LocalBusiness schema, working form if form_email is set.
package "full"    -> index, services, about and contact pages with shared nav.
See kit/README.md for every spec field.
"""
import hashlib
import html
import json
import os
import re
import sys

# ---------------------------------------------------------------------------------------------
# Design tokens

FONTS = {
    # name: (google css2 families, display stack, body stack)
    'archivo': ('family=Archivo+Black&family=Public+Sans:wght@400;600;700', '"Archivo Black", Impact, sans-serif', '"Public Sans", system-ui, sans-serif'),
    'bricolage': ('family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Figtree:wght@400;600;700', '"Bricolage Grotesque", system-ui, sans-serif', '"Figtree", system-ui, sans-serif'),
    'fraunces': ('family=Fraunces:opsz,wght@9..144,700;9..144,800&family=Work+Sans:wght@400;600;700', '"Fraunces", Georgia, serif', '"Work Sans", system-ui, sans-serif'),
    'oswald': ('family=Oswald:wght@600;700&family=Source+Sans+3:wght@400;600;700', '"Oswald", "Arial Narrow", sans-serif', '"Source Sans 3", system-ui, sans-serif'),
    'sora': ('family=Sora:wght@700;800&family=Nunito+Sans:wght@400;600;700', '"Sora", system-ui, sans-serif', '"Nunito Sans", system-ui, sans-serif'),
    'barlow': ('family=Barlow+Condensed:wght@700;800&family=Barlow:wght@400;600;700', '"Barlow Condensed", "Arial Narrow", sans-serif', '"Barlow", system-ui, sans-serif'),
}

# brand, accent, ink, paper, panel
PALETTES = {
    'pressure': [('#0f3d63', '#2bb3e6', '#0d1b26', '#f6f9fb', '#e9f1f6'), ('#114b5f', '#f4a259', '#10202a', '#fbfaf7', '#f0ede6'),
                 ('#1f2a36', '#4fd1c5', '#121821', '#f7f8fa', '#eceff3'), ('#0b5394', '#ffcc33', '#0f1c2b', '#f8fafc', '#eaf0f6')],
    'lawn': [('#1f5130', '#a3d65c', '#132219', '#f7f8f2', '#ecefe2'), ('#2f4a1f', '#f2b134', '#1a2414', '#faf8f1', '#efeadb'),
             ('#245c3b', '#e8613c', '#142519', '#f6f7f3', '#e9ede4'), ('#3d5a1e', '#6cc4a1', '#1b2412', '#f8f9f3', '#edf0e3')],
    'window': [('#164e7a', '#7cc6f0', '#0f1f2c', '#f7fafc', '#eaf2f8'), ('#2d3a4a', '#f0b429', '#18202a', '#fafaf8', '#eeede8')],
    'cleaning': [('#255f85', '#58c4b6', '#11222e', '#f7fbfb', '#e6f2f1'), ('#5b3f8c', '#f2a65a', '#1d1528', '#faf8fc', '#efeaf5')],
    'painting': [('#8c2f39', '#f2c14e', '#231417', '#fbf8f4', '#f1ebe3'), ('#264653', '#e76f51', '#14232a', '#f9f7f3', '#ece8df')],
    'handyman': [('#2b3a42', '#f29e4c', '#151c20', '#f8f7f4', '#ecebe5'), ('#7a3e1d', '#3fa7d6', '#1f140e', '#faf7f3', '#eee8df')],
    'other': [('#1e3a5f', '#f2a541', '#111c2b', '#f8f8f6', '#ecebe6'), ('#2f4858', '#86bbd8', '#152029', '#f8f9fa', '#e9eef1')],
}

VARIANTS = ['split', 'banner', 'editorial', 'bold']
VARIANT_FONTS = {'split': ['bricolage', 'sora', 'fraunces'], 'banner': ['archivo', 'oswald', 'barlow'],
                 'editorial': ['fraunces', 'bricolage', 'sora'], 'bold': ['oswald', 'barlow', 'archivo']}

ICONS = {
    'house': '<path d="M3 11 12 4l9 7v9h-6v-6H9v6H3z"/>',
    'drive': '<path d="M4 20 9 4h6l5 16M12 7v2M12 12v2M12 17v2"/>',
    'roof': '<path d="M2 13 12 5l10 8M5 11v9h14v-9"/>',
    'deck': '<path d="M3 9h18M3 14h18M3 19h18M6 9v10M18 9v10"/>',
    'store': '<path d="M4 9h16l-1-5H5zM5 9v11h14V9M9 20v-6h6v6"/>',
    'truck': '<path d="M2 7h11v9H2zM13 10h5l3 3v3h-8M6 19a2 2 0 1 0 0-.1M17 19a2 2 0 1 0 0-.1"/>',
    'mower': '<path d="M3 15h13l2-5h3M5 19a2 2 0 1 0 0-.1M15 19a2 2 0 1 0 0-.1M8 15V9h5"/>',
    'leaf': '<path d="M5 19C5 9 12 5 20 4c-1 8-5 15-15 15zM5 19l8-8"/>',
    'tree': '<path d="M12 3 6 12h3l-4 6h14l-4-6h3zM12 18v3"/>',
    'gutter': '<path d="M3 6h18v4H3zM17 10v10M17 20h-4"/>',
    'calendar': '<path d="M4 6h16v14H4zM4 10h16M8 3v4M16 3v4"/>',
    'window': '<path d="M5 4h14v16H5zM12 4v16M5 12h14"/>',
    'drop': '<path d="M12 3c4 5 6 8 6 11a6 6 0 0 1-12 0c0-3 2-6 6-11z"/>',
    'shield': '<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/>',
    'car': '<path d="M3 16v-4l2-5h14l2 5v4zM3 16v3h3v-3M18 16v3h3v-3M7 12h10"/>',
    'brush': '<path d="M4 20c3 0 5-2 5-4l-2-2c-2 0-3 2-3 6zM9 14l9-9 2 2-9 9"/>',
    'wrench': '<path d="M14 6a4 4 0 0 0 5 5l-9 9-3-3 9-9a4 4 0 0 0-2-2z"/>',
    'spark': '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l3 3M15 15l3 3M18 6l-3 3M9 15l-3 3"/>',
    'fence': '<path d="M5 21V7l2-3 2 3v14M15 21V7l2-3 2 3v14M3 11h18M3 17h18"/>',
    'bug': '<path d="M9 8h6v9a3 3 0 0 1-6 0zM12 8V5M8 4l2 2M16 4l-2 2M5 11h4M15 11h4M5 16h4M15 16h4"/>',
    'phone': '<path d="M5 4h4l2 5-3 2a11 11 0 0 0 5 5l2-3 5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"/>',
    'pin': '<path d="M12 21s-7-6-7-11a7 7 0 0 1 14 0c0 5-7 11-7 11zM12 8a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"/>',
    'clock': '<path d="M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM12 7v5l3 2"/>',
    'star': '<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"/>',
    'check': '<path d="M5 12l4 4 10-10"/>',
}

ICON_WORDS = [
    (r'drive|concrete|sidewalk|patio|walk', 'drive'), (r'roof', 'roof'), (r'deck|fence|wood', 'deck'),
    (r'house|home|siding|soft ?wash|exterior', 'house'), (r'commercial|business|storefront|parking', 'store'),
    (r'gutter', 'gutter'), (r'window|glass|screen', 'window'), (r'fleet|truck|equipment', 'truck'),
    (r'mow|cut|lawn', 'mower'), (r'leaf|leaves|cleanup|clean-up|debris', 'leaf'), (r'tree|trim|shrub|hedge|bush', 'tree'),
    (r'landscap|mulch|bed|sod|plant', 'leaf'), (r'paint|stain|cabinet', 'brush'), (r'repair|install|handyman|fix|assembly', 'wrench'),
    (r'clean|maid|janitor|sanit', 'spark'), (r'pest|bug|mosquito', 'bug'), (r'car|auto|detail|boat', 'car'),
    (r'fence', 'fence'), (r'seal|protect|insur', 'shield'), (r'water|wash|rinse|drain', 'drop'), (r'season|monthly|schedul', 'calendar'),
]

NICHES = {
    'pressure washing': 'pressure', 'pressure': 'pressure', 'soft wash': 'pressure', 'lawn care': 'lawn', 'lawn': 'lawn', 'landscaping': 'lawn',
    'window cleaning': 'window', 'window': 'window', 'cleaning': 'cleaning', 'painting': 'painting', 'handyman': 'handyman',
}

# ---------------------------------------------------------------------------------------------
# Helpers

def esc(s):
    return html.escape(str(s), quote=True)


def clean(s):
    """Copy rules: no em or en dashes, no stray whitespace."""
    s = str(s or '').replace('—', ', ').replace('–', '-').replace('‒', '-')
    s = re.sub(r'\s+,', ',', s)
    return re.sub(r'[ \t]+', ' ', s).strip()


def pick(seq, key, salt=''):
    h = int(hashlib.sha1((key + salt).encode()).hexdigest(), 16)
    return seq[h % len(seq)]


def hex_rgb(h):
    h = h.lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lum(h):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = hex_rgb(h)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def shade(h, f):
    r, g, b = hex_rgb(h)
    if f < 0:
        return '#%02x%02x%02x' % tuple(int(c * (1 + f)) for c in (r, g, b))
    return '#%02x%02x%02x' % tuple(int(c + (255 - c) * f) for c in (r, g, b))


def on(color, ink):
    """Text color that reads on a fill: white or the page ink."""
    return '#ffffff' if contrast(color, '#ffffff') >= contrast(color, ink) else ink


def icon(name, cls='ic'):
    return f'<svg class="{cls}" viewBox="0 0 24 24" aria-hidden="true">{ICONS.get(name, ICONS["check"])}</svg>'


def icon_for(text, niche):
    t = text.lower()
    for pat, name in ICON_WORDS:
        if re.search(pat, t):
            return name
    return {'pressure': 'drop', 'lawn': 'leaf', 'window': 'window', 'cleaning': 'spark', 'painting': 'brush', 'handyman': 'wrench'}.get(niche, 'check')


def digits(phone):
    d = re.sub(r'\D', '', phone or '')
    return d[1:] if len(d) == 11 and d.startswith('1') else d

# ---------------------------------------------------------------------------------------------
# Drawn illustrations, used only where the business has no photo yet. Always labeled as samples.

def art_concrete(dirty):
    joints = ''.join(f'<line x1="{x}" y1="0" x2="{x}" y2="400"/>' for x in (200, 400)) + '<line x1="0" y1="200" x2="600" y2="200"/>'
    grime = ('<g opacity=".85"><ellipse cx="140" cy="120" rx="150" ry="90" fill="#5d5a3f" opacity=".55"/><ellipse cx="430" cy="290" rx="200" ry="110" fill="#3f4630" opacity=".6"/>'
             '<ellipse cx="300" cy="60" rx="120" ry="50" fill="#6b5e45" opacity=".45"/><ellipse cx="80" cy="330" rx="110" ry="70" fill="#2f3a2a" opacity=".55"/></g>') if dirty else ''
    return ('<svg viewBox="0 0 600 400" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><rect width="600" height="400" fill="#cbc8c1"/>'
            + grime + f'<g stroke="#a8a49b" stroke-width="5">{joints}</g></svg>')


def art_lawn(dirty):
    if dirty:
        body = ('<rect width="600" height="400" fill="#6b8f3f"/><ellipse cx="150" cy="140" rx="110" ry="70" fill="#a89a5b"/><ellipse cx="420" cy="260" rx="150" ry="85" fill="#9c8d4f"/>'
                '<ellipse cx="500" cy="90" rx="70" ry="45" fill="#b3a466"/>' + ''.join(f'<path d="M{x} 400 l6 -{h} l6 {h}Z" fill="#3e6b2c"/>' for x, h in ((40, 90), (210, 120), (330, 80), (470, 110))))
    else:
        body = ''.join(f'<rect x="{i * 75}" y="0" width="75" height="400" fill="{"#4f8a3a" if i % 2 else "#5f9c45"}"/>' for i in range(8))
    return f'<svg viewBox="0 0 600 400" preserveAspectRatio="xMidYMid slice" aria-hidden="true">{body}<rect y="360" width="600" height="40" fill="#bdb6a6"/></svg>'


def art_window(dirty):
    panes = ''.join(f'<rect x="{x}" y="{y}" width="250" height="160" fill="#a9d6f0"/>' for x in (40, 310) for y in (30, 210))
    extra = ('<g fill="#7a6f55"><ellipse cx="160" cy="110" rx="100" ry="60" opacity=".45"/><ellipse cx="430" cy="290" rx="110" ry="60" opacity=".5"/>'
             '<ellipse cx="420" cy="90" rx="80" ry="45" opacity=".35"/></g>') if dirty else '<path d="M60 50 L140 50 L70 170 L40 170Z" fill="#fff" opacity=".4"/>'
    return (f'<svg viewBox="0 0 600 400" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><rect width="600" height="400" fill="#efe9de"/>{panes}{extra}'
            '<g fill="none" stroke="#f7f4ee" stroke-width="18"><rect x="31" y="21" width="538" height="358"/><line x1="300" y1="21" x2="300" y2="379"/><line x1="31" y1="200" x2="569" y2="200"/></g></svg>')


def art_wall(dirty, color):
    planks = ''.join(f'<rect x="0" y="{y}" width="600" height="38" fill="{color}"/><rect x="0" y="{y + 36}" width="600" height="2" fill="#00000022"/>' for y in range(0, 400, 40))
    if dirty:
        planks = ''.join(f'<rect x="0" y="{y}" width="600" height="38" fill="#b9b2a3"/><rect x="0" y="{y + 36}" width="600" height="2" fill="#00000033"/>' for y in range(0, 400, 40))
        planks += '<g fill="#8f8573" opacity=".55"><ellipse cx="120" cy="90" rx="90" ry="40"/><ellipse cx="420" cy="260" rx="160" ry="60"/><ellipse cx="260" cy="350" rx="120" ry="30"/></g>'
    return f'<svg viewBox="0 0 600 400" preserveAspectRatio="xMidYMid slice" aria-hidden="true">{planks}</svg>'


def scene(niche, brand, accent, wide=False):
    """A simple house scene for the hero when there is no photo. wide=True fills a banner-shaped box."""
    ground = {
        'lawn': ''.join('<path d="M%d 320 L%d 500 L%d 500 L%d 320Z" fill="%s"/>' % (x0, x0 * 2 - 200, x1 * 2 - 200, x1, '#5f9c45' if i % 2 else '#4f8a3a')
                        for i, (x0, x1) in enumerate(zip(range(-600, 1000, 50), range(-550, 1050, 50)))),
        'window': '<rect x="-400" y="320" width="1200" height="180" fill="#cfd6da"/>',
    }.get(niche, '<rect x="-400" y="320" width="1200" height="180" fill="#6f9a52"/><path d="M180 320 L220 320 L300 500 L100 500Z" fill="#d9d5cc"/>')
    if wide:
        ground += ''.join(f'<rect x="{x - 4}" y="{y + 40}" width="8" height="{330 - y - 40}" fill="#6b4f35"/><circle cx="{x}" cy="{y}" r="{r}" fill="{c}"/>'
                          for x, y, r, c in ((-260, 230, 70, '#3f7a3a'), (-120, 260, 50, '#4f8a3a'), (500, 250, 60, '#4f8a3a'), (640, 220, 80, '#3f7a3a')))
    house = ('<rect x="70" y="170" width="260" height="150" fill="#f3efe7"/>'
             + ''.join(f'<line x1="70" y1="{y}" x2="330" y2="{y}" stroke="#e2dccf" stroke-width="2"/>' for y in range(185, 320, 14))
             + f'<path d="M50 178 200 80 350 178Z" fill="{brand}"/><rect x="105" y="210" width="50" height="45" fill="#bfd9ea" stroke="#fff" stroke-width="5"/>'
             + f'<rect x="245" y="210" width="50" height="45" fill="#bfd9ea" stroke="#fff" stroke-width="5"/><rect x="180" y="235" width="40" height="85" fill="{accent}"/>')
    box = '-400 40 1200 460" preserveAspectRatio="xMidYMax slice' if wide else '0 0 400 500" preserveAspectRatio="xMidYMid slice'
    return (f'<svg viewBox="{box}" aria-hidden="true">'
            '<defs><linearGradient id="sk" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9fd0ee"/><stop offset="1" stop-color="#e8f4fb"/></linearGradient></defs>'
            f'<rect x="-400" width="1200" height="500" fill="url(#sk)"/>{ground}{house}</svg>')

# ---------------------------------------------------------------------------------------------

def load_spec(path):
    with open(path) as f:
        s = json.load(f)
    for req in ('business', 'slug', 'niche', 'headline'):
        if not str(s.get(req, '')).strip():
            raise SystemExit(f'spec is missing "{req}"')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{1,60}', s['slug']):
        raise SystemExit('slug must be lowercase letters, numbers and hyphens')
    s['package'] = s.get('package') or 'mockup'
    if s['package'] not in ('mockup', 'starter', 'full'):
        raise SystemExit('package must be mockup, starter or full')
    return s


def design(s):
    niche = NICHES.get(str(s['niche']).lower().strip(), 'other')
    variant = s.get('variant') if s.get('variant') in VARIANTS else pick(VARIANTS, s['slug'])
    font = s.get('font') if s.get('font') in FONTS else pick(VARIANT_FONTS[variant], s['slug'], 'font')
    brand, accent, ink, paper, panel = pick(PALETTES[niche], s['slug'], 'pal')
    # Brand colors from their logo or truck win when they read well.
    bc = [c for c in (s.get('brand_colors') or []) if re.fullmatch(r'#?[0-9a-fA-F]{6}', str(c))]
    bc = ['#' + c.lstrip('#') for c in bc]
    usable = [c for c in bc if 0.02 < lum(c) < 0.6]
    if usable:
        brand = usable[0]
        others = [c for c in bc if c != brand and contrast(c, brand) > 2]
        if others:
            accent = others[0]
    if contrast(brand, paper) < 3:
        brand = shade(brand, -0.35)
    return {
        'niche': niche, 'variant': variant, 'font': font,
        'brand': brand, 'brand_ink': on(brand, ink), 'accent': accent, 'accent_ink': on(accent, ink),
        'ink': ink, 'paper': paper, 'panel': panel, 'muted': shade(ink, 0.38), 'line': shade(ink, 0.82),
        'deep': shade(brand, -0.45),
    }


CSS = """
:root{--brand:%(brand)s;--brand-ink:%(brand_ink)s;--accent:%(accent)s;--accent-ink:%(accent_ink)s;--ink:%(ink)s;--paper:%(paper)s;--panel:%(panel)s;--muted:%(muted)s;--line:%(line)s;--deep:%(deep)s;--display:%(display)s;--body:%(body)s}
*{box-sizing:border-box}html{scroll-behavior:smooth;-webkit-text-size-adjust:100%%}
body{margin:0;background:var(--paper);color:var(--ink);font-family:var(--body);font-size:17px;line-height:1.6;-webkit-font-smoothing:antialiased}
img,svg{max-width:100%%;display:block}a{color:inherit}
.ribbon{background:#ffd84a;color:#1d1a10;font:600 13px/1.45 system-ui,sans-serif;text-align:center;padding:8px 16px}
.wrap{width:100%%;max-width:1140px;margin-inline:auto;padding-inline:max(20px,env(safe-area-inset-left,0px)) max(20px,env(safe-area-inset-right,0px))}
header.top{position:sticky;top:0;z-index:20;background:color-mix(in srgb,var(--paper) 92%%,transparent);backdrop-filter:blur(8px);border-bottom:1px solid var(--line)}
header.top .wrap{display:flex;align-items:center;justify-content:space-between;gap:16px;min-height:68px}
.logo{display:flex;align-items:center;gap:10px;text-decoration:none;font-family:var(--display);font-weight:800;font-size:1.2rem;line-height:1.1;min-width:0}
.logo img{height:44px;width:auto;max-width:160px;object-fit:contain}
.mono{width:40px;height:40px;flex:none;border-radius:10px;background:var(--brand);color:var(--brand-ink);display:grid;place-items:center;font-size:1rem;letter-spacing:.02em}
.logo span.nm{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
nav.main{display:flex;align-items:center;gap:24px;font-weight:600;font-size:.96rem}
nav.main a{text-decoration:none;opacity:.78}nav.main a:hover,nav.main a[aria-current],nav.main a.btn{opacity:1}nav.main .btn{white-space:nowrap}
@media(max-width:820px){nav.main a.l{display:none}}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:9px;font:700 1rem/1 var(--body);text-decoration:none;padding:15px 22px;border-radius:12px;background:var(--brand);color:var(--brand-ink);border:2px solid var(--brand);cursor:pointer;transition:transform .15s,filter .15s}
.btn:hover{filter:brightness(1.08);transform:translateY(-1px)}
.btn.alt{background:var(--accent);border-color:var(--accent);color:var(--accent-ink)}
.btn.ghost{background:transparent;color:inherit;border-color:currentColor}
.btn.sm{padding:11px 16px;font-size:.95rem}
.btn .ic{width:20px;height:20px;stroke:currentColor}
a:focus-visible,.btn:focus-visible,input:focus-visible,textarea:focus-visible,select:focus-visible,button:focus-visible{outline:3px solid var(--accent);outline-offset:3px}
h1,h2,h3{font-family:var(--display);line-height:1.06;margin:0;text-wrap:balance;letter-spacing:-.01em}
h1{font-size:clamp(2.5rem,6.4vw,4.6rem);font-weight:800}
h2{font-size:clamp(1.9rem,3.8vw,2.8rem);font-weight:800}
h3{font-size:1.18rem;font-weight:700;line-height:1.25}
p{margin:0}
.eyebrow{display:inline-flex;align-items:center;gap:8px;text-transform:uppercase;letter-spacing:.14em;font-size:.76rem;font-weight:700;color:var(--brand);margin-bottom:14px}
.eyebrow::before{content:"";width:22px;height:3px;border-radius:2px;background:var(--accent)}
section{padding-block:clamp(60px,8vw,104px)}
.lede{font-size:clamp(1.08rem,1.6vw,1.22rem);max-width:36rem;color:var(--muted);margin-top:18px}
.actions{display:flex;flex-wrap:wrap;gap:12px;margin-top:30px}
.two{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%%,22rem),1fr));gap:clamp(28px,5vw,64px);align-items:center}
.ic{width:30px;height:30px;fill:none;stroke:var(--brand);stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
.trust{background:var(--deep);color:#fff}
.trust .wrap{display:flex;flex-wrap:wrap;justify-content:center;gap:14px 40px;padding-block:18px;font-weight:600;font-size:.98rem}
.trust span{display:inline-flex;align-items:center;gap:10px}.trust .ic{stroke:var(--accent);width:22px;height:22px}
.svcs{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%%,16rem),1fr));gap:18px;margin-top:40px}
.svc{background:#fff;border:1px solid var(--line);border-radius:18px;padding:26px;display:grid;gap:10px;align-content:start;box-shadow:0 1px 0 var(--line)}
.svc .ib{width:54px;height:54px;border-radius:14px;background:var(--panel);display:grid;place-items:center}
.svc p{color:var(--muted);font-size:.98rem}
.tinted{background:var(--panel)}
.ba{position:relative;aspect-ratio:3/2;border-radius:18px;overflow:hidden;user-select:none;touch-action:pan-y;box-shadow:0 18px 40px -20px rgba(0,0,0,.4)}
.ba>div,.ba svg,.ba img{position:absolute;inset:0;width:100%%;height:100%%;object-fit:cover}
.ba .before{clip-path:inset(0 calc(100%% - var(--pos,50%%)) 0 0)}
.ba .handle{position:absolute;top:0;bottom:0;left:var(--pos,50%%);width:3px;background:#fff;transform:translateX(-50%%);pointer-events:none}
.ba .handle::after{content:"\\2194";position:absolute;top:50%%;left:50%%;width:44px;height:44px;border-radius:50%%;background:#fff;color:#222;display:grid;place-items:center;font-size:20px;transform:translate(-50%%,-50%%);box-shadow:0 2px 12px rgba(0,0,0,.3)}
.ba input{position:absolute;inset:0;width:100%%;height:100%%;opacity:0;cursor:ew-resize;margin:0}
.ba .tag{position:absolute;top:12px;font:700 12px/1 system-ui,sans-serif;background:rgba(0,0,0,.62);color:#fff;padding:7px 10px;border-radius:6px;letter-spacing:.06em;text-transform:uppercase}
.ba .tag.l{left:12px}.ba .tag.r{right:12px}
.cap{font-size:.9rem;color:var(--muted);margin-top:12px}
.gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%%,15rem),1fr));gap:14px;margin-top:36px}
.gallery figure{margin:0;border-radius:16px;overflow:hidden;background:var(--panel);aspect-ratio:4/3;position:relative}
.gallery img{width:100%%;height:100%%;object-fit:cover}
.ph{border:2px dashed var(--line);border-radius:16px;display:grid;place-items:center;text-align:center;padding:24px;color:var(--muted);font-size:.92rem;aspect-ratio:4/3;background:var(--panel)}
.ph .ic{width:34px;height:34px;margin:0 auto 10px;stroke:var(--muted)}
.reviews{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%%,17rem),1fr));gap:18px;margin-top:36px}
.review{background:#fff;border:1px solid var(--line);border-radius:18px;padding:26px;display:grid;align-content:space-between;gap:18px}
.review.ph2{border:2px dashed var(--line);background:transparent;color:var(--muted)}
.stars{display:flex;gap:3px}.stars .ic{width:18px;height:18px;fill:var(--accent);stroke:var(--accent)}
.review q{quotes:none;font-size:1.02rem}.review cite{font-style:normal;font-weight:700;font-size:.92rem}.review cite span{font-weight:400;color:var(--muted)}
.rating{display:flex;align-items:center;gap:14px;margin-top:18px;flex-wrap:wrap}.rating b{font-family:var(--display);font-size:2.4rem;line-height:1}
.facts{list-style:none;padding:0;margin:26px 0 0;display:grid;gap:12px}
.facts li{display:grid;grid-template-columns:9.5rem 1fr;gap:12px;padding-bottom:12px;border-bottom:1px solid var(--line)}
.facts b{font-weight:700}.facts span{color:var(--muted)}
@media(max-width:520px){.facts li{grid-template-columns:1fr;gap:2px}}
.area{display:flex;flex-wrap:wrap;gap:10px;margin-top:22px}.area span{background:#fff;border:1px solid var(--line);border-radius:999px;padding:8px 16px;font-weight:600;font-size:.95rem}
section.tight{padding-top:clamp(36px,5vw,56px)}.pagehead{background:var(--panel);padding-block:clamp(44px,7vw,80px) clamp(28px,4vw,44px)}.pagehead h1{font-size:clamp(2.2rem,5vw,3.6rem)}
.cta{background:var(--brand);color:var(--brand-ink);border-radius:24px;padding:clamp(28px,5vw,56px);display:grid;gap:18px;justify-items:start}
.cta .lede{color:inherit;opacity:.85;margin-top:0}
.cta .btn{background:var(--accent);border-color:var(--accent);color:var(--accent-ink)}
form{display:grid;gap:14px;background:#fff;border:1px solid var(--line);border-radius:20px;padding:clamp(20px,4vw,34px);box-shadow:0 20px 50px -30px rgba(0,0,0,.35)}
label{display:grid;gap:6px;font-weight:600;font-size:.95rem}
input,textarea,select{font:inherit;padding:13px 14px;border-radius:12px;border:1px solid var(--line);background:var(--paper);color:var(--ink);width:100%%}
textarea{min-height:7rem;resize:vertical}
.sent{background:var(--brand);color:var(--brand-ink);border-radius:12px;padding:12px 14px;font-weight:700}
.contact-list{display:grid;gap:14px;margin-top:26px}.contact-list a,.contact-list div{display:flex;gap:12px;align-items:center;text-decoration:none;font-weight:600}
footer{background:var(--deep);color:#fff;padding-block:44px 90px;font-size:.94rem}
footer .wrap{display:flex;flex-wrap:wrap;justify-content:space-between;gap:16px}footer a{color:#fff}footer .dim{opacity:.7}
.callbar{position:fixed;left:0;right:0;bottom:0;z-index:30;display:none;gap:10px;padding:10px max(14px,env(safe-area-inset-left,0px)) calc(10px + env(safe-area-inset-bottom,0px));background:color-mix(in srgb,var(--paper) 94%%,transparent);backdrop-filter:blur(8px);border-top:1px solid var(--line)}
.callbar .btn{flex:1;padding:14px}
@media(max-width:720px){.callbar{display:flex}footer{padding-bottom:110px}}
@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important;transition:none!important}}
"""

HERO_CSS = {
    'split': """.hero{padding-block:clamp(36px,6vw,84px)}.hero-art{border-radius:24px;overflow:hidden;aspect-ratio:4/5;max-height:620px;position:relative;background:var(--panel);box-shadow:0 30px 60px -30px rgba(0,0,0,.45)}
.hero-art svg,.hero-art img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}.hero-art .chip{position:absolute;left:16px;bottom:16px;right:16px;max-width:fit-content;background:var(--paper);color:var(--ink);padding:11px 15px;border-radius:12px;font-weight:700;font-size:.92rem;box-shadow:0 8px 24px rgba(0,0,0,.18)}""",
    'banner': """.hero{background:var(--brand);color:var(--brand-ink);padding-block:clamp(70px,11vw,136px);position:relative;overflow:hidden}
.hero .eyebrow{color:var(--accent)}.hero .lede{color:inherit;opacity:.88}.hero .btn{background:var(--accent);border-color:var(--accent);color:var(--accent-ink)}.hero .btn.ghost{background:transparent;color:var(--brand-ink);border-color:var(--brand-ink)}
.hero .stripes{position:absolute;right:-6%;top:0;bottom:0;width:40%;background:repeating-linear-gradient(135deg,rgba(255,255,255,.08) 0 20px,transparent 20px 40px)}.hero .wrap{position:relative}
.hero .photo{position:absolute;inset:0;opacity:.22}.hero .photo img{width:100%;height:100%;object-fit:cover}""",
    'editorial': """.hero{padding-block:clamp(48px,8vw,100px) 0}.hero h1{max-width:17ch}
.hero .meta{display:flex;flex-wrap:wrap;gap:10px 28px;margin-top:28px;color:var(--muted);font-weight:600;font-size:.96rem}.hero .meta span{display:inline-flex;align-items:center;gap:8px}.hero .meta .ic{width:20px;height:20px}
.hero-band{margin-top:clamp(36px,6vw,64px);border-radius:24px;overflow:hidden;aspect-ratio:21/8;position:relative;background:var(--panel)}.hero-band svg,.hero-band img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
@media(max-width:640px){.hero-band{aspect-ratio:4/3}}""",
    'bold': """.hero{background:var(--deep);color:#fff;padding-block:clamp(70px,11vw,140px);position:relative;overflow:hidden}.hero .lede{color:#fff;opacity:.8}.hero .eyebrow{color:var(--accent)}
.hero h1 em{font-style:normal;color:var(--accent)}.hero .big{display:inline-flex;align-items:center;gap:12px;font-family:var(--display);font-weight:800;font-size:clamp(1.7rem,4.5vw,2.8rem);text-decoration:none;color:#fff;margin-top:28px}
.hero .big .ic{width:36px;height:36px;stroke:var(--accent)}.hero .glow{position:absolute;right:-10%;top:-30%;width:60%;aspect-ratio:1;border-radius:50%;background:radial-gradient(closest-side,color-mix(in srgb,var(--brand) 70%,transparent),transparent)}
.hero .btn.ghost{color:#fff}.hero .wrap{position:relative}.hero .photo{position:absolute;inset:0;opacity:.28}.hero .photo img{width:100%;height:100%;object-fit:cover}""",
}

# ---------------------------------------------------------------------------------------------

def build(s, d):
    biz = clean(s['business'])
    mock = s['package'] == 'mockup'
    phone = clean(s.get('phone', ''))
    tel = digits(phone)
    email = clean(s.get('email', ''))
    fb = clean(s.get('facebook', ''))
    town = clean(s.get('town', '') or (s.get('service_area') or [''])[0])
    area = [clean(a) for a in (s.get('service_area') or []) if clean(a)]
    photos = [p for p in (s.get('photos') or []) if p.get('file')]
    role = lambda r: [p for p in photos if (p.get('role') or 'gallery') == r]
    logo = (role('logo') or [None])[0]
    hero_img = (role('hero') or [None])[0]
    befores, afters = role('before'), role('after')
    gallery = role('gallery') + role('hero')[1:]
    reviews = [r for r in (s.get('reviews') or []) if clean(r.get('quote'))]
    rating = s.get('rating') or {}
    services = [x for x in (s.get('services') or []) if clean(x.get('name'))][:8]
    initials = ''.join(w[0] for w in re.findall(r'[A-Za-z0-9]+', biz)[:2]).upper() or 'S'

    call_href = f'tel:+1{tel}' if tel else (fb or (f'mailto:{email}' if email else '#contact'))
    call_label = f'Call {phone}' if tel else ('Message us on Facebook' if fb else 'Get in touch')
    full = s['package'] == 'full'
    link = (lambda page, anchor: f'{page}.html' if full else f'#{anchor}')
    home = 'index.html' if full else '#top'

    def ph(text, ic='spark'):
        return f'<div class="ph"><div>{icon(ic)}{esc(text)}</div></div>'

    def img(p, cls=''):
        return f'<img src="{esc(p["file"])}" alt="{esc(clean(p.get("caption") or biz))}" loading="lazy"{f" class={cls}" if cls else ""}>'

    # Header and trust strip
    logo_html = img(logo) if logo else f'<span class="mono">{esc(initials)}</span>'
    nav = (f'<a class="l" href="{link("services", "services")}">Services</a><a class="l" href="{link("services", "work")}">Our work</a>'
           f'<a class="l" href="{link("about", "about")}">About</a>')
    header = (f'<header class="top"><div class="wrap"><a class="logo" href="{home}">{logo_html}<span class="nm">{esc(biz)}</span></a>'
              f'<nav class="main" aria-label="Main">{nav}<a class="btn sm" href="{link("contact", "contact")}">Free quote</a></nav></div></header>')
    trust_items = []
    if rating.get('value'):
        cnt = f' from {esc(rating["count"])} reviews' if rating.get('count') else ''
        trust_items.append((icon('star'), f'{esc(rating["value"])} stars{cnt}'))
    for t in (s.get('trust') or [])[:3]:
        trust_items.append((icon('check'), esc(clean(t))))
    if town:
        trust_items.append((icon('pin'), f'Local to {esc(town)}'))
    trust = ('<div class="trust"><div class="wrap">' + ''.join(f'<span>{i}{t}</span>' for i, t in trust_items) + '</div></div>') if trust_items else ''

    # Hero
    eyebrow = esc(clean(s.get('eyebrow') or (f'{s["niche"]} in {town}' if town else s['niche'])).capitalize())
    h1 = esc(clean(s['headline']))
    lede = esc(clean(s.get('subhead', '')))
    acts = f'<div class="actions"><a class="btn" href="{esc(call_href)}">{icon("phone")}{esc(call_label)}</a><a class="btn ghost" href="{link("contact", "contact")}">Get a free quote</a></div>'
    hero_visual = img(hero_img) if hero_img else scene(d['niche'], d['brand'], d['accent'], wide=d['variant'] == 'editorial')
    chip = esc(clean(s.get('hero_chip') or (f'Serving {", ".join(area[:3])}' if area else f'Locally owned in {town}' if town else biz)))
    v = d['variant']
    if v == 'split':
        hero = (f'<section class="hero" id="top"><div class="wrap two"><div><p class="eyebrow">{eyebrow}</p><h1>{h1}</h1><p class="lede">{lede}</p>{acts}</div>'
                f'<div class="hero-art">{hero_visual}<span class="chip">{chip}</span></div></div></section>')
    elif v == 'banner':
        bg = f'<div class="photo">{img(hero_img)}</div>' if hero_img else '<div class="stripes" aria-hidden="true"></div>'
        hero = f'<section class="hero" id="top">{bg}<div class="wrap"><p class="eyebrow">{eyebrow}</p><h1>{h1}</h1><p class="lede">{lede}</p>{acts}</div></section>'
    elif v == 'editorial':
        meta = ''.join(f'<span>{i}{t}</span>' for i, t in trust_items[:3])
        hero = (f'<section class="hero" id="top"><div class="wrap"><p class="eyebrow">{eyebrow}</p><h1>{h1}</h1><p class="lede">{lede}</p>{acts}'
                f'<div class="meta">{meta}</div><div class="hero-band">{hero_visual}</div></div></section>')
        trust = ''
    else:
        big = f'<a class="big" href="{esc(call_href)}">{icon("phone")}{esc(phone)}</a>' if tel else ''
        bg = f'<div class="photo">{img(hero_img)}</div>' if hero_img else '<div class="glow" aria-hidden="true"></div>'
        hero = (f'<section class="hero" id="top">{bg}<div class="wrap"><p class="eyebrow">{eyebrow}</p><h1>{h1}</h1><p class="lede">{lede}</p>'
                f'<div class="actions"><a class="btn alt" href="{link("contact", "contact")}">Get a free quote</a></div>{big}</div></section>')

    # Services
    svc_cards = ''.join(f'<article class="svc"><div class="ib">{icon(icon_for(x["name"] + " " + x.get("desc", ""), d["niche"]))}</div><h3>{esc(clean(x["name"]))}</h3>'
                        + (f'<p>{esc(clean(x["desc"]))}</p>' if clean(x.get('desc')) else '') + '</article>' for x in services)
    if not svc_cards:
        svc_cards = ''.join(f'<article class="svc">{ph("Service " + str(i) + ": name and one line about it")}</article>' for i in (1, 2, 3))
    services_sec = (f'<section id="services"><div class="wrap"><p class="eyebrow">What we do</p><h2>{esc(clean(s.get("services_title") or "Services"))}</h2>'
                    + (f'<p class="lede">{esc(clean(s["services_intro"]))}</p>' if s.get('services_intro') else '') + f'<div class="svcs">{svc_cards}</div></div></section>')

    # Before and after
    art = {'pressure': art_concrete, 'lawn': art_lawn, 'window': art_window, 'cleaning': art_window}.get(d['niche'])
    if befores and afters:
        b, a = img(befores[0]), img(afters[0])
        cap = clean(befores[0].get('caption') or 'Before and after')
        ba_cap = f'<p class="cap">{esc(cap)}</p>'
    elif art or d['niche'] in ('painting', 'handyman'):
        b = art(True) if art else art_wall(True, d['brand'])
        a = art(False) if art else art_wall(False, shade(d['brand'], 0.55))
        ba_cap = '<p class="cap">Sample illustration. Your real before and after job photos go here.</p>' if mock else ''
        if not mock:
            b = a = None
    else:
        b = a = None
    ba_sec = ''
    if b and a:
        ba_sec = (f'<section id="work" class="tinted"><div class="wrap two"><div><p class="eyebrow">See the difference</p>'
                  f'<h2>{esc(clean(s.get("ba_title") or "Drag to see the difference"))}</h2>'
                  + (f'<p class="lede">{esc(clean(s["ba_text"]))}</p>' if s.get('ba_text') else '') +
                  f'</div><div><div class="ba" style="--pos:50%"><div class="after">{a}</div><div class="before">{b}</div><span class="handle"></span>'
                  f'<span class="tag l">Before</span><span class="tag r">After</span><input type="range" min="0" max="100" value="50" aria-label="Drag to compare before and after"></div>{ba_cap}</div></div></section>')

    # Gallery
    figs = ''.join(f'<figure>{img(p)}</figure>' for p in gallery[:6])
    if not figs and mock:
        figs = ''.join(ph(t, i) for t, i in (('Photo: your crew on a job', 'truck'), ('Photo: a finished job you are proud of', 'house'), ('Photo: your equipment or truck', 'truck')))
    gallery_sec = (f'<section id="{"gallery" if ba_sec else "work"}"><div class="wrap"><p class="eyebrow">Recent work</p><h2>{esc(clean(s.get("gallery_title") or "Our work"))}</h2>'
                   f'<div class="gallery">{figs}</div></div></section>') if figs else ''

    # Reviews: real quotes only, word for word. Mockups without any show labeled placeholders.
    stars = '<span class="stars">' + icon('star') * 5 + '</span>'
    rev_cards = ''.join(f'<figure class="review" style="margin:0">{stars}<q>{esc(clean(r["quote"]))}</q><figcaption><cite>{esc(clean(r.get("name") or "Customer"))}'
                        + (f' <span>on {esc(clean(r["source"]))}</span>' if r.get('source') else '') + '</cite></figcaption></figure>' for r in reviews[:6])
    rating_html = ''
    if rating.get('value'):
        rating_html = (f'<div class="rating"><b>{esc(rating["value"])}</b>{stars}<span>' + (f'{esc(rating["count"])} reviews' if rating.get('count') else '')
                       + (f' on {esc(clean(rating["source"]))}' if rating.get('source') else '') + '</span></div>')
    if not rev_cards and mock:
        rev_cards = ''.join(f'<div class="review ph2">{stars}<span>A real customer review goes here, with their first name and town.</span></div>' for _ in range(3))
    reviews_sec = (f'<section id="reviews" class="tinted"><div class="wrap"><p class="eyebrow">Reviews</p><h2>What customers say</h2>{rating_html}'
                   f'<div class="reviews">{rev_cards}</div></div></section>') if (rev_cards or rating_html) else ''

    # About and service area
    about_txt = clean(s.get('about', ''))
    facts = ''.join(f'<li><b>{esc(clean(k))}</b><span>{esc(clean(v))}</span></li>' for k, v in (s.get('facts') or []) if clean(k) and clean(v))
    about_body = f'<p class="lede">{esc(about_txt)}</p>' if about_txt else (f'<p class="lede">{esc("A few lines in your own words: how you got started and what you care about on every job.")}</p>' if mock else '')
    about_side = (f'<figure class="gallery" style="margin:0;grid-template-columns:1fr"><figure>{img(hero_img)}</figure></figure>' if (hero_img and v != 'split')
                  else (ph('Photo: you and your crew', 'truck') if mock else ''))
    area_html = ('<div class="area">' + ''.join(f'<span>{esc(a)}</span>' for a in area) + '</div>') if area else ''
    about_sec = (f'<section id="about"><div class="wrap two"><div><p class="eyebrow">About us</p><h2>{esc(clean(s.get("about_title") or ("Locally owned in " + town if town else "About " + biz)))}</h2>'
                 f'{about_body}<ul class="facts">{facts}</ul>' + (f'<h3 style="margin-top:30px">Where we work</h3>{area_html}' if area_html else '') + f'</div><div>{about_side}</div></div></section>')

    # Contact
    form_email = clean(s.get('form_email', ''))
    svc_opts = ''.join(f'<option>{esc(clean(x["name"]))}</option>' for x in services) + '<option>Something else</option>'
    fields = ('<label for="n">Name<input id="n" name="name" autocomplete="name" required></label>'
              '<label for="p">Phone<input id="p" name="phone" type="tel" autocomplete="tel" required></label>'
              f'<label for="s">What do you need?<select id="s" name="service">{svc_opts}</select></label>'
              '<label for="m">Anything we should know?<textarea id="m" name="message"></textarea></label>')
    if mock:
        form = f'<form id="qf" novalidate>{fields}<button class="btn" type="submit">Send my request</button><p class="sent" id="sent" hidden>This is a mockup, nothing was sent.</p></form>'
    elif form_email:
        form = (f'<form action="https://formsubmit.co/{esc(form_email)}" method="POST">{fields}<input type="hidden" name="_subject" value="New quote request from your website">'
                '<input type="hidden" name="_captcha" value="false"><input type="text" name="_honey" style="display:none" tabindex="-1" autocomplete="off">'
                '<button class="btn" type="submit">Send my request</button></form>')
    else:
        form = ''
    hours = clean(s.get('hours', ''))
    clist = ''.join(x for x in (
        f'<a href="tel:+1{tel}">{icon("phone")}{esc(phone)}</a>' if tel else '',
        f'<a href="mailto:{esc(email)}">{icon("check")}{esc(email)}</a>' if email else '',
        f'<a href="{esc(fb)}">{icon("check")}Facebook</a>' if fb else '',
        f'<div>{icon("clock")}{esc(hours)}</div>' if hours else '',
        f'<div>{icon("pin")}{esc(", ".join(area) if area else town)}</div>' if (area or town) else ''))
    contact_sec = (f'<section id="contact"><div class="wrap two"><div><p class="eyebrow">Free quote</p><h2>{esc(clean(s.get("quote_title") or "Get a free quote"))}</h2>'
                   f'<p class="lede">{esc(clean(s.get("quote_text") or "Tell us a little about the job and we will get back to you with a price."))}</p>'
                   f'<div class="contact-list">{clist}</div></div><div>{form or ("<div class=cta><h3>Call or text for a quote</h3><a class=btn href=" + chr(34) + esc(call_href) + chr(34) + ">" + esc(call_label) + "</a></div>")}</div></div></section>')

    cta_band = (f'<section><div class="wrap"><div class="cta"><h2>{esc(clean(s.get("cta_title") or "Ready when you are"))}</h2>'
                f'<p class="lede">{esc(clean(s.get("cta_text") or "Free quotes, honest prices and work you can see from the street."))}</p>'
                f'<a class="btn" href="{link("contact", "contact")}">Get a free quote</a></div></div></section>')

    year = s.get('year') or ''
    credit = 'Concept site by' if mock else 'Website by'
    footer = (f'<footer><div class="wrap"><div><b>{esc(biz)}</b><div class="dim">{esc(", ".join(area) if area else town)}</div></div>'
              f'<div class="dim">{"&copy; " + esc(year) + " " if year else ""}{credit} <a href="mailto:thomasdbiz26@gmail.com">Sidequest Creative</a>, Gonzales, LA</div></div></footer>')
    callbar = (f'<div class="callbar"><a class="btn" href="{esc(call_href)}">{icon("phone")}{"Call now" if tel else esc(call_label)}</a>'
               f'<a class="btn alt" href="{link("contact", "contact")}">Free quote</a></div>')

    # Pages
    def head(title, text):
        return (f'<section class="pagehead"><div class="wrap"><p class="eyebrow">{esc(biz)}</p><h1>{esc(title)}</h1>'
                + (f'<p class="lede">{esc(text)}</p>' if text else '') + '</div></section>')

    if full:
        where = f' in {town}' if town else ''
        services_sec_p = (head('Services' + where, clean(s.get('services_intro', '')))
                          + f'<section class="tight"><div class="wrap"><div class="svcs" style="margin-top:0">{svc_cards}</div></div></section>')
        pages = {
            'index.html': hero + trust + services_sec + reviews_sec + cta_band,
            'services.html': services_sec_p + ba_sec + gallery_sec + cta_band,
            'about.html': head('About ' + biz, '') + about_sec + reviews_sec + cta_band,
            'contact.html': head('Get a free quote', clean(s.get('quote_text') or 'Call, text or send the form and we will get back to you.')) + contact_sec,
        }
    else:
        pages = {'index.html': hero + trust + services_sec + ba_sec + gallery_sec + reviews_sec + about_sec + contact_sec}

    fam, disp, body = FONTS[d['font']]
    css = CSS % dict(d, display=disp, body=body) + HERO_CSS[v]
    ribbon = ''
    if mock:
        all_real = 'class="ph' not in ''.join(pages.values()) and 'Sample illustration' not in ''.join(pages.values()) and (hero_img or v == 'bold')
        ribbon = (f'<div class="ribbon">Concept homepage designed for {esc(biz)} by Sidequest Creative. '
                  + ('Photos are from your business pages.' if all_real else 'Photos and some details are placeholders.') + '</div>')
    desc = esc(clean(s.get('meta_description') or f'{biz}: {s["niche"]} in {town or "your area"}. Call for a free quote.'))
    schema = ''
    if not mock:
        ld = {'@context': 'https://schema.org', '@type': 'LocalBusiness', 'name': biz}
        if tel:
            ld['telephone'] = f'+1{tel}'
        if town:
            ld['address'] = {'@type': 'PostalAddress', 'addressLocality': town, 'addressRegion': 'LA', 'addressCountry': 'US'}
        if area:
            ld['areaServed'] = area
        if s.get('url'):
            ld['url'] = s['url']
        if rating.get('value') and rating.get('count'):
            ld['aggregateRating'] = {'@type': 'AggregateRating', 'ratingValue': str(rating['value']), 'reviewCount': str(rating['count'])}
        schema = '<script type="application/ld+json">' + json.dumps(ld).replace('</', '<\\/') + '</script>'
    js = ("<script>document.querySelectorAll('.ba').forEach(function(b){var r=b.querySelector('input');r.addEventListener('input',function(){b.style.setProperty('--pos',r.value+'%')})});"
          + ("var f=document.getElementById('qf');f&&f.addEventListener('submit',function(e){e.preventDefault();document.getElementById('sent').hidden=false});" if mock else '')
          + '</script>')
    out = {}
    titles = {'index.html': '', 'services.html': 'Services | ', 'about.html': 'About | ', 'contact.html': 'Quote | '}
    for name, main in pages.items():
        out[name] = ('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
                     f'<title>{titles[name]}{esc(biz)} | {esc(str(s["niche"]).capitalize())}{" in " + esc(town) if town else ""}</title><meta name="description" content="{desc}">'
                     + ('<meta name="robots" content="noindex">' if mock else '') +
                     f'<meta name="theme-color" content="{d["brand"]}"><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
                     f'<link rel="stylesheet" href="https://fonts.googleapis.com/css2?{fam}&display=swap"><style>{css}</style>{schema}</head><body>'
                     f'{ribbon}{header}<main>{main}</main>{footer}{callbar}{js}</body></html>')
    return out


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: render.py spec.json out_dir')
    s = load_spec(sys.argv[1])
    d = design(s)
    pages = build(s, d)
    os.makedirs(sys.argv[2], exist_ok=True)
    for name, page in pages.items():
        with open(os.path.join(sys.argv[2], name), 'w') as f:
            f.write(page)
    print(json.dumps({'pages': sorted(pages), 'variant': d['variant'], 'font': d['font'], 'brand': d['brand'], 'accent': d['accent']}))


if __name__ == '__main__':
    main()

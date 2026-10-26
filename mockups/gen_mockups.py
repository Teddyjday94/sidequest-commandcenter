"""Build the eight Directory Scout mockups into the repo's mockups/<slug>/index.html."""
import html, json, os, re, sys

OUT = sys.argv[1]

# Illustrations for the before/after slider. Drawn, not photographed, and labeled as samples.
def concrete(dirty):
    joints = ''.join(f'<line x1="{x}" y1="0" x2="{x}" y2="400" />' for x in (200, 400)) + '<line x1="0" y1="200" x2="600" y2="200" />'
    base = '<rect width="600" height="400" fill="#c9c6bf"/><rect width="600" height="400" fill="url(#grain)"/>'
    grime = ''
    if dirty:
        grime = ('<g opacity=".85">'
                 '<ellipse cx="140" cy="120" rx="150" ry="90" fill="#5d5a3f" opacity=".55"/>'
                 '<ellipse cx="430" cy="290" rx="200" ry="110" fill="#3f4630" opacity=".6"/>'
                 '<ellipse cx="300" cy="60" rx="120" ry="50" fill="#6b5e45" opacity=".45"/>'
                 '<ellipse cx="80" cy="330" rx="110" ry="70" fill="#2f3a2a" opacity=".55"/>'
                 '<ellipse cx="520" cy="80" rx="90" ry="60" fill="#4a4a36" opacity=".5"/>'
                 '<path d="M0 230 C120 250 220 210 600 260 L600 290 C300 250 150 280 0 260Z" fill="#2b2a22" opacity=".35"/>'
                 '</g>')
    return ('<svg viewBox="0 0 600 400" preserveAspectRatio="xMidYMid slice" aria-hidden="true">'
            '<defs><filter id="n"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" seed="3"/><feColorMatrix values="0 0 0 0 .35  0 0 0 0 .34  0 0 0 0 .32  0 0 0 .35 0"/></filter>'
            '<pattern id="grain" width="600" height="400" patternUnits="userSpaceOnUse"><rect width="600" height="400" filter="url(#n)"/></pattern></defs>'
            + base + grime + f'<g stroke="#a8a49b" stroke-width="5">{joints}</g></svg>')

def lawn(dirty):
    stripes = ''.join(f'<rect x="{i*75}" y="0" width="75" height="400" fill="{"#4f8a3a" if i % 2 else "#5f9c45"}"/>' for i in range(8))
    patch = ''
    if dirty:
        patch = ('<rect width="600" height="400" fill="#6b8f3f"/>'
                 '<ellipse cx="150" cy="140" rx="110" ry="70" fill="#a89a5b"/>'
                 '<ellipse cx="420" cy="260" rx="150" ry="85" fill="#9c8d4f"/>'
                 '<ellipse cx="500" cy="90" rx="70" ry="45" fill="#b3a466"/>'
                 '<ellipse cx="90" cy="330" rx="90" ry="50" fill="#8c8a48"/>'
                 + ''.join(f'<path d="M{x} 400 l6 -{h} l6 {h}Z" fill="#3e6b2c"/>' for x, h in ((40, 90), (210, 120), (330, 80), (470, 110), (560, 95), (120, 70)))
                 )
        stripes = ''
    return f'<svg viewBox="0 0 600 400" preserveAspectRatio="xMidYMid slice" aria-hidden="true">{stripes}{patch}<rect y="360" width="600" height="40" fill="#bdb6a6"/></svg>'

def windowpane(dirty):
    sky = '<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8ec5ea"/><stop offset="1" stop-color="#dff0fa"/></linearGradient></defs>'
    panes = ''.join(f'<rect x="{x}" y="{y}" width="250" height="160" fill="url(#sky)"/>' for x in (40, 310) for y in (30, 210))
    glare = '<path d="M60 50 L140 50 L70 170 L40 170Z" fill="#fff" opacity=".35"/><path d="M330 230 L400 230 L340 350 L310 350Z" fill="#fff" opacity=".3"/>'
    smudge = ''
    if dirty:
        smudge = ('<g fill="#7a6f55">'
                  '<ellipse cx="160" cy="110" rx="100" ry="60" opacity=".45"/><ellipse cx="430" cy="290" rx="110" ry="60" opacity=".5"/>'
                  '<ellipse cx="420" cy="90" rx="80" ry="45" opacity=".35"/><ellipse cx="150" cy="300" rx="90" ry="55" opacity=".4"/></g>'
                  '<g stroke="#8a7f66" stroke-width="6" opacity=".45">' + ''.join(f'<line x1="{x}" y1="40" x2="{x+8}" y2="190"/>' for x in (90, 180, 360, 470)) + '</g>')
        glare = ''
    return (f'<svg viewBox="0 0 600 400" preserveAspectRatio="xMidYMid slice" aria-hidden="true">{sky}<rect width="600" height="400" fill="#efe9de"/>'
            f'{panes}{glare}{smudge}<g fill="none" stroke="#f7f4ee" stroke-width="18"><rect x="31" y="21" width="538" height="358"/><line x1="300" y1="21" x2="300" y2="379"/><line x1="31" y1="200" x2="569" y2="200"/></g></svg>')

ART = {'concrete': concrete, 'lawn': lawn, 'window': windowpane}

def scene(kind, c):
    p = c['palette']
    sky = '<defs><linearGradient id="skyh" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9fd0ee"/><stop offset="1" stop-color="#e8f4fb"/></linearGradient></defs><rect width="400" height="500" fill="url(#skyh)"/>'
    house = ('<g><rect x="70" y="170" width="260" height="150" fill="#f3efe7"/>'
             + ''.join('<line x1="70" y1="%d" x2="330" y2="%d" stroke="#e2dccf" stroke-width="2"/>' % (y, y) for y in range(185, 320, 14)) +
             '<path d="M50 178 200 80 350 178Z" fill="%s"/>'
             '<rect x="105" y="210" width="50" height="45" fill="#bfd9ea" stroke="#fff" stroke-width="5"/>'
             '<rect x="245" y="210" width="50" height="45" fill="#bfd9ea" stroke="#fff" stroke-width="5"/>'
             '<rect x="180" y="235" width="40" height="85" fill="%s"/><circle cx="212" cy="280" r="3" fill="#f3efe7"/>'
             '</g>') % (p['brand'], p['accent'])
    if kind == 'lawn':
        ground = ''.join('<path d="M%d 320 L%d 500 L%d 500 L%d 320Z" fill="%s"/>' % (x0, x0*2-200, x1*2-200, x1, '#5f9c45' if i % 2 else '#4f8a3a') for i, (x0, x1) in enumerate(zip(range(-200, 600, 50), range(-150, 650, 50))))
    else:
        ground = '<rect y="320" width="400" height="180" fill="#6f9a52"/><path d="M180 320 L220 320 L300 500 L100 500Z" fill="#d9d5cc"/><path d="M200 330 L200 500" stroke="#c5c0b5" stroke-width="3" stroke-dasharray="14 14"/>'
    if kind == 'window':
        ground = '<rect y="320" width="400" height="180" fill="#cfd6da"/>'
    return '<svg viewBox="0 0 400 500" preserveAspectRatio="xMidYMid slice" aria-hidden="true">' + sky + ground + house + '</svg>'

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
    'card': '<path d="M3 6h18v12H3zM3 10h18M7 15h4"/>',
    'window': '<path d="M5 4h14v16H5zM12 4v16M5 12h14"/>',
    'blind': '<path d="M5 4h14M6 4v12M18 4v12M6 7h12M6 10h12M6 13h12M6 16h12M12 16v4"/>',
    'sun': '<path d="M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M5 19l2-2"/>',
    'panel': '<path d="M3 17 6 7h15l-3 10zM8 7l-2 10M13 7l-2 10M17 7l-2 10M4 12h16"/>',
    'drop': '<path d="M12 3c4 5 6 8 6 11a6 6 0 0 1-12 0c0-3 2-6 6-11z"/>',
    'shield': '<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/>',
    'car': '<path d="M3 16v-4l2-5h14l2 5v4zM3 16v3h3v-3M18 16v3h3v-3M7 12h10"/>',
}

def icon(name):
    return f'<svg class="ic" viewBox="0 0 24 24" aria-hidden="true">{ICONS[name]}</svg>'

def esc(s):
    return html.escape(s, quote=True)

def build(c):
    p = c['palette']
    biz = c['business']
    phone_digits = re.sub(r'\D', '', c.get('phone', ''))
    if phone_digits:
        cta_href, cta_label = f'tel:+1{phone_digits}', f'Call {c["phone"]}'
    else:
        cta_href, cta_label = c['facebook'], 'Message us on Facebook'
    services = ''.join(
        f'<article class="svc">{icon(s[0])}<h3>{esc(s[1])}</h3><p>{esc(s[2])}</p></article>' for s in c['services'])
    svc_note = f'<p class="note">{esc(c["services_note"])}</p>' if c.get('services_note') else ''
    facts = ''.join(f'<li><b>{esc(k)}</b><span>{esc(v)}</span></li>' for k, v in c['facts'])
    extra = c.get('extra_html', '')
    art = ART[c['art']]
    review_line = f'<p class="rating">{esc(c["rating_line"])}</p>' if c.get('rating_line') else ''
    hours = f'<p class="hours">{esc(c["hours"])}</p>' if c.get('hours') else ''
    layout = c['layout']
    css = f"""
:root {{ --ink:{p['ink']}; --paper:{p['paper']}; --brand:{p['brand']}; --brand-ink:{p['brand_ink']}; --accent:{p['accent']}; --muted:{p['muted']}; --line:{p['line']}; --panel:{p['panel']};
  --display:{c['fonts'][1]}; --body:{c['fonts'][3]}; }}
*{{box-sizing:border-box}} html{{scroll-behavior:smooth}}
body{{margin:0;background:var(--paper);color:var(--ink);font-family:var(--body);font-size:17px;line-height:1.55;-webkit-font-smoothing:antialiased}}
img,svg{{max-width:100%}} a{{color:inherit}}
.ribbon{{background:#ffd84a;color:#1d1a10;font:600 13px/1.4 system-ui,sans-serif;text-align:center;padding:8px 16px}}
.wrap{{max-width:1120px;margin-inline:auto;padding-inline:max(20px,env(safe-area-inset-left,0px))}}
header.nav{{display:flex;align-items:center;justify-content:space-between;gap:16px;padding-block:18px}}
.logo{{font-family:var(--display);font-weight:800;font-size:1.35rem;letter-spacing:{c.get('logo_track','-0.01em')};text-decoration:none;display:flex;align-items:center;gap:10px}}
.logo .mark{{width:34px;height:34px;border-radius:{c.get('mark_radius','8px')};background:var(--brand);color:var(--brand-ink);display:grid;place-items:center;font-size:.95rem}}
.nav nav{{display:flex;gap:22px;font-weight:600;font-size:.95rem}} .nav nav a{{text-decoration:none;opacity:.8}} .nav nav a:hover{{opacity:1}}
@media(max-width:760px){{.nav nav{{display:none}}}}
.btn{{display:inline-flex;align-items:center;gap:8px;font-weight:700;text-decoration:none;padding:14px 22px;border-radius:{c.get('btn_radius','10px')};background:var(--brand);color:var(--brand-ink);border:2px solid var(--brand);font-size:1rem;cursor:pointer;font-family:inherit}}
.btn.ghost{{background:transparent;color:inherit;border-color:currentColor}}
.btn:focus-visible,a:focus-visible,input:focus-visible,textarea:focus-visible,select:focus-visible{{outline:3px solid var(--accent);outline-offset:3px}}
h1,h2,h3{{font-family:var(--display);line-height:1.08;margin:0;text-wrap:balance}}
h1{{font-size:clamp(2.4rem,6vw,{c.get('h1max','4.4rem')});font-weight:{c.get('h1w','800')};letter-spacing:-0.02em}}
h2{{font-size:clamp(1.8rem,3.6vw,2.6rem);font-weight:800;letter-spacing:-0.01em}}
h3{{font-size:1.2rem;font-weight:700}}
.eyebrow{{text-transform:uppercase;letter-spacing:.14em;font-size:.78rem;font-weight:700;color:var(--accent)}}
section{{padding-block:clamp(56px,8vw,96px)}}
.lede{{font-size:1.18rem;max-width:34rem;color:var(--muted)}}
.hero-actions{{display:flex;flex-wrap:wrap;gap:12px;margin-top:28px}}
.svcs{{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,15rem),1fr));gap:18px;margin-top:36px}}
.svc{{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:24px;display:grid;gap:8px;align-content:start}}
.svc p{{margin:0;color:var(--muted);font-size:.98rem}}
.ic{{width:30px;height:30px;fill:none;stroke:var(--brand);stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}}
.note{{color:var(--muted);font-size:.9rem;margin-top:16px}}
.ba{{position:relative;aspect-ratio:3/2;border-radius:16px;overflow:hidden;border:1px solid var(--line);max-width:100%;user-select:none;touch-action:pan-y}}
.ba svg{{position:absolute;inset:0;width:100%;height:100%;display:block}}
.ba .before{{position:absolute;inset:0;clip-path:inset(0 calc(100% - var(--pos,50%)) 0 0)}}
.ba .handle{{position:absolute;top:0;bottom:0;left:var(--pos,50%);width:3px;background:#fff;box-shadow:0 0 0 1px rgba(0,0,0,.2);transform:translateX(-50%);pointer-events:none}}
.ba .handle::after{{content:"";position:absolute;top:50%;left:50%;width:42px;height:42px;border-radius:50%;background:#fff;transform:translate(-50%,-50%);box-shadow:0 2px 10px rgba(0,0,0,.25)}}
.ba input{{position:absolute;inset:0;width:100%;height:100%;opacity:0;cursor:ew-resize;margin:0}}
.ba .tag{{position:absolute;top:12px;font:700 12px/1 system-ui,sans-serif;background:rgba(0,0,0,.6);color:#fff;padding:6px 10px;border-radius:6px;letter-spacing:.06em;text-transform:uppercase}}
.ba .tag.l{{left:12px}} .ba .tag.r{{right:12px}}
.ba-cap{{font-size:.9rem;color:var(--muted);margin-top:10px}}
.two{{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,22rem),1fr));gap:clamp(28px,5vw,64px);align-items:center}}
.facts{{list-style:none;padding:0;margin:24px 0 0;display:grid;gap:12px}}
.facts li{{display:grid;grid-template-columns:9rem 1fr;gap:12px;padding-bottom:12px;border-bottom:1px solid var(--line)}}
.facts b{{font-weight:700}} .facts span{{color:var(--muted)}}
@media(max-width:520px){{.facts li{{grid-template-columns:1fr;gap:2px}}}}
.reviews{{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,16rem),1fr));gap:18px;margin-top:28px}}
.review{{border:2px dashed var(--line);border-radius:14px;padding:22px;color:var(--muted);font-size:.95rem;min-height:9rem;display:grid;align-content:space-between;gap:16px}}
.review .stars{{color:var(--accent);letter-spacing:3px;font-size:1.05rem}}
.rating{{font-weight:700;margin:12px 0 0}}
.photo{{border:2px dashed var(--line);border-radius:14px;display:grid;place-items:center;text-align:center;padding:24px;color:var(--muted);font-size:.92rem;aspect-ratio:4/3;background:var(--panel)}}
.photos{{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,14rem),1fr));gap:16px;margin-top:28px}}
form{{display:grid;gap:14px;background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:clamp(20px,4vw,32px)}}
label{{display:grid;gap:6px;font-weight:600;font-size:.95rem}}
input,textarea,select{{font:inherit;padding:12px 14px;border-radius:10px;border:1px solid var(--line);background:var(--paper);color:var(--ink);width:100%}}
textarea{{min-height:7rem;resize:vertical}}
.sent{{background:var(--brand);color:var(--brand-ink);border-radius:10px;padding:12px 14px;font-weight:700}}
footer{{padding-block:40px;border-top:1px solid var(--line);font-size:.92rem;color:var(--muted)}}
footer .wrap{{display:flex;flex-wrap:wrap;justify-content:space-between;gap:12px}}
.hours{{color:var(--muted);margin:8px 0 0}}
"""
    # Layout-specific hero styling.
    if layout == 'banner':
        css += """
.hero{background:var(--brand);color:var(--brand-ink);padding-block:clamp(64px,10vw,120px);position:relative;overflow:hidden}
.hero .lede{color:inherit;opacity:.88}
.hero .btn{background:var(--accent);border-color:var(--accent);color:var(--ink)}
.hero .btn.ghost{background:transparent;color:var(--brand-ink);border-color:var(--brand-ink)}
.hero .stripe{position:absolute;right:-8%;top:0;bottom:0;width:38%;background:repeating-linear-gradient(135deg,rgba(255,255,255,.07) 0 18px,transparent 18px 36px)}
.strip{display:flex;flex-wrap:wrap;gap:12px 36px;margin-top:40px;font-weight:700;font-size:.95rem}
.strip span{display:flex;gap:8px;align-items:center}
"""
    elif layout == 'split':
        css += """
.hero{padding-block:clamp(40px,7vw,88px)}
.hero .two{align-items:center}
.hero-art{border-radius:20px;overflow:hidden;aspect-ratio:4/5;position:relative;background:var(--brand)}
.hero-art svg{position:absolute;inset:0;width:100%;height:100%}
.hero-art .chip{position:absolute;left:16px;bottom:16px;background:var(--paper);color:var(--ink);padding:10px 14px;border-radius:10px;font-weight:700;font-size:.9rem;box-shadow:0 6px 20px rgba(0,0,0,.15)}
"""
    elif layout == 'dark':
        css += """
body{background:var(--paper)}
.hero{padding-block:clamp(64px,10vw,128px);border-bottom:1px solid var(--line)}
.hero h1 em{font-style:normal;color:var(--brand)}
.hero .lede{color:var(--muted)}
.hero{position:relative;overflow:hidden}.hero .wrap{position:relative;z-index:1}.deco{position:absolute;right:-140px;top:50%;transform:translateY(-50%);width:min(46vw,560px);opacity:.16;pointer-events:none}
@media(max-width:760px){.deco{opacity:.08;width:90vw;right:-30vw}}
.big-tel{font-family:var(--display);font-weight:800;font-size:clamp(1.6rem,4vw,2.4rem);text-decoration:none;color:var(--brand);display:inline-block;margin-top:24px}
"""
    else:  # editorial
        css += """
.hero{padding-block:clamp(48px,8vw,104px);border-bottom:1px solid var(--line)}
.hero h1{max-width:16ch}
.hero .meta{display:flex;flex-wrap:wrap;gap:10px 28px;margin-top:28px;color:var(--muted);font-weight:600;font-size:.95rem}
.hero .meta span::before{content:"";display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--accent);margin-right:8px;vertical-align:1px}
"""
    css += c.get('extra_css', '')

    if layout == 'banner':
        hero = f"""<section class="hero" id="top"><div class="stripe" aria-hidden="true"></div><div class="wrap">
<p class="eyebrow" style="color:var(--accent)">{esc(c['eyebrow'])}</p>
<h1>{c['h1']}</h1><p class="lede">{esc(c['lede'])}</p>
<div class="hero-actions"><a class="btn" href="{esc(cta_href)}">{esc(cta_label)}</a><a class="btn ghost" href="#quote">Get a free quote</a></div>
<div class="strip">{''.join(f'<span>{esc(s)}</span>' for s in c['strip'])}</div></div></section>"""
    elif layout == 'split':
        hero = f"""<section class="hero" id="top"><div class="wrap two"><div>
<p class="eyebrow">{esc(c['eyebrow'])}</p><h1>{c['h1']}</h1><p class="lede">{esc(c['lede'])}</p>
<div class="hero-actions"><a class="btn" href="{esc(cta_href)}">{esc(cta_label)}</a><a class="btn ghost" href="#quote">Get a free quote</a></div>{hours}</div>
<div class="hero-art">{scene(c['art'], c)}<span class="chip">{esc(c['chip'])}</span></div></div></section>"""
    elif layout == 'dark':
        hero = f"""<section class="hero" id="top">{c.get('deco','')}<div class="wrap">
<p class="eyebrow">{esc(c['eyebrow'])}</p><h1>{c['h1']}</h1><p class="lede">{esc(c['lede'])}</p>
<div class="hero-actions"><a class="btn" href="#quote">Get a free quote</a></div>
<a class="big-tel" href="{esc(cta_href)}">{esc(c.get('phone') or 'Message us on Facebook')}</a>{hours}</div></section>"""
    else:
        hero = f"""<section class="hero" id="top"><div class="wrap">
<p class="eyebrow">{esc(c['eyebrow'])}</p><h1>{c['h1']}</h1><p class="lede">{esc(c['lede'])}</p>
<div class="hero-actions"><a class="btn" href="{esc(cta_href)}">{esc(cta_label)}</a><a class="btn ghost" href="#quote">Get a free quote</a></div>
<div class="meta">{''.join(f'<span>{esc(s)}</span>' for s in c['strip'])}</div></div></section>"""

    service_options = ''.join(f'<option>{esc(s[1])}</option>' for s in c['services'])
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>{esc(biz)} | {esc(c['title_tail'])}</title>
<meta name="description" content="{esc(c['meta'])}">
<meta name="robots" content="noindex">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?{c['fonts'][0]}&{c['fonts'][2]}&display=swap">
<style>{css}</style></head><body>
<div class="ribbon">Concept homepage designed for {esc(biz)} by Sidequest Creative. Photos and details are placeholders.</div>
<header class="wrap nav"><a class="logo" href="#top"><span class="mark">{esc(c['mark'])}</span>{esc(c['logo'])}</a>
<nav aria-label="Main"><a href="#services">Services</a><a href="#work">Our work</a><a href="#about">About</a><a href="#quote">Free quote</a></nav></header>
<main>{hero}
<section id="services"><div class="wrap"><p class="eyebrow">What we do</p><h2>{esc(c['services_h2'])}</h2><div class="svcs">{services}</div>{svc_note}</div></section>
{extra}
<section id="work" style="background:var(--panel);border-block:1px solid var(--line)"><div class="wrap two"><div>
<p class="eyebrow">See the difference</p><h2>{esc(c['ba_h2'])}</h2><p class="lede">{esc(c['ba_text'])}</p></div>
<div><div class="ba" style="--pos:50%"><div class="after">{art(False)}</div><div class="before">{art(True)}</div><span class="handle"></span>
<span class="tag l">Before</span><span class="tag r">After</span>
<input type="range" min="0" max="100" value="50" aria-label="Drag to compare before and after"></div>
<p class="ba-cap">Sample illustration. Your real before and after job photos go here.</p></div></div></section>
<section id="about"><div class="wrap two"><div><p class="eyebrow">About</p><h2>{esc(c['about_h2'])}</h2><p class="lede">{esc(c['about'])}</p>
<ul class="facts">{facts}</ul></div>
<div class="photos" style="margin-top:0"><div class="photo">Photo: {esc(c['photo1'])}</div><div class="photo">Photo: {esc(c['photo2'])}</div></div></div></section>
<section id="reviews" style="background:var(--panel);border-block:1px solid var(--line)"><div class="wrap"><p class="eyebrow">Reviews</p><h2>What customers say</h2>{review_line}
<div class="reviews">{''.join('<div class="review"><span class="stars" aria-hidden="true">&#9733;&#9733;&#9733;&#9733;&#9733;</span><span>A real customer review goes here, with their first name and town.</span></div>' for _ in range(3))}</div></div></section>
<section id="quote"><div class="wrap two"><div><p class="eyebrow">Free quote</p><h2>{esc(c['quote_h2'])}</h2><p class="lede">{esc(c['quote_text'])}</p>
<p style="margin-top:20px"><a class="btn" href="{esc(cta_href)}">{esc(cta_label)}</a></p>{hours}</div>
<form id="qf" novalidate><label for="n">Name<input id="n" name="name" autocomplete="name"></label>
<label for="p">Phone<input id="p" name="phone" type="tel" autocomplete="tel"></label>
<label for="s">What do you need?<select id="s" name="service">{service_options}<option>Something else</option></select></label>
<label for="m">Anything we should know?<textarea id="m" name="message"></textarea></label>
<button class="btn" type="submit">Send my request</button><p class="sent" id="sent" hidden>This is a mockup, nothing was sent.</p></form></div></section>
</main>
<footer><div class="wrap"><span>&copy; {esc(biz)} &middot; {esc(c['area'])}</span><span>Concept site by <a href="mailto:thomasdbiz26@gmail.com">Sidequest Creative</a>, Gonzales, LA</span></div></footer>
<script>
document.querySelectorAll('.ba').forEach(function(b){{var r=b.querySelector('input');r.addEventListener('input',function(){{b.style.setProperty('--pos',r.value+'%')}})}});
document.getElementById('qf').addEventListener('submit',function(e){{e.preventDefault();document.getElementById('sent').hidden=false}});
</script></body></html>"""
    for bad in ('—', '–'):
        assert bad not in page, (c['slug'], 'dash found')
    return page

MOCKUPS = json.load(open(sys.argv[2]))
for c in MOCKUPS:
    os.makedirs(os.path.join(OUT, c['slug']), exist_ok=True)
    with open(os.path.join(OUT, c['slug'], 'index.html'), 'w') as f:
        f.write(build(c))
    print(c['slug'], 'ok')

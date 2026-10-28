#!/usr/bin/env python3
"""Sidequest site kit: quality gate for a rendered site folder.

    python3 qa.py out_dir [spec.json]

Checks every .html page against the playbook's quality bar and prints a JSON report:
{"pass": bool, "errors": [...], "warnings": [...]}. Exit code 1 when there are errors.
Errors block a deploy. Warnings are worth a look but can ship. Standard library only.
For the browser checks (phone width overflow, broken images, screenshots) run qa_render.js.
"""
import json
import os
import re
import sys
from html.parser import HTMLParser

BANNED = [
    'elevate', 'unlock', 'seamless', 'delve', 'tapestry', 'testament to', 'in today\'s', 'look no further',
    'game-changer', 'game changer', 'cutting-edge', 'cutting edge', 'top-notch', 'second to none', 'unparalleled',
    'revolutioniz', 'world-class', 'best-in-class', 'synergy', 'leverage', 'empower', 'embark', 'journey',
    'nestled', 'bustling', 'vibrant', 'whether you\'re', 'we\'ve got you covered', 'your one-stop',
]
JUNK = [r'\{\{', r'\}\}', r'\bNone\b', r'\bundefined\b', r'\bnull\b', r'lorem ipsum', r'\bTODO\b', r'\bTBD\b', r'\bXXX\b', r'\[insert', r'NaN']
MAX_PAGE = 400_000      # bytes of HTML per page
MAX_IMAGE = 900_000     # bytes per image file


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.text, self.tags, self.stack, self.title, self.ids = [], [], [], '', []
        self.skip = 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self.tags.append((tag, a))
        if a.get('id'):
            self.ids.append(a['id'])
        if tag in ('script', 'style'):
            self.skip += 1
        self.stack.append(tag)

    def handle_endtag(self, tag):
        if tag in ('script', 'style') and self.skip:
            self.skip -= 1
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()

    def handle_data(self, data):
        if self.skip:
            return
        if self.stack and self.stack[-1] == 'title':
            self.title += data
        self.text.append(data)


def check(out_dir, spec=None):
    errors, warnings = [], []
    pages = sorted(f for f in os.listdir(out_dir) if f.endswith('.html'))
    if 'index.html' not in pages:
        errors.append('no index.html')
    spec = spec or {}
    mock = (spec.get('package') or 'mockup') == 'mockup'
    for name in pages:
        path = os.path.join(out_dir, name)
        raw = open(path, encoding='utf-8').read()
        where = lambda msg: f'{name}: {msg}'
        if len(raw.encode()) > MAX_PAGE:
            warnings.append(where(f'page is {len(raw) // 1000} KB, keep it under {MAX_PAGE // 1000} KB'))
        p = Page()
        p.feed(raw)
        text = re.sub(r'\s+', ' ', ' '.join(p.text))
        low = text.lower()

        if '—' in raw or '–' in raw:
            errors.append(where('has an em or en dash'))
        for pat in JUNK:
            m = re.search(pat, text, re.I)
            if m:
                errors.append(where(f'leftover placeholder text "{m.group(0)}"'))
        for b in BANNED:
            if b in low:
                errors.append(where(f'AI-sounding phrase "{b}"'))
        if not re.search(r'<meta name="viewport"[^>]*width=device-width', raw):
            errors.append(where('no mobile viewport tag'))
        if not p.title.strip():
            errors.append(where('no <title>'))
        elif len(p.title) > 70:
            warnings.append(where(f'title is {len(p.title)} characters, aim for 70 or less'))
        if not re.search(r'<meta name="description" content="[^"]{30,}"', raw):
            errors.append(where('missing or too short meta description'))
        if mock and 'noindex' not in raw:
            errors.append(where('mockup page without noindex'))
        if not mock and 'noindex' in raw:
            errors.append(where('client site has noindex'))
        if mock and 'Concept homepage' not in raw:
            errors.append(where('mockup page without the concept ribbon'))
        h1s = [t for t, _ in p.tags if t == 'h1']
        if len(h1s) != 1:
            errors.append(where(f'{len(h1s)} h1 headings, want exactly 1'))

        for tag, a in p.tags:
            if tag == 'img':
                src = a.get('src', '')
                if not a.get('alt', '').strip():
                    errors.append(where(f'image without alt text: {src}'))
                if not src:
                    errors.append(where('image without src'))
                elif not re.match(r'^(https?:|data:)', src):
                    f = os.path.join(out_dir, src.split('?')[0])
                    if not os.path.isfile(f):
                        errors.append(where(f'missing image file {src}'))
                    elif os.path.getsize(f) > MAX_IMAGE:
                        warnings.append(where(f'{src} is {os.path.getsize(f) // 1000} KB, resize it to 1600px wide or less'))
            if tag == 'a':
                href = a.get('href', '')
                if not href or href == '#':
                    errors.append(where('link with an empty href'))
                elif href.startswith('#') and len(href) > 1 and href[1:] not in p.ids:
                    errors.append(where(f'link to missing section {href}'))
                elif href.endswith('.html') and not re.match(r'^https?:', href) and href not in pages:
                    errors.append(where(f'link to missing page {href}'))
                elif href.startswith('tel:') and not re.fullmatch(r'tel:\+1\d{10}', href):
                    errors.append(where(f'bad phone link {href}'))
            if tag in ('input', 'textarea', 'select') and a.get('type') not in ('hidden', 'range') and a.get('name') != '_honey':
                if not a.get('id') or f'for="{a["id"]}"' not in raw:
                    warnings.append(where(f'form field {a.get("name")} has no label'))

        if spec.get('phone'):
            d = re.sub(r'\D', '', spec['phone'])[-10:]
            if f'tel:+1{d}' not in raw:
                errors.append(where('the phone number is not a tap-to-call link'))
        if spec.get('business') and spec['business'].lower().split()[0] not in low:
            errors.append(where('business name does not appear on the page'))
        if not mock and re.search(r'placeholder|goes here|sample illustration', low):
            errors.append(where('client site still has placeholder text'))
        if not mock and 'action="https://formsubmit.co/' not in raw and '<form' in raw:
            errors.append(where('client form has nowhere to send'))

    # Reviews must be quoted word for word from the spec, never written by the agent.
    for r in spec.get('reviews') or []:
        if not r.get('quote', '').strip():
            continue
        if not r.get('source'):
            warnings.append(f'review from {r.get("name", "someone")} has no source (Google, Facebook, ...)')
    return {'pass': not errors, 'pages': pages, 'errors': errors, 'warnings': warnings}


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit('usage: qa.py out_dir [spec.json]')
    spec = json.load(open(sys.argv[2])) if len(sys.argv) == 3 else None
    report = check(sys.argv[1], spec)
    print(json.dumps(report, indent=1))
    sys.exit(0 if report['pass'] else 1)


if __name__ == '__main__':
    main()

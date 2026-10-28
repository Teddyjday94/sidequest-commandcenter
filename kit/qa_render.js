// Sidequest site kit: browser checks for a rendered site folder.
//
//   node qa_render.js out_dir [shots_dir]
//
// Opens every page at phone (390px) and desktop (1280px) width in Chromium and checks for
// sideways scrolling, broken images, text running off screen and tap targets that are too small.
// Saves full-page screenshots to shots_dir (default out_dir/../shots) so the agent can look at them.
// Prints {"pass", "errors", "warnings", "shots"}; exit code 1 when there are errors.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  const dir = path.resolve(process.argv[2] || '.');
  const shots = path.resolve(process.argv[3] || path.join(dir, '..', 'shots'));
  fs.mkdirSync(shots, { recursive: true });
  const pages = fs.readdirSync(dir).filter(f => f.endsWith('.html')).sort();
  const errors = [], warnings = [], files = [];
  const browser = await chromium.launch();
  for (const [label, width, height] of [['phone', 390, 844], ['desktop', 1280, 800]]) {
    const ctx = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1, isMobile: label === 'phone', hasTouch: label === 'phone' });
    for (const name of pages) {
      const page = await ctx.newPage();
      const where = msg => `${name} (${label}): ${msg}`;
      page.on('pageerror', e => errors.push(where('script error ' + e.message)));
      await page.goto('file://' + path.join(dir, name), { waitUntil: 'load', timeout: 30000 }).catch(e => errors.push(where('did not load ' + e.message)));
      await page.waitForTimeout(600);
      const r = await page.evaluate(() => {
        const out = { overflow: 0, wide: [], broken: [], small: [], clipped: [] };
        out.overflow = document.documentElement.scrollWidth - window.innerWidth;
        if (out.overflow > 1) {
          for (const el of document.querySelectorAll('body *')) {
            const b = el.getBoundingClientRect();
            if (b.right > window.innerWidth + 1 && b.width > 0 && getComputedStyle(el).position !== 'fixed') {
              out.wide.push((el.tagName + '.' + (el.className.baseVal ?? el.className)).slice(0, 60));
              if (out.wide.length > 4) break;
            }
          }
        }
        for (const img of document.images) if (img.complete && img.naturalWidth === 0) out.broken.push(img.getAttribute('src'));
        for (const a of document.querySelectorAll('a.btn, button, .callbar a')) {
          const b = a.getBoundingClientRect();
          if (b.width && b.height && b.height < 40) out.small.push(a.textContent.trim().slice(0, 30));
        }
        for (const h of document.querySelectorAll('h1, h2, h3')) {
          if (h.scrollWidth > h.clientWidth + 2) out.clipped.push(h.textContent.trim().slice(0, 40));
        }
        return out;
      });
      if (r.overflow > 1) errors.push(where(`page scrolls sideways by ${r.overflow}px (${r.wide.join(', ')})`));
      for (const b of r.broken) errors.push(where('broken image ' + b));
      for (const c of r.clipped) errors.push(where('heading runs off its box: ' + c));
      if (label === 'phone') for (const s of r.small) warnings.push(where('small tap target: ' + s));
      const shot = path.join(shots, `${name.replace('.html', '')}-${label}.png`);
      await page.screenshot({ path: shot, fullPage: true });
      files.push(shot);
      await page.close();
    }
    await ctx.close();
  }
  await browser.close();
  const report = { pass: errors.length === 0, errors, warnings, shots: files };
  console.log(JSON.stringify(report, null, 1));
  process.exit(report.pass ? 0 : 1);
})();

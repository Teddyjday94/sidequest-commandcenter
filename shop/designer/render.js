// Elsewhere Supply Co. design renderer: turns a design HTML file into print-ready PNGs.
//
//   node render.js designs/<name>.html out_dir
//
// A design file draws its artwork inside #art using CSS pixels where 100px = 1 inch, and colors every
// mark with var(--ink). The renderer saves it at 300 DPI (deviceScaleFactor 3) on a transparent
// background, once with dark ink (for light garments) and once with light ink (for dark garments):
//   <name>-dark-ink.png, <name>-light-ink.png
// It prints the pixel size and print size in inches. Printify wants 300 DPI PNGs; place the file at the
// printed width shown.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const INKS = { 'dark-ink': '#1b1a18', 'light-ink': '#f3eee3' };

(async () => {
  const file = path.resolve(process.argv[2]);
  const out = path.resolve(process.argv[3] || 'out');
  fs.mkdirSync(out, { recursive: true });
  const name = path.basename(file, '.html');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1600, height: 1800 }, deviceScaleFactor: 3 });
  const report = [];
  for (const [label, ink] of Object.entries(INKS)) {
    await page.goto('file://' + file, { waitUntil: 'networkidle' });
    await page.evaluate(async (c) => { document.documentElement.style.setProperty('--ink', c); await document.fonts.ready; }, ink);
    const missing = await page.evaluate(() => [...document.fonts].filter((f) => f.status === 'error').map((f) => f.family));
    if (missing.length) throw new Error('fonts failed to load: ' + missing.join(', '));
    await page.waitForTimeout(300);
    // Nothing may spill outside #art: a clipped letter is a ruined print.
    const spill = await page.evaluate(() => {
      const a = document.getElementById('art').getBoundingClientRect();
      return [...document.querySelectorAll('#art *')].filter((e) => {
        const r = e.getBoundingClientRect();
        return r.width && (r.left < a.left - 1 || r.right > a.right + 1 || r.top < a.top - 1 || r.bottom > a.bottom + 1 || e.scrollWidth > e.clientWidth + 1);
      }).map((e) => (e.textContent || e.tagName).trim().slice(0, 40));
    });
    if (spill.length) throw new Error('artwork spills outside its box: ' + spill.join(' | '));
    const art = page.locator('#art');
    const box = await art.boundingBox();
    const dest = path.join(out, `${name}-${label}.png`);
    await art.screenshot({ path: dest, omitBackground: true });
    report.push({ file: dest, px: [Math.round(box.width * 3), Math.round(box.height * 3)], inches: [+(box.width / 100).toFixed(2), +(box.height / 100).toFixed(2)] });
  }
  await browser.close();
  console.log(JSON.stringify(report, null, 1));
})();

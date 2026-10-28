# Site kit

One renderer and two quality checks that every mockup and client site goes through. The agent writes a spec (facts and short copy); the kit owns layout, palette, type, icons and responsive behavior, so each build starts from a tested design instead of improvised HTML.

```
python3 render.py spec.json out/          # writes out/index.html (+ services, about, contact for "full")
python3 qa.py out/ spec.json              # static checks, exit 1 on errors
node qa_render.js out/ shots/             # Chromium at 390px and 1280px: sideways scroll, broken images, clipped headings, screenshots
```

Live copies for the cloud agents are published as files on the Site Kit artifact (`kit/render.py`, `kit/qa.py`, `kit/qa_render.js`, `kit/sample.json`). After editing here, ask Claude to republish the Site Kit artifact.

## Spec fields

Required: `business`, `slug` (lowercase, hyphens), `niche`, `headline`.

| Field | Notes |
|---|---|
| `package` | `mockup` (default, one page, concept ribbon, noindex), `starter` (one page client site), `full` (index, services, about, contact) |
| `phone`, `email`, `facebook`, `town`, `service_area[]` | From the lead row and case file. Phone becomes tap-to-call |
| `subhead`, `eyebrow`, `hero_chip` | Short hero copy |
| `services[{name, desc}]`, `services_title`, `services_intro` | Their real services. Icons are picked from the words |
| `photos[{file, caption, role}]` | `role`: `logo`, `hero`, `before`, `after`, `gallery`. Files sit next to the pages. Their own photos only |
| `reviews[{quote, name, source}]`, `rating{value, count, source}` | Word for word from a public page. Never write one |
| `trust[]`, `about`, `about_title`, `facts[[label, value]]`, `hours` | |
| `ba_title`, `ba_text`, `gallery_title`, `quote_title`, `quote_text`, `cta_title`, `cta_text` | Optional section copy |
| `form_email` | Client sites: quote form posts to FormSubmit at this address (the owner confirms it once) |
| `brand_colors[]` | Hex colors from their logo or truck; used when they read well |
| `variant`, `font` | Force a layout (`split`, `banner`, `editorial`, `bold`) or font pair. Default is picked from the slug so neighbors look different |
| `meta_description`, `url`, `year` | |

Missing photos or reviews on a mockup show labeled placeholders ("A real customer review goes here"), and the ribbon says so. Client sites never show placeholders; `qa.py` fails them.

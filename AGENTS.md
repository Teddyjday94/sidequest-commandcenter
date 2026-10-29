# AGENTS.md — Sidequest Creative command center

Read this before changing anything. It is the shared guide for Codex, Claude, and any other coding agent working in this repo.

## What this is

An automated sales and marketing crew for Sidequest Creative, a small web design shop in Gonzales, Louisiana (owner: Thomas, thomasdbiz26@gmail.com). Packages: Starter $600, Full $800, 50% deposit. Target niches: lawn care and pressure washing first, then other local service businesses.

The crew finds local businesses with weak or missing websites, finds their contact info, builds free mockup homepages, drafts outreach, and plans social posts. **Thomas sends everything himself.** No agent ever sends.

## Architecture

| Piece | Where it lives | Runs on |
|---|---|---|
| Database (source of truth) | Supabase project `taskvfzqgpqxpdifmxru` (Side Quest Client Portal), schema **`ops`** only | Supabase |
| Lead Scout (no AI) | HomeAdvisor: `ops.run_scout(3)` via pg_cron `ops-lead-scout` (`30 11 * * 1-5` UTC). Google Maps (`ops.run_maps_scout`) is built but off: it needs a Places API key in Supabase Vault (`google_places_api_key`) and the `ops-maps-scout` cron job, and Thomas chose not to set up Google billing | Postgres |
| Yellow Pages scout (no AI) | `ops.run_yp_scout(4)` via pg_cron `ops-yp-scout` (`40 11 * * 1-5`), rotating through `ops.maps_targets` (`yp_last_run`). Keeps nearby businesses with no website or only a Yellow Pages template site, niche from the listing's categories, skips nonprofits; stops on 403/429/503 | Postgres |
| Site Auditor (no AI) | `ops.run_site_audits(10)` via pg_cron `ops-site-auditor` (`44 11 * * 1-5`). Loads each lead's own site and writes plain-English problems to `ops.site_audits`; the Detective and Sales Agent pitch with them | Postgres |
| Contact sweep (no AI) | `ops.harvest_contacts(15)` via pg_cron `ops-contact-sweep` (`47 11 * * 1-5`): reads each open lead's own website (home plus contact/about pages) for a published email (`mailto:` or an address clearly tied to the business, `ops.pick_business_email`) and tap-to-call number; records `contact_source`. The Detective's Contact hunt (playbook 8) searches the web for the rest | Postgres |
| Client site checks (no AI) | `ops.check_client_sites()` via pg_cron `ops-client-sites` (`20 12 * * *`): sets `ops.builds.site_ok` for launched sites; the planner flags any that are down | Postgres |
| Daily Planner (no AI) | `ops.build_todos()` via pg_cron `ops-daily-planner` (`50 11 * * 1-5`) and `ops-afternoon-planner` (`15 21 * * 1-5`) | Postgres |
| Sales Agent (+ Product Launcher every morning, Contact Finder and Directory Scout on Mon/Wed/Fri, Bookkeeper on Fridays, + Reply Watcher) | Claude scheduled task, weekdays 9:17 AM and 1:17 PM CT (Sonnet), cloud. Each morning run starts with the Product Launcher (playbook 12c): any new Elsewhere Supply Co. product not in `ops.shop_launches` gets cleaned copy, SEO, tags, alt text and collections (never prices, status, variants or images). The 1:17 PM run is the Reply Watcher: replies and sent-mail sync only (playbook 4b). Friday mornings start with the Bookkeeper (playbook 11): reads Stripe into `ops.ledger`, drafts the balance invoice at launch and payment reminders. On Mon/Wed/Fri it runs the playbook's Contact Finder and Directory Scout (Facebook, Yelp, Nextdoor, BBB, Thumbtack, Angi, Yellow Pages via WebSearch, rotating through `ops.maps_targets`) sections first with WebSearch/WebFetch | Claude |
| Detective + Mockup + Site Builder | Claude scheduled task, Tue/Thu 8:33 AM CT (Sonnet). The Detective first writes case files (`ops.dossiers`) on up to 5 leads from public business sources only, then hunts the web for published emails and phones on up to 15 leads that have none; then it builds the next won client's site (`site-*` Vercel project, login wall stays on), then up to 3 prospect mockups (`mockup-*`, public). Every page is rendered with the Site kit (`kit/`) and must pass `qa.py` and `qa_render.js` before it deploys. Lead Desk's **Build it now** fires this task on demand (`fire_trigger` with "On-demand mockup for lead L<n>") so one mockup is ready in about half an hour | Claude |
| Content Agent + Strategist + Client Care + Trend Scout | Claude scheduled task, Sunday 5:43 PM CT (Sonnet). After the posts, the Strategist reads `ops.scorecard` and rewrites `ops.settings` 'lessons', which the Sales Agent, Detective and Scouts read every run (playbook 9). Then Client Care (playbook 10) drafts review requests and 30-day check-ins for launched clients. Then the Trend Scout (playbook 12) writes up to 5 risk-checked shirt ideas for Elsewhere Supply Co. into `ops.shop_ideas`, and the Shop Designer (12b) makes illustrated artwork with Artlist image models for ideas Thomas asked for (`design_requested`), turns it into 300 DPI transparent PNGs with `shop/designer/prep_print.py`, and uploads them to the Idea Board's asset store. The Idea Board's **Design it now** fires this task on demand ("On-demand design for shop idea <id>"). Then the Social Planner (12d) writes next week's Elsewhere posts into `ops.shop_posts`, and the Blog Writer (12e) publishes one gift guide or SEO post to the store blog (tracked in `ops.shop_articles`) | Claude |
| Dashboard | Claude Dashboard artifact https://claude.ai/artifact/LjDPvPRUYEfi4DPcsrtYmN, reads Supabase live (read only) | claude.ai |
| Lead Desk | Artifact https://claude.ai/artifact/My8ufd1itRBDSTHAK9VJ5E (`lead-desk/index.html`). Thomas's buttons: emailed, called, messaged, replied, won, lost, opted out, make a mockup, plus My notes, photo uploads for mockups, and an Email box (the Sales Agent's ready email for every lead, add an address with `ops.lead_set_email`, one-click Gmail draft through his Gmail connector, recorded by `ops.lead_set_draft`). Calls `ops.lead_action(id, action, package)` through his Supabase connector. **Call Mode** works the day's calls, texts and Facebook messages one lead at a time and records each with `ops.lead_touch(id, channel, result)` (logged in `ops.touches`), which schedules the next step on the plan (`next_channel`, `next_followup`: call, text, email or Facebook, call, last text) | claude.ai |
| Site Kit | Artifact https://claude.ai/artifact/MZ24NG8rcY1FfEAchwRPDV (`kit/page/index.html`). Previews of the four layouts, and the published copies of `kit/render.py`, `kit/qa.py`, `kit/qa_render.js`, `kit/README.md`, `kit/sample.json` that the builder downloads each run | claude.ai |
| Elsewhere Idea Board | Artifact https://claude.ai/artifact/MMqakwJ9ANhygv7aN9rfi4 (`shop/idea-board/index.html`). Thomas's second business: Elsewhere Supply Co., Shopify store `elsewheresupplyco.myshopify.com`, apparel printed and shipped by Printify. Shows the Trend Scout's shirt ideas with design briefs, risk checks and listing copy; Thomas marks Like, Pass or Made through `ops.shop_idea_mark(id, status, note, handle)`, asks for artwork with `ops.shop_idea_design(id, feedback)`, saves print files (`design_url`) with the page's downloads capability, and works the social plan in its Posts tab (`ops.shop_posts`, marked with `ops.shop_post_mark`). Draft store policies wait for his approval in `shop/policies/`. Agents never create, edit, price or discount anything in the store; brand notes in `ops.settings` 'shop_brand', learnings in 'shop_lessons' | claude.ai |
| Sidequest HQ | Artifact https://claude.ai/artifact/9oM7nvYymhhT1cB25Js7zj (`hq/index.html`). Game view of the crew in the "Aether Archipelago" art Thomas supplied (`hq/assets/`, published as the artifact's files): one floating island and animated robot sprite per agent around his central nexus, a mission board (queued, working, review), XP and levels computed from real `ops` data, quests from `ops.todos`, a weekly raid from `ops.weekly_stats`, achievements. Read only, one SQL query every 90s | claude.ai |

Agent prompts are short: each one reads the playbook, then does only its own section. The **playbook is the real logic**.

**Dormant: job queue + Windows worker.** The `ops` tables `missions`, `jobs`, `job_events`, `workflows`, `approvals`, `evidence`, `memory_items`, `inbound_messages`, `worker_devices` and `autonomy_events`, and the `ops.agents` rows with hyphenated ids (`sales-agent`, `contact-finder`, and so on), belong to a second crew built in Codex that runs through a local worker on Thomas's PC. On 2026-10-26 Thomas chose the Claude scheduled tasks above as the one live crew, and every mission was disabled. Worker results never write to `ops.leads`. Keep its missions off unless Thomas decides to switch, so the two crews don't both draft outreach to the same leads.

## Repo layout

```
playbook/PLAYBOOK.md        the instructions every Claude agent follows (live copy: artifact store "ops/playbook")
agents/*.md                 the scheduled-task prompts (for reference; live copies live in Claude scheduled tasks)
supabase/migrations/        ops schema, functions (scout + planner), seed data and cron jobs
dashboard/index.html        dashboard page (live copy: files/index.html in the dashboard artifact)
dashboard/datasets.json     the 7 live SQL queries the dashboard runs
lead-desk/index.html        Lead Desk page (republish with the Artifact tool, same URL)
kit/                        Site kit: render.py (spec to site), qa.py + qa_render.js (quality gate), README (spec fields), page/ (Site Kit artifact)
shop/idea-board/index.html  Elsewhere Idea Board (republish with the Artifact tool, same URL; shop/designer/prep_print.py is published with it)
hq/index.html               Sidequest HQ game view (republish with the Artifact tool, same URL, with hq/assets/* as files)
```

## How edits reach production

This repo is a mirror and a workbench. Nothing deploys from git automatically.

- **SQL (`supabase/migrations/`)**: add a NEW migration file (timestamped name) rather than editing old ones. Apply it with the Supabase CLI (`supabase db push` against project `taskvfzqgpqxpdifmxru`) or ask Claude to apply it. Functions use `create or replace`, so re-applying is safe.
- **Playbook**: edit `playbook/PLAYBOOK.md`, then ask Claude to "sync the playbook to the artifact store" (it writes the file into the dashboard artifact's `ops/playbook` doc, which the agents read each run). Keep the existing section headings; old agent prompts look them up by name.
- **Dashboard**: edit `dashboard/index.html`, then ask Claude to republish it to the dashboard artifact. The page uses the Claude Dashboard runtime (`dash.loader`, `dash.calc`, `dash.onData`), so it will not run as a plain local HTML file.
- **Agent prompts**: edit `agents/*.md`, then ask Claude to update the matching scheduled task.
- **Site kit**: edit `kit/*`, render `kit/examples/sample-pressure.json` with each `variant` and run both checks, then republish the Site Kit artifact (same URL, the kit files in `files`) so the builder picks it up.
- **Mockups**: built by the Tue/Thu task (or on demand from Lead Desk's Build it now) only for leads Thomas requests in Lead Desk (`mockup_requested`), using photos he uploads there (`ops.lead_photos`, files in the Lead Desk asset store). Each deploys to the Vercel project `mockup-<slug>` (team `team_JpoOV9VCUX3FeIX8tsXZRIkv`). On 2026-10-26 Thomas had all earlier mockups taken down.

## Hard rules (do not break these)

1. Never send emails, DMs, texts or posts. Gmail drafts only.
2. Supabase: only read/write the `ops` schema (the one exception: the dormant `ops.run_maps_scout` reads its API key from Supabase Vault, which Thomas would add himself). **Never touch `public`** — that is Thomas's live client portal. No DROP/TRUNCATE of ops tables without Thomas saying so.
3. Stripe: create customers and **draft** invoices only. Never finalize, send, pay, void, refund or delete.
4. Vercel: turning off login protection is allowed **only** for projects named `mockup-*`. Client `site-*` projects keep it on.
5. Never bypass CAPTCHAs or bot checks (the scout stops on 403/429/503 by design).
6. Never record a personal home street address. Opted-out leads are never contacted again.
7. Never invent reviews, quotes or facts. Copy has no em dashes and no AI-sounding phrasing; tone is slightly laid back but professional.
8. **No secrets in this repo.** No API keys, tokens, `.env` files or service-role keys. Connections are handled by the Claude connectors or your local Supabase CLI login.

## Key data

- `ops.leads` — one row per prospect (id `L01`…, stage, score, heat, hook, contact info, draft ids). New ids: `select ops.next_lead_id()`.
- Stages: New → Audited → Mockup ready → Contacted → Replied → Proposal sent → Won (plus Lost, Opted out).
- Scoring and heat rules are in the playbook. `ops.heat_for(score)`: Hot 78+, Warm 55–77, Cold <55.
- `ops.dossiers` — the Detective's case file per lead (owner as published, history, services, the business's own photos, reviews, rivals, pitch angles, sources). Read by the Sales Agent, Mockup Builder, Site Builder, dashboard and Lead Desk.
- `ops.builds` — one row per won client, opened by the `leads_stage_log` trigger when a lead's stage becomes Won. `ops.lead_events` — stage history written by that trigger. `ops.weekly_stats` — view of the last 8 weeks for the dashboard and the Friday brief.
- `ops.scorecard` / `ops.lead_outcomes` — results by niche, town, source, pitch angle (`ops.leads.pitch_angle`) and heat. `ops.settings` 'lessons' — the Strategist's notes. `ops.lead_priority(l)` / `ops.lead_next_move(l)` — live next-best-move score and action per lead; Lead Desk and HQ sort by it.
- `ops.site_audits` (lead website checks), `ops.ledger` (one row per Stripe invoice), `ops.settings` 'google_review_link' and 'care_plan_offer' (Thomas fills these in; blank means agents never invent one).
- `ops.agents`, `ops.activity`, `ops.posts`, `ops.todos` (rebuilt by `build_todos`, don't write it directly), `ops.settings`, `ops.clients` (never prospect these), `ops.scout_targets`, `ops.near_cities`.

## Working tips

- Test SQL against a Supabase branch or locally before running it on the live project.
- The dashboard parses Supabase MCP answers that wrap JSON in `<untrusted-data-…>` tags; see `sbRows` in `dashboard/index.html` before changing the loader.
- Keep Claude usage low: anything mechanical belongs in Postgres, not in a Claude run.

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
| Daily Planner (no AI) | `ops.build_todos()` via pg_cron `ops-daily-planner` (`50 11 * * 1-5`) and `ops-afternoon-planner` (`15 21 * * 1-5`) | Postgres |
| Sales Agent (+ Contact Finder and Directory Scout on Mon/Wed/Fri) | Claude scheduled task, weekdays 9:17 AM CT (Sonnet), cloud. On Mon/Wed/Fri it runs the playbook's Contact Finder and Directory Scout (Facebook, Yelp, Nextdoor, BBB, Thumbtack, Angi, Yellow Pages via WebSearch, rotating through `ops.maps_targets`) sections first with WebSearch/WebFetch | Claude |
| Detective + Mockup + Site Builder | Claude scheduled task, Tue/Thu 8:33 AM CT (Sonnet). The Detective first writes case files (`ops.dossiers`) on up to 5 leads from public business sources only; then it builds the next won client's site (`site-*` Vercel project, login wall stays on), then up to 3 prospect mockups (`mockup-*`, public) | Claude |
| Content Agent | Claude scheduled task, Sunday 5:43 PM CT (Sonnet) | Claude |
| Dashboard | Claude Dashboard artifact https://claude.ai/artifact/LjDPvPRUYEfi4DPcsrtYmN, reads Supabase live (read only) | claude.ai |
| Lead Desk | Artifact https://claude.ai/artifact/My8ufd1itRBDSTHAK9VJ5E (`lead-desk/index.html`). Thomas's buttons: emailed, called, messaged, replied, won, lost, opted out, make a mockup, plus My notes and photo uploads for mockups. Calls `ops.lead_action(id, action, package)` through his Supabase connector | claude.ai |

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
```

## How edits reach production

This repo is a mirror and a workbench. Nothing deploys from git automatically.

- **SQL (`supabase/migrations/`)**: add a NEW migration file (timestamped name) rather than editing old ones. Apply it with the Supabase CLI (`supabase db push` against project `taskvfzqgpqxpdifmxru`) or ask Claude to apply it. Functions use `create or replace`, so re-applying is safe.
- **Playbook**: edit `playbook/PLAYBOOK.md`, then ask Claude to "sync the playbook to the artifact store" (it writes the file into the dashboard artifact's `ops/playbook` doc, which the agents read each run). Keep the existing section headings; old agent prompts look them up by name.
- **Dashboard**: edit `dashboard/index.html`, then ask Claude to republish it to the dashboard artifact. The page uses the Claude Dashboard runtime (`dash.loader`, `dash.calc`, `dash.onData`), so it will not run as a plain local HTML file.
- **Agent prompts**: edit `agents/*.md`, then ask Claude to update the matching scheduled task.
- **Mockups**: built by the Tue/Thu task only for leads Thomas requests in Lead Desk (`mockup_requested`), using photos he uploads there (`ops.lead_photos`, files in the Lead Desk asset store). Each deploys to the Vercel project `mockup-<slug>` (team `team_JpoOV9VCUX3FeIX8tsXZRIkv`). On 2026-10-26 Thomas had all earlier mockups taken down.

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
- `ops.agents`, `ops.activity`, `ops.posts`, `ops.todos` (rebuilt by `build_todos`, don't write it directly), `ops.settings`, `ops.clients` (never prospect these), `ops.scout_targets`, `ops.near_cities`.

## Working tips

- Test SQL against a Supabase branch or locally before running it on the live project.
- The dashboard parses Supabase MCP answers that wrap JSON in `<untrusted-data-…>` tags; see `sbRows` in `dashboard/index.html` before changing the loader.
- Keep Claude usage low: anything mechanical belongs in Postgres, not in a Claude run.

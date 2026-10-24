# Sidequest Creative command center

The agent crew that finds, contacts and closes web design clients for Sidequest Creative (Gonzales, LA).

- **Dashboard:** https://claude.ai/artifact/LjDPvPRUYEfi4DPcsrtYmN
- **Database:** Supabase, schema `ops` in the Side Quest Client Portal project
- **Free jobs (no AI):** Lead Scout and Daily Planner run inside Postgres on a schedule
- **AI agents:** Contact Finder, Sales Agent, Mockup Builder, Content Agent (about 10 runs a week)
- **No-purchase Codex path:** `runner/run-agent.ps1` pins the built-in OpenAI provider, requires ChatGPT authentication, and refuses API-key or custom-provider routing

Agents prepare everything (leads, drafts, call scripts, mockups, post plans). Thomas reviews and sends.

Start with [AGENTS.md](AGENTS.md) for how the pieces fit together, the safety rules, and how to push changes live.

To move the scheduled agents from Claude to existing ChatGPT/Codex usage, see [docs/CODEX_SETUP.md](docs/CODEX_SETUP.md). The existing Claude jobs can stay active until each Codex replacement has completed one reviewed test run.

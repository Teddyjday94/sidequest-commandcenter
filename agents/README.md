# Scheduled agents (Claude scheduled tasks)

These are the prompts each Claude scheduled task sends when it fires. The live copies live in Claude (claude.ai > scheduled tasks). If you change one here, paste it into that task too, or ask Claude to update it.

| Agent | Schedule (Central) | Model | Needs PC |
|---|---|---|---|
| Sales Agent (does Contact Finder first on Mon, Wed, Fri) | Weekdays 9:17 AM | Sonnet | No |
| Detective + Mockup + Site Builder | Tue, Thu 8:33 AM | Sonnet | No |
| Content Agent | Sundays 5:43 PM | Sonnet | No |

Paused (kept for reference, replaced by the database jobs and the Sales Agent): Contact Finder (old PC-bound task), Lead Scout, Site Auditor, Outreach Agent, Closer, Chief of Staff.

All three read `playbook/PLAYBOOK.md`, whose live copy is stored in the dashboard artifact (collection `ops`, doc `playbook`).

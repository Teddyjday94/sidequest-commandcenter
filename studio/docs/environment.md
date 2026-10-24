# Studio environment

The studio is not linked or deployed by this repository setup. Configure values only in a local ignored environment file or as environment-scoped Vercel variables after separate deployment approval.

| Variable | Exposure | Purpose |
| --- | --- | --- |
| `SUPABASE_URL` | Server only | Supabase project URL used by the authenticated API. |
| `SUPABASE_ANON_KEY` | Server configuration | Public Supabase client key reserved for the later browser-session bootstrap. |
| `SUPABASE_SERVICE_ROLE_KEY` | Secret, server only | Private-schema broker access. Never prefix with `VITE_`. |
| `COMMAND_CENTER_OWNER_USER_ID` | Server only | UUID of the only Supabase Auth user allowed into the command center. |
| `SESSION_CSRF_SECRET` | Secret, server only | At least 32 characters, used to sign owner-bound CSRF tokens. Never prefix with `VITE_`. |

Do not commit `.env`, `.env.local`, tokens, keys, or copied production values. Preview and production secrets must be configured independently at the activation checkpoint.

# Studio environment

The studio is not linked or deployed by this repository setup. Configure values only in a local ignored environment file or as environment-scoped Vercel variables after separate deployment approval. This document records names and boundaries, never secret values.

| Variable | Exposure | Purpose |
| --- | --- | --- |
| `SUPABASE_URL` | Server only | Supabase project URL used by the authenticated API. |
| `SUPABASE_ANON_KEY` | Server configuration | Public Supabase client key reserved for a separately approved browser-session bootstrap. |
| `SUPABASE_SERVICE_ROLE_KEY` | Secret, server only | Private-schema broker access. Never prefix with `VITE_`. |
| `COMMAND_CENTER_OWNER_USER_ID` | Server only | UUID of the only Supabase Auth user allowed into the command center. |
| `SESSION_CSRF_SECRET` | Secret, server only | At least 32 characters, used to sign owner-bound CSRF tokens. Never prefix with `VITE_`. |

Do not commit `.env`, `.env.local`, tokens, keys, or copied production values. Preview and production secrets must be configured independently at the activation checkpoint.

## Browser session boundary

Every read requires a valid Supabase bearer session whose user ID exactly matches `COMMAND_CENTER_OWNER_USER_ID`. Every mutation also requires the owner-bound `sq_csrf` cookie and matching `x-csrf-token` header. The browser receives only the normalized `StudioSnapshot`; it never receives the service-role key, worker hashes, mission input, arbitrary settings, raw job input/output, or event details.

The current UI accepts an already-issued owner access token for the lifetime of the browser tab. Issuing that session and its CSRF cookie is intentionally left for the separately approved preview/authentication checkpoint. Do not work around that gate by embedding a token or secret in `VITE_*`, HTML, source code, or a URL.

## Local verification

From `studio/`:

```powershell
npm ci
npm test
npm run typecheck
npm run build
npm run test:browser
```

Local browser tests use installed Chrome. CI installs an isolated Chromium build. Neither path calls a live Supabase or Vercel project.

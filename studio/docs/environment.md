# Studio environment

The studio is not linked or deployed by this repository setup. Configure values only in a local ignored environment file or as environment-scoped Vercel variables after separate deployment approval. This document records names and boundaries, never secret values.

| Variable | Exposure | Purpose |
| --- | --- | --- |
| `SUPABASE_URL` | Server only | Supabase project URL used by the authenticated API. |
| `SUPABASE_ANON_KEY` | Server configuration | Supabase publishable key used by server-side configuration checks. |
| `SUPABASE_SERVICE_ROLE_KEY` | Secret, server only | Supabase secret key for private-schema broker access. Never prefix with `VITE_`. |
| `COMMAND_CENTER_OWNER_EMAIL` | Server only | Verified email of the only Supabase Auth account allowed into the command center. |
| `COMMAND_CENTER_OWNER_USER_ID` | Server only, optional | Stronger UUID allowlist when the owner user ID is known. Either this or the owner email is required. |
| `SESSION_CSRF_SECRET` | Secret, server only | At least 32 characters, used to sign owner-bound CSRF tokens. Never prefix with `VITE_`. |
| `VITE_SUPABASE_URL` | Browser-safe | Supabase project URL used by the login form. |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Browser-safe | Publishable key used only for Supabase Auth in the browser. Never use a secret or service-role key here. |

Do not commit `.env`, `.env.local`, tokens, keys, or copied production values. Preview and production secrets must be configured independently at the activation checkpoint.

## Browser session boundary

The login form signs in with the existing Sidequest client-portal email and password through Supabase Auth. The browser keeps the resulting session in session storage, then `/api/session` verifies the server-side owner allowlist and sets the owner-bound `sq_csrf` cookie. Every read requires that valid owner bearer session. Every mutation also requires the matching CSRF cookie and header. The browser receives only the normalized `StudioSnapshot`; it never receives the server secret key, worker hashes, mission input, arbitrary settings, raw job input/output, or event details.

Do not copy access tokens into the UI. Sign in with the existing owner account instead. Only the project URL and publishable key may use the `VITE_*` prefix; never place the Supabase secret key, CSRF secret, password, or session token in browser-exposed variables, HTML, source code, or a URL.

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

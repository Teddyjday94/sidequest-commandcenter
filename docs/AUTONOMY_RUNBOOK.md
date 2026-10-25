# Sidequest autonomy operations runbook

## Current delivery state

This branch contains guarded recurring-mission procedures, a narrow worker broker, native Windows credential storage, owner-only control routes, and a real-state Studio interface. Everything remains dormant by default: no live database migration, deployment, worker enrollment, task schedule, cron schedule, or canary workflow has been activated.

The system may autonomously create and process only internal `research`, `qualification`, `draft`, and `review` jobs. Sending, publishing, purchases, deployment, payment, refunds, invoice finalization, and any other external state change remain approval-gated and manually completed by the owner.

## Hard limits

The database is authoritative. Browser and worker payloads cannot raise these limits.

| Control | Default |
| --- | --- |
| Emergency stop | Off until explicitly engaged |
| Daily mission-job cap | 12 |
| Maximum attempts | 3 |
| Runtime lease | 15 minutes |
| Operating window | 07:00–20:00 America/Chicago |
| Minimum mission cadence | 15 minutes |
| Maximum mission cadence | 7 days |

Recurring missions are disabled unless their row is explicitly enabled. A due slot uses a deterministic idempotency key, so repeating the same dispatcher tick does not create a second job.

## Emergency stop

Use the Studio’s **Stop automation** control when the queue should stop accepting new work. The database then:

- creates no new mission jobs;
- offers no queued jobs to a worker;
- rejects a new claim;
- allows an already-running, correctly leased claim to remain identifiable so its result can be handled safely.

The change is recorded in `ops.autonomy_events`. Running work may finish, so inspect the live ledger and current jobs after engaging the stop. Resume only after the triggering condition is understood.

If the Studio is unavailable, an authorized operator can call `ops.set_emergency_stop(true, <owner-user-id>)` through a separately authenticated administrative database session. Never expose this procedure directly to `anon` or `authenticated`; grants remain service-role only.

## Worker enrollment and revocation

Enrollment is a future, separate checkpoint. Generate one opaque token outside this repository, store only its SHA-256 hash in the intended `ops.worker_devices` row, and assign only explicit `kind:<job-kind>` or `agent:<agent-id>` capabilities. State-changing jobs are never worker-eligible. Pass the raw token once through the interactive script:

```powershell
.\runner\enroll-worker.ps1 -WorkerId <registered-worker-id>
```

The script reads the token as a secure string and stores it in Windows Credential Manager under `SidequestCommandCenterWorker`. Do not pass the raw token on a command line, place it in an environment file, paste it into an agent prompt, or record it in an issue.

The broker base URL must use HTTPS. Plain HTTP is accepted only for an explicit loopback address during local development; the broker rejects any other HTTP destination before reading or sending the credential.

To revoke a device, set that exact worker row’s status to `revoked` through an authenticated administrative database session. Confirm the worker endpoints return `401` before removing the matching Windows credential. Re-enrollment requires a new token and a new stored hash; do not reactivate or reuse the old token.

## Scheduling and PC-off behavior

No cron or Windows task is installed by this branch.

For a preview, invoke `ops.dispatch_due_missions(now())` manually from the isolated database test environment and run one worker turn under supervision. If future scheduling is approved, use the supported Supabase Cron functions rather than editing `cron.job` directly, and keep a single dispatcher cadence at or above 15 minutes.

The local worker depends on the Windows PC and Codex/ChatGPT authentication. When the PC is off or asleep:

- queued jobs remain in Postgres;
- no local model usage occurs;
- an expired lease can be recovered by the existing queue recovery procedure;
- the Studio reports stale/offline worker state from server time;
- the next approved worker heartbeat can claim eligible queued work after the PC returns.

Do not disable any existing Claude task until its replacement has three consecutive reviewed runs with no duplicate, unsupported-claim, safety-boundary, or unexplained-blocker failure, plus one deliberate blocked-path test.

## No-purchase model boundary

`runner/run-agent.ps1` permits only Codex using existing ChatGPT authentication, the built-in `openai` provider, official ChatGPT endpoints, and `on-request` approval. It refuses `CODEX_API_KEY`, `OPENAI_API_KEY`, and `OPENAI_BASE_URL`. Do not add paid API keys, model gateways, hosted GPU services, premium plugins, or usage-based providers without a new explicit approval.

An empty queue must exit before invoking a model. Mission dispatch itself is database work and consumes no Codex or Claude allowance.

## Rollback

Use the smallest reversible action first:

1. Engage the emergency stop.
2. Disable the affected mission rows.
3. Revoke the affected worker device.
4. Disable the exact future Windows task or cron job, if one was separately installed.
5. Keep the database history and audit events; do not delete evidence while diagnosing.
6. Roll back the preview deployment or migration only with a reviewed, project-specific rollback plan.

Do not use broad destructive Git or database commands. Existing Claude tasks remain the fallback until the cutover criteria are satisfied.

## Four independent activation checkpoints

Each item requires its own fresh approval and target verification immediately before mutation:

1. **Supabase migration:** verify the project reference and apply the reviewed migrations to the intended environment.
2. **Vercel preview and owner auth:** verify project/environment names, configure server-only variables, deploy preview only, and establish the owner session plus CSRF flow.
3. **Windows worker:** verify the device row, enroll one token, and install only the specifically reviewed local schedule.
4. **Canary missions:** enable selected missions and a maximum-five-lead canary after the first three checkpoints pass.

Approval of one checkpoint does not authorize any other checkpoint. Production promotion, external sends, purchases, and disabling legacy automation are never implied.

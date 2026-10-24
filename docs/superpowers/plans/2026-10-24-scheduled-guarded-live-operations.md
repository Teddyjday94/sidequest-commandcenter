# Scheduled, Guarded Live Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add recurring internal missions, enforce hard autonomy limits and an emergency stop, and present real agent rooms, live job states, activity history, and approvals in the standalone studio.

**Architecture:** Keep `ops` as the private source of truth. A device-specific HTTPS broker is the only worker entry point; recurring missions create bounded jobs through fixed database procedures; owner-only routes expose control mutations; the browser renders a whitelisted snapshot and never receives a service-role credential. The UI is a functional warm studio map, not a decorative simulation: every room and timeline item maps to stored agent, job, event, or approval state.

**Tech Stack:** PostgreSQL/Supabase private `ops` schema, Vercel Node Web handlers, TypeScript 7, vanilla web components/DOM, Vitest 5, Playwright 1.64, PowerShell 7 and Windows PowerShell 5.1.

**Spec:** `docs/superpowers/specs/2026-10-23-autonomous-agent-studio-design.md`

## Global Constraints

- No purchase, plan upgrade, paid API fallback, or API-key model billing.
- Automated work is limited to research, qualification, drafts, internal review, and internal state updates.
- Sending, publishing, purchasing, invoicing, payment movement, and production deployment always require Thomas's approval and remain manually completed in this release.
- Only the private `ops` schema may change. Never touch `public`.
- No live Supabase migration, Vercel deployment, Windows schedule installation, worker enrollment, or canary activation in this implementation pass.
- Raw worker tokens stay in Windows Credential Manager and never enter Git, prompts, result files, browser JavaScript, or logs.
- All schedules and human-facing times use `America/Chicago`.
- UI copy uses sentence case, contains no em dashes, and uses no pulsing status dots or generic KPI strip.

## Review Focus

- A revoked, malformed, or mismatched worker credential must fail before any job procedure is called.
- Emergency stop must prevent new dispatch and claim work while preserving history and allowing no external action.
- Daily limits, retry limits, and runtime leases must be enforced server-side, not trusted to browser or worker input.
- A repeated mission dispatch for the same due slot must create one job only.
- Offline, partial, empty, loading, error, and approval-needed states must remain understandable on desktop and mobile.

---

### Task 1: Secure worker broker

**Files:**
- Create: `studio/api/_lib/worker-auth.ts`
- Create: `studio/api/worker-offer.ts`
- Create: `studio/api/worker-claim.ts`
- Create: `studio/api/worker-heartbeat.ts`
- Create: `studio/api/worker-result.ts`
- Create: `studio/api/worker-fail.ts`
- Create: `studio/tests/unit/worker-routes.test.ts`
- Create: `runner/SidequestBroker.psm1`
- Create: `runner/enroll-worker.ps1`
- Create: `tests/Broker.Tests.ps1`

**Interfaces:**
- Consumes: `ops.worker_devices`, `ops.offer_job(text)`, `ops.claim_job(text, uuid)`, `ops.heartbeat_job(text, uuid)`, `ops.complete_job(text, uuid, jsonb)`, and `ops.fail_job(text, uuid, text, text, boolean)`.
- Produces: authenticated worker Web handlers and PowerShell functions `Get-SidequestOffer`, `Claim-SidequestJob`, `Send-SidequestHeartbeat`, `Submit-SidequestResult`, and `Fail-SidequestJob`.

- [ ] Write TypeScript tests for missing, malformed, unknown, disabled, and revoked worker tokens; valid offer and atomic claim; wrong-worker heartbeat/result; capped result bodies; and redacted errors.
- [ ] Run `npm --prefix studio test -- worker-routes.test.ts` and verify RED because the worker routes do not exist.
- [ ] Implement SHA-256 token hashing, fixed-form authorization parsing, active-device lookup, last-seen update, capped JSON parsing, and calls to fixed procedure names only.
- [ ] Run the worker route test and the complete studio suite; verify GREEN.
- [ ] Write PowerShell tests for `204`, typed `401/409/429/5xx`, token redaction, and request shapes; run both PowerShell editions and verify RED.
- [ ] Implement the broker module and an interactive enrollment script that stores the token in Windows Credential Manager, clears the variable, and never writes it to disk or history.
- [ ] Run both PowerShell editions and verify GREEN.
- [ ] Commit `feat: add secure worker broker`.

### Task 2: Recurring missions and hard autonomy controls

**Files:**
- Create via `supabase migration new ops_missions_and_controls`: `supabase/migrations/<generated>_ops_missions_and_controls.sql`
- Create: `supabase/tests/ops_missions_controls_test.sql`
- Modify: `.github/workflows/db-tests.yml`

**Interfaces:**
- Consumes: `ops.workflows`, `ops.jobs`, `ops.job_events`, `ops.settings`, and existing queue procedures.
- Produces: `ops.missions`; `ops.dispatch_due_missions(timestamptz)`; `ops.set_mission_enabled(text, boolean, uuid)`; `ops.set_emergency_stop(boolean, uuid)`; `ops.get_autonomy_status()`; fixed defaults for daily job limit, maximum retry attempts, runtime lease, and the America/Chicago operating window.

- [ ] Write pgTAP coverage for one-job-per-due-slot idempotency, disabled missions, emergency stop, daily limit, server-side retry cap, operating window, owner audit events, and service-role-only execution.
- [ ] Run the database test in GitHub Actions and verify RED against the missing migration.
- [ ] Create the migration with the Supabase CLI, implement private tables and security-definer procedures with `search_path = ''`, and revoke `PUBLIC`, `anon`, and `authenticated` execution.
- [ ] Extend offer and claim behavior so emergency stop and server-side limits cannot be bypassed by a worker or browser payload.
- [ ] Run pgTAP, concurrent claim, lint, and advisors in GitHub Actions; verify GREEN.
- [ ] Commit `feat: add guarded recurring missions`.

### Task 3: Owner controls and snapshot expansion

**Files:**
- Create: `studio/api/mission-toggle.ts`
- Create: `studio/api/emergency-stop.ts`
- Create: `studio/tests/unit/autonomy-routes.test.ts`
- Modify: `studio/api/snapshot.ts`
- Modify: `studio/src/types.ts`
- Modify: `studio/tests/unit/snapshot.test.ts`

**Interfaces:**
- Consumes: Task 2 procedures plus existing owner authentication and CSRF enforcement.
- Produces: owner-only mission toggle and emergency-stop routes; whitelisted `missions` and `autonomy` snapshot DTOs.

- [ ] Write tests proving non-owner and CSRF failures happen before database calls, route bodies are capped and canonical, procedure names are fixed, repeated mutations are idempotent, and snapshot output strips arbitrary database fields.
- [ ] Run focused tests and verify RED.
- [ ] Implement the owner routes and DTO mapping without exposing mission input, credentials, arbitrary settings, or procedure selection.
- [ ] Run all studio tests, strict typecheck, and build; verify GREEN.
- [ ] Commit `feat: add autonomy control API`.

### Task 4: Live studio shell and operational views

**Files:**
- Create: `studio/index.html`
- Create: `studio/src/main.ts`
- Create: `studio/src/lib/api.ts`
- Create: `studio/src/lib/store.ts`
- Create: `studio/src/components/app-shell.ts`
- Create: `studio/src/components/morning-brief.ts`
- Create: `studio/src/components/studio-floor.ts`
- Create: `studio/src/components/agent-workbench.ts`
- Create: `studio/src/components/live-ledger.ts`
- Create: `studio/src/components/approval-dock.ts`
- Create: `studio/src/components/autonomy-controls.ts`
- Create: `studio/src/styles.css`
- Create: `studio/tests/unit/studio-view-model.test.ts`
- Create: `studio/tests/browser/studio.spec.ts`

**Interfaces:**
- Consumes: the whitelisted snapshot and owner mutation routes.
- Produces: responsive studio rooms, real agent/job states, chronological activity, approval dock, mission controls, emergency stop, and an anchored agent workbench.

- [ ] Write unit tests for deterministic room assignment, real state labels, worker-offline calculation, brief priority, event chronology, approval risk order, and emergency-stop copy; verify RED.
- [ ] Implement the state/store layer and semantic DOM components with loading, empty, partial, error, disabled, permission, and reduced-motion behavior.
- [ ] Apply the design contract: warm charcoal/parchment/moss/rust palette with one chartreuse control accent; editorial brief typography; compact control typography; no fake metrics, decorative conversations, generic card grid, or pulsing dots.
- [ ] Run unit tests, strict typecheck, and build; verify GREEN.
- [ ] Write browser tests for keyboard navigation, agent workbench, timeline, approval controls, emergency-stop confirmation, desktop layout, and mobile reflow; verify RED then GREEN.
- [ ] Render desktop and mobile states locally and fix visible clipping, overlap, contrast, and inert controls.
- [ ] Commit `feat: add live autonomous studio`.

### Task 5: Integrated verification and activation-safe handoff

**Files:**
- Modify: `studio/docs/environment.md`
- Create: `docs/AUTONOMY_RUNBOOK.md`
- Modify: `.github/workflows/db-tests.yml`

**Interfaces:**
- Consumes: Tasks 1 through 4.
- Produces: repeatable CI checks, setup documentation, rollback instructions, and four separate future activation checkpoints.

- [ ] Add CI coverage for studio tests/typecheck/build and both PowerShell editions where supported.
- [ ] Document owner environment names, worker enrollment/revocation, mission defaults, emergency stop, preview-only scheduling, PC-off behavior, rollback, and the no-purchase boundary without recording values.
- [ ] Run every studio, PowerShell, database, concurrency, lint, advisor, and build check available to this branch.
- [ ] Scan Git history and tracked files for credential patterns and forbidden external-action implementations.
- [ ] Request a whole-branch code/security review, fix every Critical or Important finding test-first, and rerun the complete suite.
- [ ] Push the feature branch and verify GitHub Actions, but do not create a PR or activate Supabase, Vercel, Windows scheduling, worker enrollment, or canary leads.
- [ ] Commit `docs: add autonomy operations runbook`.

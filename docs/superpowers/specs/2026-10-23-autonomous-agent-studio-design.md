# SideQuest autonomous agent studio design

Date: October 23, 2026  
Status: proposed for approval

## Intent

Evolve the existing SideQuest Command Center into a highly autonomous internal operating system for Thomas's website business. Agents should discover work, coordinate, hand off deliverables, critique one another, retry recoverable failures, and prepare polished outputs without waiting for Thomas at every internal step.

Every customer-facing or financially consequential action remains behind Thomas's approval. Phase one preserves the current stronger rule: agents may create drafts and previews, but Thomas personally sends emails and messages, publishes posts, approves invoices, and promotes work to a customer-facing destination.

The interface should make the invisible work legible through an interactive isometric SideQuest studio inspired by the supplied TikTok. The studio is not a role-playing simulation. Every occupied desk, movement, conversation, blocked pose, and completed handoff represents a real database-backed job or event.

## Goals

- Increase useful autonomy without adding a paid model, API plan, hosting tier, or other purchase.
- Preserve Supabase `ops` as the source of truth and never touch the live client portal's `public` schema.
- Replace isolated scheduled runs with durable jobs, explicit handoffs, retries, quality review, and approval gates.
- Use deterministic Postgres work whenever an LLM is unnecessary.
- Use Thomas's existing ChatGPT/Codex plan for model-backed work, with the billing and approval guards already added to `runner/`.
- Make agent status, evidence, output quality, blockers, and required human decisions immediately understandable.
- Retain the useful pipeline, lead, content, and activity views instead of hiding operations behind an animated scene.
- Roll out one workflow at a time so the existing Claude tasks remain a reversible fallback until each replacement is proven.
- Make the command center securely usable from Thomas's phone or any modern browser, including while his PC is off.

## Non-goals

- Agents do not independently send email, DMs, texts, proposals, invoices, or social posts.
- Agents do not finalize, send, pay, void, refund, or delete Stripe objects.
- Agents do not make purchases, upgrade plans, create paid resources, or switch to API-key billing.
- The studio does not invent agent relationships, drama, conversations, or productivity for entertainment.
- The project does not rewrite the current data model or dashboard from scratch in one release.
- The project does not expose `ops` directly to anonymous browser clients or put privileged credentials in repository files.
- The system does not store hidden chain-of-thought. It stores concise decisions, evidence, outputs, and failure reasons.

## Constraints

- Existing hard rules in `AGENTS.md` and `playbook/PLAYBOOK.md` remain authoritative.
- Supabase project `taskvfzqgpqxpdifmxru`, schema `ops` only.
- The current dashboard is a Claude Dashboard artifact using `dash.loader`, `dash.calc`, and `dash.onData`; it is not ordinary standalone HTML.
- The Codex runner must continue to require ChatGPT authentication, the built-in OpenAI provider, official ChatGPT endpoints, and `on-request` approval.
- The computer and ChatGPT desktop app must be available for local Codex schedules and browser-based work.
- When the PC is off, the remote control surface and Postgres jobs remain available, while local model jobs remain queued and visibly report `Worker offline` rather than failing or silently disappearing.
- Installed model availability can change. Routing uses capability tiers rather than hard-coding a model that may later retire.
- A lead may have only one state-changing job running at a time.

## Approaches considered

### Automation first

Build orchestration, memory, retry logic, and quality controls before changing the interface. This gives the fastest operational return but leaves the command center visually plain for a substantial period.

### Environment first

Build the isometric studio before the orchestration layer. This creates the desired experience quickly but risks displaying decorative activity that is not backed by real work.

### Layered evolution — selected

Add the job system and visual studio in coordinated vertical slices. Each new visual state is introduced only when the matching database event and workflow are real. Existing tables and scheduled jobs continue to work during the transition.

This approach was selected because it improves the business system and the experience together without a high-risk rewrite.

## Operating model

### Crew

The existing agents remain specialized. Two coordinating roles are added.

| Role | Responsibility | Model use |
|---|---|---|
| Lead Scout | Find candidate businesses from approved sources | None |
| Contact Finder | Verify websites and public contact routes | Standard tier |
| Opportunity Analyst | Re-score evidence, identify the strongest genuine hook, flag weak claims | Fast or standard tier |
| Mockup Builder | Produce clearly labeled local previews and approved `mockup-*` deployments | Standard or deep tier |
| Sales Agent | Prepare reply, outreach, call, DM, proposal, and invoice drafts | Standard tier |
| Content Agent | Prepare the weekly content plan and drafts | Fast or standard tier |
| Quality Reviewer | Check evidence, accuracy, tone, duplication, safety, and completeness | Standard tier; deep tier only on escalation |
| Operations Director | Assign queued work, enforce dependencies, retry recoverable failures, and build the morning brief | Deterministic SQL first; model only for ambiguous prioritization |

The Daily Planner remains deterministic and becomes part of the Operations Director's control loop rather than being replaced by an always-thinking manager.

### Model routing

Model aliases describe capability rather than provider names:

- `mechanical`: SQL, templates, validation, scheduling, and state transitions; no model.
- `fast`: classification, concise summaries, deduplication suggestions, and routine content variants.
- `standard`: lead analysis, outreach drafts, research synthesis, and normal quality review.
- `deep`: complex mockup direction, conflicting evidence, unusual replies, and final escalation review.

At run time, the signed-in Codex catalog resolves the best available included model for the requested tier. If no suitable included model is available, the job becomes `blocked`; the runner never falls back to an API key or paid provider.

Resolution is an explicit mapping in `ops.settings`, not an automatic guess from the catalog. Setup validates each configured model against the signed-in catalog. Thomas can change a tier mapping without changing prompts or code.

### Autonomy boundary

The system may autonomously:

- discover and queue internal work;
- research public business information;
- score, classify, summarize, and enrich leads;
- generate local mockups and draft assets;
- prepare email, reply, DM, call, proposal, invoice, and post drafts;
- critique another agent's work;
- retry idempotent jobs;
- hand work to the next agent;
- update internal `ops` records and activity history;
- assemble Thomas's brief and approval queue.

The system must stop for Thomas before:

- sending any communication;
- publishing any post;
- finalizing or sending an invoice;
- charging, refunding, or otherwise moving money;
- purchasing or upgrading anything;
- deploying anywhere except the already approved `mockup-*` preview boundary;
- changing a verified business fact when evidence conflicts;
- overriding an opt-out or other safety restriction.

An approval records Thomas's decision and keeps an audit trail. In the first release, approval does not automatically execute the external action; it marks the item ready for Thomas to perform.

## Data design

All changes are new timestamped migrations in `supabase/migrations/`. Existing tables stay compatible.

### `ops.workflows`

One durable business process, such as qualifying a lead or preparing next week's content.

- `id uuid primary key`
- `kind text`
- `subject_type text`
- `subject_id text`
- `status text`: active, waiting, completed, blocked, cancelled
- `current_step text`
- `created_at`, `updated_at`, `completed_at`
- unique active-workflow constraint appropriate to kind and subject

### `ops.jobs`

One bounded unit of agent work.

- `id uuid primary key`
- `workflow_id uuid`
- `parent_job_id uuid null`
- `lead_id text null`
- `agent_id text`
- `kind text`
- `status text`: queued, running, review, blocked, completed, failed, cancelled
- `priority int`
- `input jsonb`
- `output jsonb`
- `confidence numeric`
- `attempts int`, `max_attempts int`
- `scheduled_for`, `locked_at`, `lock_owner`, `started_at`, `completed_at`
- `error_code`, `error_summary`
- `created_at`, `updated_at`

Workers claim jobs with a transaction and `for update skip locked`. A partial unique index prevents more than one running state-changing job for the same lead.

### `ops.job_events`

Append-only, concise observability records.

- `id bigserial primary key`
- `job_id uuid`
- `at timestamptz`
- `event text`
- `actor text`
- `summary text`
- `details jsonb`

Events include queued, claimed, researching, draft_created, handed_off, review_failed, retry_scheduled, approval_requested, blocked, and completed.

### `ops.approvals`

The single inbox for decisions requiring Thomas.

- `id uuid primary key`
- `job_id uuid`
- `lead_id text null`
- `action_type text`
- `title text`
- `preview jsonb`
- `risk text`: low, medium, high
- `status text`: pending, approved, rejected, revised, expired
- `requested_at`, `decided_at`
- `decision_note text`
- `external_action_completed_at null`

Approval mutation is idempotent. Repeated button presses cannot create duplicate sends, invoices, or deployments.

### `ops.evidence`

Normalized evidence behind contact details, scores, and pitch claims.

- `id bigserial primary key`
- `lead_id text`
- `kind text`
- `value text`
- `source_url text`
- `source_label text`
- `observed_at timestamptz`
- `confidence numeric`
- `verified_by text`

This allows Quality Reviewer to reject unsupported hooks or stale contact information.

### `ops.memory_items`

Compact durable memory, not transcripts or hidden reasoning.

- `id uuid primary key`
- `scope text`: business, lead, workflow, agent
- `scope_id text`
- `kind text`
- `fact text`
- `source_job_id uuid null`
- `valid_from`, `expires_at`
- `superseded_by uuid null`

### Existing table extensions

`ops.agents` gains `state`, `current_job_id`, `queue_depth`, `health`, `model_tier`, and `last_heartbeat`. `ops.activity` remains the human-readable feed while `ops.job_events` carries structured detail.

## Orchestration

### Deterministic dispatcher

Postgres functions create follow-up jobs from durable state rather than asking a manager model what to do on every cycle. Examples:

- a new lead queues contact verification;
- verified contact data queues opportunity analysis;
- a high-confidence hot lead queues mockup preparation;
- a reviewed mockup queues a sales draft;
- a new reply queues classification and a draft response;
- a completed draft creates an approval item;
- a rejected approval queues revision with Thomas's note.

The dispatcher is idempotent. Running it twice does not create duplicate jobs.

Postgres runs the dispatcher on the existing internal cron schedule. Each role's current cadence becomes the earliest time its recurring jobs are eligible rather than a separate model invocation.

Windows Task Scheduler runs one generic `runner/run-next-job.ps1` heartbeat every 15 minutes from 7:00 AM through 8:00 PM America/Chicago each day. The script asks the remote broker whether eligible work exists before invoking Codex, so an empty queue consumes no model usage. A named Windows mutex permits only one local worker process. Each invocation processes at most one model-backed job; the next heartbeat handles additional work.

Opportunity Analyst and Quality Reviewer are event-driven queue roles rather than additional scheduled model tasks. Their jobs become eligible as soon as an upstream job submits output, so review normally begins within 15 minutes while the PC is online. When the PC is offline, the broker keeps the jobs queued.

### Worker lifecycle

1. Acquire the local worker mutex.
2. Ask the command-center broker for eligible work using the device credential. Exit before model invocation when the queue is empty.
3. Preflight ChatGPT authentication, provider, approval policy, and required job tools.
4. Claim the offered job through the broker. Its server route calls `ops.claim_job(worker_id, offered_job_id)`, which atomically claims the job using `for update skip locked` and returns the minimal payload.
5. Load only the playbook sections and broker-provided context needed for that job.
6. Emit state events while working.
7. Validate output against a per-job JSON schema.
8. Submit risky or creative work to Quality Reviewer.
9. Commit approved internal changes and hand off the next job.
10. Create a human approval item when external action is ready.

The runner owns offer, claim, heartbeat, complete, and fail calls through narrow HTTPS broker endpoints. Model agents never receive a Supabase service-role credential or general SQL tool. The runner injects the claimed job's bounded context and accepts a schema-validated result, then submits that result to the broker. A lease timeout lets the dispatcher recover a job after a crashed or offline worker.

The broker authenticates the local machine with a revocable, device-specific worker token. The raw token lives in Windows Credential Manager. Only its hash and device metadata are stored server-side. It never enters the repository, prompt, output, or logs. Thomas can revoke and re-enroll a worker from the remote command center.

### Retry and escalation

- Retry only classified transient failures: network timeouts, temporary rate limits, and unavailable browser sessions.
- Use bounded exponential backoff with a maximum defined per job type.
- Never retry CAPTCHA, explicit opt-out, permission denial, rejected approval, or a failed billing/authentication guard.
- After the final attempt, mark the job blocked and place a precise item in Thomas's morning brief.
- Quality failures return to the producing agent once with targeted feedback. A second failure escalates to Thomas rather than looping.

### Quality gates

Quality Reviewer checks:

- every factual claim has current evidence;
- no invented reviews, prices, addresses, or business facts;
- no duplicate lead, draft, mockup, or active job;
- copy follows the approved tone and contains no em dashes;
- draft recipients and lead identity agree;
- mockups are clearly labeled and do not contain functional lead forms;
- all external actions remain pending approval;
- confidence is sufficient for the next handoff.

Thresholds are deterministic configuration in `ops.settings`, not improvised by agents.

## Interface design

### Design direction

The visual language is a warm, high-detail isometric creative studio rather than a neon AI control panel. The palette uses charcoal, parchment, muted moss, rust, and one electric chartreuse accent. Typography pairs an editorial serif for briefings with a compact grotesk for controls and a restrained mono face for queue and timing data.

The studio has texture and depth but avoids fake game mechanics. There are no pulsing status dots, generic KPI strip, glass-card grid, or decorative chat bubbles pretending agents are talking.

### Primary layout

Desktop uses four coordinated regions:

1. **Morning brief** across the top: one plain-language sentence describing what changed, what matters, and what needs Thomas.
2. **Studio floor** as the main canvas: isometric rooms for Research, Sales, Creative, Content, Review, and Operations.
3. **Live ledger** on the right: real job events, handoffs, retries, and blockers in chronological order.
4. **Approval dock** along the bottom: pending decisions sorted by risk and urgency.

The existing detailed lead, pipeline, content, and activity views remain available under an `Operations` view. The studio is the orientation layer; tables remain the working layer.

### Real agent states

Each visual state maps to stored data:

- idle: seated with an empty desk and a text label;
- queued: reviewing an inbox tray;
- working: interacting with the workstation appropriate to the job;
- reviewing: standing at the Review room table with the producing agent;
- handing off: moving a physical folder between rooms;
- waiting for Thomas: folder placed in the approval dock;
- blocked: stationary with a clear rectangular `Blocked` label and reason;
- offline: room dimmed with a plain `Offline` label.

Motion is restrained and state-driven. Reduced-motion mode replaces travel animations with immediate position changes and maintains all status labels.

### Agent workbench

Selecting an agent opens an anchored side panel rather than a modal. It shows:

- current job and elapsed time;
- queue depth and next job;
- evidence and source links;
- produced artifact or draft;
- Quality Reviewer feedback;
- model tier and usage summary;
- retries and blocker history;
- exact next handoff.

It does not expose chain-of-thought. It shows a concise decision summary and supporting evidence.

### Approval dock

Every item includes the action, recipient or destination, preview, evidence, quality checks, and risk. Controls are `Approve for me to perform`, `Request changes`, and `Reject`. Approval never sends or publishes in phase one.

High-risk items such as an invoice draft remain visually distinct and require an explicit confirmation note. Bulk approval is unavailable for outbound communication or financial actions.

Before interactive controls exist, Thomas records a decision through one narrow operator command in an authenticated Codex chat. The command calls `ops.resolve_approval(id, decision, note)`; it cannot send, publish, or finalize anything. Thomas separately marks the real-world action complete through `ops.record_external_completion(id)` after he performs it. These procedures provide a temporary audited path without broad database access.

### Mobile

The isometric floor becomes a vertical department map with the same real states and workbench panels. The approval dock becomes the first section when decisions are pending. Dense operational tables use focused row cards instead of forcing a miniature desktop table.

## Dashboard delivery architecture

### Stage one: existing artifact

Upgrade the current Claude Dashboard artifact as a read-only visual studio. Viewing the dashboard does not require a model call. New datasets read `ops.jobs`, `ops.job_events`, and `ops.approvals` through the existing Supabase connector. This stage proves the visual language without exposing a browser credential.

### Stage two: standalone control surface

The finished command center is a responsive standalone app on Thomas's existing Vercel and Supabase setup so it can be reached securely from a phone or any browser while the PC is off. This is a required delivery stage, not an optional enhancement.

The browser uses Supabase Auth only for identity and receives no direct access to `ops`. Server-side Vercel routes verify the Supabase session, require Thomas's allowlisted user ID, and then call narrow security-definer procedures in `ops`. The Supabase service-role credential exists only as a Vercel environment variable; it never enters client JavaScript, logs, generated artifacts, or Git.

The existing client-portal authentication may be reused if Thomas already has a Supabase Auth identity. Reuse does not grant command-center access to any client account: the server compares the authenticated user ID with a dedicated command-center allowlist before every read or mutation. If no suitable identity exists, setup creates one Thomas-only Supabase Auth user through the existing project without adding a paid authentication service.

The application receives only purpose-built response shapes from server routes. It cannot submit arbitrary SQL. Approval endpoints call `ops.resolve_approval`; completion endpoints call `ops.record_external_completion`; read endpoints call bounded views or stored procedures. Rate limiting, same-site secure cookies, CSRF protection for mutations, audit events, and a short idle session timeout are required.

The same server provides a separate worker-broker route family authenticated by the device token rather than Thomas's browser session. Broker routes expose only queue availability, atomic claim, bounded job context, heartbeat, structured result submission, and failure reporting. They never accept raw SQL, arbitrary table names, or caller-supplied procedure names.

The live page distinguishes cloud and local availability. Supabase cron, queued work, approvals, history, and read-only business data remain visible at all times. Work requiring Codex, local files, or the desktop browser stays queued while the PC is unavailable. The studio dims those rooms and shows a rectangular `Worker offline` label with the last heartbeat and expected recovery behavior.

No standalone deployment occurs without a separate deployment review. The implementation must remain within the capacity of Thomas's existing services; if a limit requires an upgrade, deployment stops and reports the constraint instead of purchasing or changing a plan.

## Security and failure handling

- Every worker has an explicit tool allowlist and the narrowest available service permission.
- Supabase is not exposed to model agents. Database work goes through the runner and purpose-built broker procedures.
- Gmail send, social publish, Stripe finalize/pay/refund, destructive SQL, and non-`mockup-*` Vercel operations remain unavailable or approval-gated.
- Codex plugin configuration allowlists only the read and draft tools required by a job. Gmail send, Stripe finalization/payment/refund, and unrestricted Vercel project mutation tools are disabled. Where a provider tool cannot express the required resource boundary, the job uses a validating SideQuest wrapper or remains manual.
- External pages, emails, plugin output, and model output are untrusted data.
- State-changing jobs include idempotency keys.
- Database functions validate legal stage transitions rather than trusting prompts.
- Locks expire safely and orphaned jobs return to queued or blocked state after inspection.
- All approvals and state changes have actor, timestamp, and source job.
- No secret, OAuth token, service-role key, or `.env` file enters the repository.
- Empty, loading, stale, offline, permission-denied, and partial-data states are designed explicitly.

Inbound email polling remains part of Sales Agent. It stores provider message and thread IDs, sender, timestamps, classification, and a short operational summary. It does not copy full message bodies into `ops`. A unique provider-message constraint prevents repeat processing, and lead matching requires an exact normalized email or manual review.

Initial confidence thresholds, evidence freshness windows, and quality criteria run in calibration mode. During calibration, they may block or recommend but cannot automatically promote work to the next external-facing stage. Thomas's reviewed outcomes are measured before thresholds become enforcing settings.

## Measures of success

- Thomas can identify the most important pending decision in under ten seconds.
- At least 80 percent of internal handoffs complete without manual coordination after the first four-week tuning period.
- Duplicate drafts, duplicate mockups, and concurrent lead mutations remain at zero.
- Every outbound draft has evidence and a recorded quality result.
- Blocked jobs name the missing connection or decision instead of silently failing.
- Model-backed work decreases when a deterministic function can perform the same operation.
- No agent sends, publishes, charges, purchases, or touches `public`.

## Rollout

1. Add the job, event, approval, evidence, and memory schema behind feature flags.
2. Add deterministic dispatcher functions and tests without changing existing schedules.
3. Extend the guarded Codex runner to claim one job and return structured job results.
4. Pilot Content Agent because it has no customer contact and a clear review surface.
5. Add Quality Reviewer and approval records.
6. Pilot Contact Finder, then Opportunity Analyst, then Mockup Builder, then Sales Agent.
7. Disable each matching Claude task only after its Codex replacement completes three consecutive reviewed runs with no duplicate, unsupported claim, safety-boundary, or unexplained blocker failure, plus one deliberate blocked-path test.
8. Introduce the real-time studio states as the corresponding workflow slices become live.
9. Add interactive approvals only after the read-only studio and audit trail are stable.

Each phase has a kill switch in `ops.settings`; disabling a workflow stops new jobs without deleting history or affecting the legacy path.

The pilot does not bulk-backfill existing work. It starts with newly eligible records and an explicit canary cohort of at most five existing leads selected by Thomas. A new `automation_owner` field keeps those leads out of legacy Claude selection queries while the Codex workflow owns them. Removing the canary flag returns an unfinished lead to the legacy path without deleting history.

## Builder decisions

The implementation plan may choose exact migration names, UUID generation details, CSS drawing technique, illustration asset format, animation library or no-library approach, and test tooling, provided those choices preserve the existing stack, no-purchase constraint, accessibility, and security boundaries above.

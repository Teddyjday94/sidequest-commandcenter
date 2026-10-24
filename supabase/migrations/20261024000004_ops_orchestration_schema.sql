-- Durable, private orchestration state for the SideQuest agent studio.
-- The ops schema remains outside the Data API and grants no browser role access.

create extension if not exists http with schema extensions;

create table ops.worker_devices (
  id text primary key,
  display_name text not null,
  token_hash text not null unique,
  status text not null default 'active',
  capabilities jsonb not null default '[]'::jsonb,
  enrolled_at timestamptz not null default now(),
  last_seen_at timestamptz,
  revoked_at timestamptz,
  constraint worker_devices_status_check
    check (status in ('active', 'disabled', 'revoked')),
  constraint worker_devices_token_hash_check
    check (length(token_hash) >= 32),
  constraint worker_devices_capabilities_check
    check (jsonb_typeof(capabilities) = 'array'),
  constraint worker_devices_revocation_check
    check (status <> 'revoked' or revoked_at is not null)
);

create table ops.workflows (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  subject_type text not null,
  subject_id text not null,
  status text not null default 'active',
  current_step text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint workflows_status_check
    check (status in ('active', 'waiting', 'completed', 'blocked', 'cancelled')),
  constraint workflows_identity_check
    check (btrim(kind) <> '' and btrim(subject_type) <> '' and btrim(subject_id) <> ''),
  constraint workflows_completion_check
    check ((status = 'completed') = (completed_at is not null))
);

create unique index workflows_active_subject_uq
  on ops.workflows (kind, subject_type, subject_id)
  where status in ('active', 'waiting', 'blocked');

create table ops.jobs (
  id uuid primary key default gen_random_uuid(),
  workflow_id uuid not null references ops.workflows(id) on delete restrict,
  parent_job_id uuid references ops.jobs(id) on delete set null,
  lead_id text references ops.leads(id) on delete restrict,
  agent_id text not null references ops.agents(id) on delete restrict,
  kind text not null,
  status text not null default 'queued',
  priority integer not null default 100,
  input jsonb not null default '{}'::jsonb,
  output jsonb,
  confidence numeric,
  attempts integer not null default 0,
  max_attempts integer not null default 3,
  scheduled_for timestamptz not null default now(),
  locked_at timestamptz,
  lock_owner text references ops.worker_devices(id) on delete restrict,
  started_at timestamptz,
  completed_at timestamptz,
  error_code text,
  error_summary text,
  idempotency_key text not null unique,
  is_state_changing boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint jobs_status_check
    check (status in ('queued', 'running', 'review', 'blocked', 'completed', 'failed', 'cancelled')),
  constraint jobs_priority_check check (priority >= 0),
  constraint jobs_confidence_check check (confidence is null or confidence between 0 and 1),
  constraint jobs_attempts_check
    check (attempts >= 0 and max_attempts > 0 and attempts <= max_attempts),
  constraint jobs_kind_check check (btrim(kind) <> '')
);

create index jobs_queue_idx
  on ops.jobs (priority, scheduled_for, created_at)
  where status = 'queued';

create unique index jobs_running_lead_state_change_uq
  on ops.jobs (lead_id)
  where status = 'running' and is_state_changing and lead_id is not null;

create table ops.job_events (
  id bigserial primary key,
  job_id uuid not null references ops.jobs(id) on delete restrict,
  at timestamptz not null default now(),
  event text not null,
  actor text not null,
  summary text not null,
  details jsonb not null default '{}'::jsonb,
  constraint job_events_event_check check (btrim(event) <> ''),
  constraint job_events_actor_check check (btrim(actor) <> ''),
  constraint job_events_summary_check check (btrim(summary) <> '')
);

create index job_events_job_at_idx on ops.job_events (job_id, at desc);

create table ops.approvals (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references ops.jobs(id) on delete restrict,
  lead_id text references ops.leads(id) on delete restrict,
  action_type text not null,
  title text not null,
  preview jsonb not null default '{}'::jsonb,
  risk text not null,
  status text not null default 'pending',
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid,
  decision_note text,
  external_action_completed_at timestamptz,
  external_action_completed_by uuid,
  constraint approvals_risk_check check (risk in ('low', 'medium', 'high')),
  constraint approvals_status_check
    check (status in ('pending', 'approved', 'rejected', 'revised', 'expired')),
  constraint approvals_action_type_check check (btrim(action_type) <> ''),
  constraint approvals_title_check check (btrim(title) <> ''),
  constraint approvals_decision_check
    check (
      (status = 'pending' and decided_at is null and decided_by is null)
      or (status <> 'pending' and decided_at is not null and decided_by is not null)
    ),
  constraint approvals_external_completion_check
    check (
      (external_action_completed_at is null and external_action_completed_by is null)
      or (external_action_completed_at is not null and external_action_completed_by is not null)
    )
);

create index approvals_pending_idx
  on ops.approvals (risk, requested_at)
  where status = 'pending';

create table ops.evidence (
  id bigserial primary key,
  lead_id text not null references ops.leads(id) on delete restrict,
  kind text not null,
  value text not null,
  source_url text,
  source_label text not null,
  observed_at timestamptz not null,
  confidence numeric not null,
  verified_by text,
  constraint evidence_kind_check check (btrim(kind) <> ''),
  constraint evidence_value_check check (btrim(value) <> ''),
  constraint evidence_source_label_check check (btrim(source_label) <> ''),
  constraint evidence_confidence_check check (confidence between 0 and 1)
);

create index evidence_lead_observed_idx on ops.evidence (lead_id, observed_at desc);

create table ops.memory_items (
  id uuid primary key default gen_random_uuid(),
  scope text not null,
  scope_id text not null,
  kind text not null,
  fact text not null,
  source_job_id uuid references ops.jobs(id) on delete set null,
  valid_from timestamptz not null default now(),
  expires_at timestamptz,
  superseded_by uuid references ops.memory_items(id) on delete set null,
  constraint memory_items_scope_check
    check (scope in ('business', 'lead', 'workflow', 'agent')),
  constraint memory_items_scope_id_check check (btrim(scope_id) <> ''),
  constraint memory_items_kind_check check (btrim(kind) <> ''),
  constraint memory_items_fact_check check (btrim(fact) <> ''),
  constraint memory_items_expiry_check check (expires_at is null or expires_at > valid_from),
  constraint memory_items_supersession_check check (superseded_by is null or superseded_by <> id)
);

create index memory_items_active_scope_idx
  on ops.memory_items (scope, scope_id, valid_from desc)
  where superseded_by is null;

create table ops.inbound_messages (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_message_id text not null,
  provider_thread_id text,
  sender_email text not null,
  received_at timestamptz not null,
  classification text not null,
  summary text not null,
  lead_id text references ops.leads(id) on delete restrict,
  match_status text not null default 'unmatched',
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint inbound_messages_provider_check check (btrim(provider) <> ''),
  constraint inbound_messages_provider_id_check check (btrim(provider_message_id) <> ''),
  constraint inbound_messages_sender_check check (btrim(sender_email) <> ''),
  constraint inbound_messages_classification_check check (btrim(classification) <> ''),
  constraint inbound_messages_summary_check check (btrim(summary) <> ''),
  constraint inbound_messages_match_status_check
    check (match_status in ('unmatched', 'matched', 'manual_review', 'ignored'))
);

create unique index inbound_messages_provider_message_uq
  on ops.inbound_messages (provider, provider_message_id);

create index inbound_messages_thread_idx
  on ops.inbound_messages (provider, provider_thread_id)
  where provider_thread_id is not null;

alter table ops.agents
  add column current_job_id uuid,
  add column state text not null default 'idle',
  add column queue_depth integer not null default 0,
  add column health text not null default 'unknown',
  add column model_tier text not null default 'mechanical',
  add column last_heartbeat timestamptz,
  add constraint agents_current_job_fk
    foreign key (current_job_id) references ops.jobs(id) on delete set null,
  add constraint agents_state_check
    check (state in ('idle', 'queued', 'working', 'reviewing', 'handing_off', 'waiting_for_thomas', 'blocked', 'offline')),
  add constraint agents_queue_depth_check check (queue_depth >= 0),
  add constraint agents_health_check check (health in ('healthy', 'degraded', 'offline', 'unknown')),
  add constraint agents_model_tier_check check (model_tier in ('mechanical', 'fast', 'standard', 'deep'));

alter table ops.leads add column automation_owner text;

drop trigger if exists workflows_touch on ops.workflows;
create trigger workflows_touch
  before update on ops.workflows
  for each row execute function ops.touch_updated();

drop trigger if exists jobs_touch on ops.jobs;
create trigger jobs_touch
  before update on ops.jobs
  for each row execute function ops.touch_updated();

alter table ops.worker_devices enable row level security;
alter table ops.workflows enable row level security;
alter table ops.jobs enable row level security;
alter table ops.job_events enable row level security;
alter table ops.approvals enable row level security;
alter table ops.evidence enable row level security;
alter table ops.memory_items enable row level security;
alter table ops.inbound_messages enable row level security;

revoke all on schema ops from public, anon, authenticated;
revoke all on all tables in schema ops from public, anon, authenticated;
revoke all on all sequences in schema ops from public, anon, authenticated;
alter default privileges in schema ops revoke all on tables from public, anon, authenticated;
alter default privileges in schema ops revoke all on sequences from public, anon, authenticated;

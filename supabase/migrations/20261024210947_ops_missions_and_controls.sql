-- Guarded recurring missions for the private Sidequest operations schema.
-- This migration defines schedules and controls but does not install a cron job.

create table ops.missions (
  id text primary key,
  name text not null,
  agent_id text not null references ops.agents(id) on delete restrict,
  job_kind text not null,
  cadence_minutes integer not null,
  next_run_at timestamptz not null,
  enabled boolean not null default false,
  priority integer not null default 100,
  max_attempts integer not null default 3,
  input jsonb not null default '{}'::jsonb,
  last_dispatched_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint missions_identity_check check (btrim(id) <> '' and btrim(name) <> ''),
  constraint missions_job_kind_check check (job_kind in ('research', 'qualification', 'draft', 'review')),
  constraint missions_cadence_check check (cadence_minutes between 15 and 10080),
  constraint missions_priority_check check (priority >= 0),
  constraint missions_attempts_check check (max_attempts between 1 and 10),
  constraint missions_input_check check (jsonb_typeof(input) = 'object')
);

create index missions_due_idx
  on ops.missions (next_run_at, priority, id)
  where enabled;

create table ops.autonomy_events (
  id bigserial primary key,
  at timestamptz not null default now(),
  actor uuid not null,
  event text not null,
  summary text not null,
  details jsonb not null default '{}'::jsonb,
  constraint autonomy_events_event_check check (btrim(event) <> ''),
  constraint autonomy_events_summary_check check (btrim(summary) <> ''),
  constraint autonomy_events_details_check check (jsonb_typeof(details) = 'object')
);

create index autonomy_events_at_idx on ops.autonomy_events (at desc, id desc);

drop trigger if exists missions_touch on ops.missions;
create trigger missions_touch
  before update on ops.missions
  for each row execute function ops.touch_updated();

alter table ops.missions enable row level security;
alter table ops.autonomy_events enable row level security;

insert into ops.settings (key, value) values
  ('automation_emergency_stop', 'false'),
  ('automation_daily_job_limit', '12'),
  ('automation_max_attempts', '3'),
  ('automation_runtime_minutes', '15'),
  ('automation_window_start', '07:00'),
  ('automation_window_end', '20:00'),
  ('automation_timezone', 'America/Chicago')
on conflict (key) do nothing;

create or replace function ops.dispatch_due_missions(p_now timestamptz) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  mission ops.missions%rowtype;
  workflow_id uuid;
  job_id uuid;
  created_count integer := 0;
  daily_count integer;
  daily_limit integer;
  maximum_attempts integer;
  timezone_name text;
  local_time time;
  window_start time;
  window_end time;
  slot_key text;
begin
  if p_now is null then
    raise exception using errcode = '22023', message = 'dispatch_time_required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('ops.dispatch_due_missions'));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('ops.automation_gate'));

  if coalesce((
    select pg_catalog.lower(s.value) = 'true'
    from ops.settings s where s.key = 'automation_emergency_stop'
  ), false) then
    return jsonb_build_object('created', 0, 'reason', 'emergency_stop');
  end if;

  timezone_name := coalesce((
    select s.value from ops.settings s where s.key = 'automation_timezone'
  ), 'America/Chicago');
  window_start := coalesce((
    select s.value::time from ops.settings s where s.key = 'automation_window_start'
  ), time '07:00');
  window_end := coalesce((
    select s.value::time from ops.settings s where s.key = 'automation_window_end'
  ), time '20:00');
  local_time := (p_now at time zone timezone_name)::time;

  if local_time < window_start or local_time > window_end then
    return jsonb_build_object('created', 0, 'reason', 'outside_operating_window');
  end if;

  daily_limit := greatest(1, least(100, coalesce((
    select s.value::integer from ops.settings s where s.key = 'automation_daily_job_limit'
  ), 12)));
  maximum_attempts := greatest(1, least(10, coalesce((
    select s.value::integer from ops.settings s where s.key = 'automation_max_attempts'
  ), 3)));

  select count(*)::integer into daily_count
  from ops.jobs j
  where j.idempotency_key like 'mission:%'
    and (j.created_at at time zone timezone_name)::date = (p_now at time zone timezone_name)::date;

  if daily_count >= daily_limit then
    return jsonb_build_object('created', 0, 'reason', 'daily_limit');
  end if;

  for mission in
    select m.*
    from ops.missions m
    where m.enabled and m.next_run_at <= p_now
    order by m.priority, m.next_run_at, m.id
    for update skip locked
  loop
    exit when daily_count + created_count >= daily_limit;
    slot_key := 'mission:' || mission.id || ':' || pg_catalog.to_char(mission.next_run_at at time zone 'UTC', 'YYYYMMDDHH24MI');
    workflow_id := null;
    job_id := null;

    insert into ops.workflows
      (kind, subject_type, subject_id, status, current_step, created_at, updated_at)
    values
      ('scheduled_mission', 'mission_slot', slot_key, 'active', mission.job_kind, p_now, p_now)
    on conflict do nothing
    returning id into workflow_id;

    if workflow_id is null then
      select w.id into workflow_id
      from ops.workflows w
      where w.kind = 'scheduled_mission'
        and w.subject_type = 'mission_slot'
        and w.subject_id = slot_key
        and w.status in ('active', 'waiting', 'blocked')
      limit 1;
    end if;

    if workflow_id is not null then
      insert into ops.jobs
        (workflow_id, agent_id, kind, status, priority, input, max_attempts,
         scheduled_for, idempotency_key, is_state_changing, created_at, updated_at)
      values
        (workflow_id, mission.agent_id, mission.job_kind, 'queued', mission.priority,
         mission.input, least(mission.max_attempts, maximum_attempts),
         p_now, slot_key, false, p_now, p_now)
      on conflict (idempotency_key) do nothing
      returning id into job_id;
    end if;

    if job_id is not null then
      insert into ops.job_events (job_id, at, event, actor, summary, details)
      values (
        job_id,
        p_now,
        'mission_dispatched',
        'mission-dispatcher',
        'Recurring internal mission queued',
        jsonb_build_object('mission_id', mission.id, 'slot', slot_key)
      );
      created_count := created_count + 1;
    end if;

    update ops.missions m
    set last_dispatched_at = case when job_id is not null then p_now else m.last_dispatched_at end,
        next_run_at = greatest(
          mission.next_run_at + pg_catalog.make_interval(mins => mission.cadence_minutes),
          p_now + pg_catalog.make_interval(mins => mission.cadence_minutes)
        )
    where m.id = mission.id;
  end loop;

  return jsonb_build_object(
    'created', created_count,
    'reason', case when daily_count + created_count >= daily_limit then 'daily_limit' else 'complete' end
  );
end
$$;

create or replace function ops.set_mission_enabled(
  p_mission_id text,
  p_enabled boolean,
  p_actor uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_mission ops.missions%rowtype;
begin
  if p_mission_id is null or btrim(p_mission_id) = '' or p_enabled is null or p_actor is null then
    raise exception using errcode = '22023', message = 'mission_toggle_fields_required';
  end if;

  select m.* into current_mission
  from ops.missions m
  where m.id = p_mission_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'mission_not_found';
  end if;
  if current_mission.enabled = p_enabled then
    return jsonb_build_object('id', current_mission.id, 'enabled', current_mission.enabled);
  end if;

  update ops.missions m set enabled = p_enabled where m.id = p_mission_id;
  insert into ops.autonomy_events (actor, event, summary, details)
  values (
    p_actor,
    case when p_enabled then 'mission_enabled' else 'mission_disabled' end,
    case when p_enabled then 'Recurring mission enabled' else 'Recurring mission disabled' end,
    jsonb_build_object('mission_id', p_mission_id)
  );

  return jsonb_build_object('id', p_mission_id, 'enabled', p_enabled);
end
$$;

create or replace function ops.set_emergency_stop(
  p_enabled boolean,
  p_actor uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_enabled boolean;
begin
  if p_enabled is null or p_actor is null then
    raise exception using errcode = '22023', message = 'emergency_stop_fields_required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('ops.automation_gate'));

  select pg_catalog.lower(s.value) = 'true' into current_enabled
  from ops.settings s
  where s.key = 'automation_emergency_stop'
  for update;
  current_enabled := coalesce(current_enabled, false);

  if current_enabled = p_enabled then
    return jsonb_build_object('enabled', current_enabled);
  end if;

  insert into ops.settings (key, value)
  values ('automation_emergency_stop', p_enabled::text)
  on conflict (key) do update set value = excluded.value;

  insert into ops.autonomy_events (actor, event, summary, details)
  values (
    p_actor,
    case when p_enabled then 'emergency_stop_engaged' else 'emergency_stop_released' end,
    case when p_enabled then 'Emergency stop engaged' else 'Emergency stop released' end,
    jsonb_build_object('enabled', p_enabled)
  );

  return jsonb_build_object('enabled', p_enabled);
end
$$;

create or replace function ops.get_autonomy_status() returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'emergencyStop', coalesce((
      select pg_catalog.lower(s.value) = 'true'
      from ops.settings s where s.key = 'automation_emergency_stop'
    ), false),
    'dailyJobLimit', coalesce((
      select s.value::integer from ops.settings s where s.key = 'automation_daily_job_limit'
    ), 12),
    'maximumAttempts', coalesce((
      select s.value::integer from ops.settings s where s.key = 'automation_max_attempts'
    ), 3),
    'runtimeMinutes', coalesce((
      select s.value::integer from ops.settings s where s.key = 'automation_runtime_minutes'
    ), 15),
    'windowStart', coalesce((
      select s.value from ops.settings s where s.key = 'automation_window_start'
    ), '07:00'),
    'windowEnd', coalesce((
      select s.value from ops.settings s where s.key = 'automation_window_end'
    ), '20:00'),
    'timezone', coalesce((
      select s.value from ops.settings s where s.key = 'automation_timezone'
    ), 'America/Chicago')
  )
$$;

create or replace function ops.offer_job(p_worker_id text) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  offered ops.jobs%rowtype;
  worker_capabilities jsonb;
begin
  if p_worker_id is null or btrim(p_worker_id) = '' then
    raise exception using errcode = '22023', message = 'worker_id_required';
  end if;
  select w.capabilities into worker_capabilities
  from ops.worker_devices w
  where w.id = p_worker_id and w.status = 'active';
  if not found then
    raise exception using errcode = '42501', message = 'worker_not_active';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('ops.automation_gate'));
  if coalesce((
    select pg_catalog.lower(s.value) = 'true'
    from ops.settings s where s.key = 'automation_emergency_stop'
  ), false) then
    return null;
  end if;

  select j.* into offered
  from ops.jobs j
  where j.status = 'queued'
    and j.scheduled_for <= now()
    and j.attempts < j.max_attempts
    and not j.is_state_changing
    and (
      worker_capabilities ? ('kind:' || j.kind)
      or worker_capabilities ? ('agent:' || j.agent_id)
    )
  order by j.priority, j.scheduled_for, j.created_at, j.id
  limit 1
  for update skip locked;

  if not found then return null; end if;

  return jsonb_build_object(
    'id', offered.id,
    'workflow_id', offered.workflow_id,
    'agent_id', offered.agent_id,
    'kind', offered.kind,
    'priority', offered.priority,
    'attempts', offered.attempts,
    'max_attempts', offered.max_attempts,
    'input', offered.input
  );
end
$$;

create or replace function ops.claim_job(p_worker_id text, p_job_id uuid) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed ops.jobs%rowtype;
  worker_capabilities jsonb;
begin
  if p_worker_id is null or btrim(p_worker_id) = '' or p_job_id is null then
    raise exception using errcode = '22023', message = 'worker_and_job_required';
  end if;
  select w.capabilities into worker_capabilities
  from ops.worker_devices w
  where w.id = p_worker_id and w.status = 'active';
  if not found then
    raise exception using errcode = '42501', message = 'worker_not_active';
  end if;

  select j.* into claimed
  from ops.jobs j
  where j.id = p_job_id
    and j.status = 'running'
    and j.lock_owner = p_worker_id
    and j.locked_at >= now() - interval '15 minutes'
    and not j.is_state_changing
    and (
      worker_capabilities ? ('kind:' || j.kind)
      or worker_capabilities ? ('agent:' || j.agent_id)
    );

  if found then
    return jsonb_build_object(
      'id', claimed.id,
      'workflow_id', claimed.workflow_id,
      'agent_id', claimed.agent_id,
      'kind', claimed.kind,
      'attempts', claimed.attempts,
      'max_attempts', claimed.max_attempts,
      'lease_expires_at', claimed.locked_at + interval '15 minutes',
      'input', claimed.input
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('ops.automation_gate'));
  if coalesce((
    select pg_catalog.lower(s.value) = 'true'
    from ops.settings s where s.key = 'automation_emergency_stop'
  ), false) then
    raise exception using errcode = '55000', message = 'automation_stopped';
  end if;

  select j.* into claimed
  from ops.jobs j
  where j.id = p_job_id
    and j.status = 'queued'
    and j.scheduled_for <= now()
    and j.attempts < j.max_attempts
    and not j.is_state_changing
    and (
      worker_capabilities ? ('kind:' || j.kind)
      or worker_capabilities ? ('agent:' || j.agent_id)
    )
  for update skip locked;

  if not found then return null; end if;

  update ops.jobs j
  set status = 'running',
      attempts = j.attempts + 1,
      locked_at = now(),
      lock_owner = p_worker_id,
      started_at = coalesce(j.started_at, now()),
      error_code = null,
      error_summary = null
  where j.id = p_job_id
  returning j.* into claimed;

  update ops.worker_devices w set last_seen_at = now() where w.id = p_worker_id;
  update ops.agents a
  set current_job_id = claimed.id,
      state = 'working',
      health = 'healthy',
      last_heartbeat = now()
  where a.id = claimed.agent_id;

  insert into ops.job_events (job_id, event, actor, summary, details)
  values (
    claimed.id,
    'claimed',
    p_worker_id,
    'Worker claimed job',
    jsonb_build_object('attempt', claimed.attempts, 'lease_seconds', 900)
  );

  return jsonb_build_object(
    'id', claimed.id,
    'workflow_id', claimed.workflow_id,
    'agent_id', claimed.agent_id,
    'kind', claimed.kind,
    'attempts', claimed.attempts,
    'max_attempts', claimed.max_attempts,
    'lease_expires_at', claimed.locked_at + interval '15 minutes',
    'input', claimed.input
  );
end
$$;

create or replace function ops.guard_expired_job_lease() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'running'
    and old.locked_at is not null
    and old.locked_at < now() - interval '15 minutes'
    and not (
      new.status in ('queued', 'blocked')
      and new.locked_at is null
      and new.lock_owner is null
      and new.error_code = 'lease_expired'
    ) then
    raise exception using errcode = '55000', message = 'job_lease_expired';
  end if;
  return new;
end
$$;

drop trigger if exists jobs_guard_expired_lease on ops.jobs;
create trigger jobs_guard_expired_lease
  before update on ops.jobs
  for each row execute function ops.guard_expired_job_lease();

create or replace function ops.get_studio_snapshot() returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'agents', coalesce((
      select jsonb_agg(to_jsonb(agent_rows) order by agent_rows.ord, agent_rows.id)
      from (
        select a.id, a.ord, a.name, a.role, a.status, a.state, a.health,
               a.model_tier, a.current_job_id, a.queue_depth, a.last_heartbeat,
               a.last_run, a.last_result
        from ops.agents a order by a.ord, a.id limit 50
      ) agent_rows
    ), '[]'::jsonb),
    'jobs', coalesce((
      select jsonb_agg(to_jsonb(job_rows) order by job_rows.created_at desc, job_rows.id)
      from (
        select j.id, j.workflow_id, j.lead_id, j.agent_id, j.kind, j.status,
               j.priority, j.confidence, j.attempts, j.max_attempts, j.scheduled_for,
               j.locked_at, j.lock_owner, j.created_at, j.updated_at, j.completed_at,
               j.error_code, j.error_summary, j.is_state_changing
        from ops.jobs j order by j.created_at desc, j.id limit 100
      ) job_rows
    ), '[]'::jsonb),
    'approvals', coalesce((
      select jsonb_agg(to_jsonb(approval_rows) order by approval_rows.requested_at desc, approval_rows.id)
      from (
        select a.id, a.job_id, a.lead_id, a.action_type, a.title, a.preview,
               a.risk, a.status, a.requested_at, a.decided_at, a.decision_note,
               a.external_action_completed_at
        from ops.approvals a order by a.requested_at desc, a.id limit 50
      ) approval_rows
    ), '[]'::jsonb),
    'activity', coalesce((
      select jsonb_agg(to_jsonb(activity_rows) order by activity_rows.at desc, activity_rows.id desc)
      from (
        select e.id, e.job_id, e.at, e.event, e.actor, e.summary, e.details
        from ops.job_events e order by e.at desc, e.id desc limit 100
      ) activity_rows
    ), '[]'::jsonb),
    'missions', coalesce((
      select jsonb_agg(to_jsonb(mission_rows) order by mission_rows.priority, mission_rows.id)
      from (
        select m.id, m.name, m.agent_id, m.job_kind, m.cadence_minutes,
               m.next_run_at, m.enabled, m.priority, m.max_attempts,
               m.last_dispatched_at
        from ops.missions m order by m.priority, m.id limit 50
      ) mission_rows
    ), '[]'::jsonb),
    'autonomy', ops.get_autonomy_status()
  )
$$;

revoke all on table ops.missions from public, anon, authenticated;
revoke all on table ops.autonomy_events from public, anon, authenticated;
revoke all on sequence ops.autonomy_events_id_seq from public, anon, authenticated;

revoke execute on function ops.dispatch_due_missions(timestamptz) from public, anon, authenticated;
revoke execute on function ops.set_mission_enabled(text, boolean, uuid) from public, anon, authenticated;
revoke execute on function ops.set_emergency_stop(boolean, uuid) from public, anon, authenticated;
revoke execute on function ops.get_autonomy_status() from public, anon, authenticated;
revoke execute on function ops.offer_job(text) from public, anon, authenticated;
revoke execute on function ops.claim_job(text, uuid) from public, anon, authenticated;
revoke execute on function ops.get_studio_snapshot() from public, anon, authenticated;
revoke execute on function ops.guard_expired_job_lease() from public, anon, authenticated;

grant usage on schema ops to service_role;
grant select, insert, update on table ops.missions to service_role;
grant select, insert on table ops.autonomy_events to service_role;
grant usage, select on sequence ops.autonomy_events_id_seq to service_role;
grant execute on function ops.dispatch_due_missions(timestamptz) to service_role;
grant execute on function ops.set_mission_enabled(text, boolean, uuid) to service_role;
grant execute on function ops.set_emergency_stop(boolean, uuid) to service_role;
grant execute on function ops.get_autonomy_status() to service_role;
grant execute on function ops.offer_job(text) to service_role;
grant execute on function ops.claim_job(text, uuid) to service_role;
grant execute on function ops.get_studio_snapshot() to service_role;

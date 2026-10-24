-- Lease-based orchestration procedures for trusted SideQuest workers.
-- The ops schema is private; only service_role may invoke these broker functions.

create or replace function ops.dispatch_work() returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  lead_row record;
  workflow_id uuid;
  job_id uuid;
  dispatched integer := 0;
begin
  for lead_row in
    select l.id, l.business
    from ops.leads l
    where l.automation_owner = 'codex-pilot'
      and l.stage = 'New'
    order by l.created_at, l.id
  loop
    if exists (
      select 1
      from ops.jobs j
      where j.idempotency_key = 'dispatch:lead:' || lead_row.id || ':contact_verification:v1'
    ) then
      continue;
    end if;

    insert into ops.workflows (kind, subject_type, subject_id, status, current_step)
    values ('lead_pipeline', 'lead', lead_row.id, 'active', 'contact_verification')
    on conflict (kind, subject_type, subject_id)
      where status in ('active', 'waiting', 'blocked')
    do update set updated_at = now()
    returning id into workflow_id;

    job_id := null;
    insert into ops.jobs (
      workflow_id,
      lead_id,
      agent_id,
      kind,
      status,
      priority,
      input,
      idempotency_key
    ) values (
      workflow_id,
      lead_row.id,
      'finder',
      'contact_verification',
      'queued',
      25,
      jsonb_build_object('lead_id', lead_row.id, 'business', left(lead_row.business, 200)),
      'dispatch:lead:' || lead_row.id || ':contact_verification:v1'
    )
    on conflict (idempotency_key) do nothing
    returning id into job_id;

    if job_id is not null then
      insert into ops.job_events (job_id, event, actor, summary, details)
      values (
        job_id,
        'queued',
        'dispatcher',
        'Queued contact verification',
        jsonb_build_object('lead_id', lead_row.id)
      );
      dispatched := dispatched + 1;
    end if;
  end loop;

  return jsonb_build_object('dispatched', dispatched);
end
$$;

create or replace function ops.offer_job(p_worker_id text) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  offered ops.jobs%rowtype;
begin
  if p_worker_id is null or btrim(p_worker_id) = '' then
    raise exception using errcode = '22023', message = 'worker_id_required';
  end if;

  if not exists (
    select 1
    from ops.worker_devices w
    where w.id = p_worker_id and w.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'worker_not_active';
  end if;

  select j.*
  into offered
  from ops.jobs j
  where j.status = 'queued'
    and j.scheduled_for <= now()
    and j.attempts < j.max_attempts
  order by j.priority, j.scheduled_for, j.created_at, j.id
  limit 1
  for update skip locked;

  if not found then
    return null;
  end if;

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
begin
  if p_worker_id is null or btrim(p_worker_id) = '' or p_job_id is null then
    raise exception using errcode = '22023', message = 'worker_and_job_required';
  end if;

  if not exists (
    select 1
    from ops.worker_devices w
    where w.id = p_worker_id and w.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'worker_not_active';
  end if;

  select j.*
  into claimed
  from ops.jobs j
  where j.id = p_job_id
    and j.status = 'running'
    and j.lock_owner = p_worker_id;

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

  select j.*
  into claimed
  from ops.jobs j
  where j.id = p_job_id
    and j.status = 'queued'
    and j.scheduled_for <= now()
    and j.attempts < j.max_attempts
  for update skip locked;

  if not found then
    return null;
  end if;

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

  update ops.worker_devices w
  set last_seen_at = now()
  where w.id = p_worker_id;

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

create or replace function ops.heartbeat_job(p_worker_id text, p_job_id uuid) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_job ops.jobs%rowtype;
  renewed_at timestamptz;
begin
  if p_worker_id is null or btrim(p_worker_id) = '' or p_job_id is null then
    raise exception using errcode = '22023', message = 'worker_and_job_required';
  end if;

  if not exists (
    select 1
    from ops.worker_devices w
    where w.id = p_worker_id and w.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'worker_not_active';
  end if;

  select j.* into current_job
  from ops.jobs j
  where j.id = p_job_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'job_not_found';
  end if;
  if current_job.status <> 'running' then
    raise exception using errcode = '55000', message = 'job_not_running';
  end if;
  if current_job.lock_owner is distinct from p_worker_id then
    raise exception using errcode = '42501', message = 'worker_mismatch';
  end if;

  renewed_at := now();
  update ops.jobs j set locked_at = renewed_at where j.id = p_job_id;
  update ops.worker_devices w set last_seen_at = renewed_at where w.id = p_worker_id;
  update ops.agents a
  set last_heartbeat = renewed_at, health = 'healthy'
  where a.id = current_job.agent_id;

  insert into ops.job_events (job_id, event, actor, summary, details)
  values (
    p_job_id,
    'heartbeat',
    p_worker_id,
    'Worker renewed lease',
    jsonb_build_object('lease_seconds', 900)
  );

  return jsonb_build_object(
    'id', p_job_id,
    'status', 'running',
    'lease_expires_at', renewed_at + interval '15 minutes'
  );
end
$$;

create or replace function ops.complete_job(
  p_worker_id text,
  p_job_id uuid,
  p_result jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_job ops.jobs%rowtype;
  result_confidence numeric;
begin
  if p_worker_id is null or btrim(p_worker_id) = '' or p_job_id is null then
    raise exception using errcode = '22023', message = 'worker_and_job_required';
  end if;
  if p_result is null or jsonb_typeof(p_result) <> 'object' or octet_length(p_result::text) > 32768 then
    raise exception using errcode = '22023', message = 'invalid_result';
  end if;

  if not exists (
    select 1
    from ops.worker_devices w
    where w.id = p_worker_id and w.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'worker_not_active';
  end if;

  select j.* into current_job
  from ops.jobs j
  where j.id = p_job_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'job_not_found';
  end if;
  if current_job.status = 'completed'
    and current_job.lock_owner = p_worker_id
    and current_job.output = p_result then
    return jsonb_build_object('id', current_job.id, 'status', current_job.status);
  end if;
  if current_job.status <> 'running' then
    raise exception using errcode = '55000', message = 'job_not_running';
  end if;
  if current_job.lock_owner is distinct from p_worker_id then
    raise exception using errcode = '42501', message = 'worker_mismatch';
  end if;

  if p_result ? 'confidence' then
    begin
      result_confidence := (p_result ->> 'confidence')::numeric;
    exception when invalid_text_representation then
      raise exception using errcode = '22023', message = 'invalid_confidence';
    end;
    if result_confidence not between 0 and 1 then
      raise exception using errcode = '22023', message = 'invalid_confidence';
    end if;
  end if;

  update ops.jobs j
  set status = 'completed',
      output = p_result,
      confidence = result_confidence,
      completed_at = now()
  where j.id = p_job_id
  returning j.* into current_job;

  update ops.agents a
  set current_job_id = null,
      state = 'idle',
      health = 'healthy',
      last_heartbeat = now()
  where a.id = current_job.agent_id and a.current_job_id = p_job_id;

  insert into ops.job_events (job_id, event, actor, summary, details)
  values (
    p_job_id,
    'completed',
    p_worker_id,
    left(coalesce(nullif(p_result ->> 'summary', ''), 'Job completed'), 500),
    jsonb_build_object('confidence', result_confidence)
  );

  return jsonb_build_object('id', current_job.id, 'status', current_job.status);
end
$$;

create or replace function ops.fail_job(
  p_worker_id text,
  p_job_id uuid,
  p_code text,
  p_summary text,
  p_retryable boolean
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_job ops.jobs%rowtype;
  next_status text;
begin
  if p_worker_id is null or btrim(p_worker_id) = '' or p_job_id is null then
    raise exception using errcode = '22023', message = 'worker_and_job_required';
  end if;
  if p_code is null or btrim(p_code) = '' or length(p_code) > 100 then
    raise exception using errcode = '22023', message = 'invalid_error_code';
  end if;
  if p_summary is null or btrim(p_summary) = '' or length(p_summary) > 1000 then
    raise exception using errcode = '22023', message = 'invalid_error_summary';
  end if;
  if p_retryable is null then
    raise exception using errcode = '22023', message = 'retryable_required';
  end if;

  if not exists (
    select 1
    from ops.worker_devices w
    where w.id = p_worker_id and w.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'worker_not_active';
  end if;

  select j.* into current_job
  from ops.jobs j
  where j.id = p_job_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'job_not_found';
  end if;

  if current_job.status in ('queued', 'blocked')
    and exists (
      select 1
      from ops.job_events e
      where e.job_id = p_job_id
        and e.event = 'failed'
        and e.actor = p_worker_id
        and e.details ->> 'code' = p_code
        and e.details ->> 'retryable' = p_retryable::text
        and e.summary = p_summary
    ) then
    return jsonb_build_object('id', current_job.id, 'status', current_job.status);
  end if;

  if current_job.status <> 'running' then
    raise exception using errcode = '55000', message = 'job_not_running';
  end if;
  if current_job.lock_owner is distinct from p_worker_id then
    raise exception using errcode = '42501', message = 'worker_mismatch';
  end if;

  next_status := case
    when p_retryable and current_job.attempts < current_job.max_attempts then 'queued'
    else 'blocked'
  end;

  update ops.jobs j
  set status = next_status,
      locked_at = null,
      lock_owner = null,
      error_code = p_code,
      error_summary = p_summary,
      scheduled_for = case when next_status = 'queued' then now() else j.scheduled_for end
  where j.id = p_job_id
  returning j.* into current_job;

  update ops.agents a
  set current_job_id = null,
      state = case when next_status = 'queued' then 'queued' else 'blocked' end,
      last_heartbeat = now()
  where a.id = current_job.agent_id and a.current_job_id = p_job_id;

  insert into ops.job_events (job_id, event, actor, summary, details)
  values (
    p_job_id,
    'failed',
    p_worker_id,
    p_summary,
    jsonb_build_object('code', p_code, 'retryable', p_retryable, 'next_status', next_status)
  );

  return jsonb_build_object('id', current_job.id, 'status', current_job.status);
end
$$;

create or replace function ops.recover_expired_jobs() returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_job ops.jobs%rowtype;
  next_status text;
  recovered integer := 0;
begin
  for expired_job in
    select j.*
    from ops.jobs j
    where j.status = 'running'
      and j.locked_at < now() - interval '15 minutes'
    order by j.locked_at, j.id
    for update skip locked
  loop
    next_status := case
      when expired_job.attempts < expired_job.max_attempts then 'queued'
      else 'blocked'
    end;

    update ops.jobs j
    set status = next_status,
        locked_at = null,
        lock_owner = null,
        error_code = 'lease_expired',
        error_summary = 'Worker lease expired before completion',
        scheduled_for = case when next_status = 'queued' then now() else j.scheduled_for end
    where j.id = expired_job.id;

    update ops.agents a
    set current_job_id = null,
        state = case when next_status = 'queued' then 'queued' else 'blocked' end,
        health = 'degraded'
    where a.id = expired_job.agent_id and a.current_job_id = expired_job.id;

    insert into ops.job_events (job_id, event, actor, summary, details)
    values (
      expired_job.id,
      'lease_expired',
      'lease-recovery',
      'Recovered expired worker lease',
      jsonb_build_object('previous_worker', expired_job.lock_owner, 'next_status', next_status)
    );
    recovered := recovered + 1;
  end loop;

  return jsonb_build_object('recovered', recovered);
end
$$;

create or replace function ops.resolve_approval(
  p_approval_id uuid,
  p_decision text,
  p_note text,
  p_actor uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_approval ops.approvals%rowtype;
begin
  if p_approval_id is null or p_actor is null then
    raise exception using errcode = '22023', message = 'approval_and_actor_required';
  end if;
  if p_decision not in ('approved', 'rejected', 'revised') then
    raise exception using errcode = '22023', message = 'invalid_approval_decision';
  end if;
  if p_note is not null and length(p_note) > 2000 then
    raise exception using errcode = '22023', message = 'approval_note_too_long';
  end if;

  select a.* into current_approval
  from ops.approvals a
  where a.id = p_approval_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'approval_not_found';
  end if;

  if current_approval.status <> 'pending' then
    if current_approval.status = p_decision
      and current_approval.decided_by = p_actor
      and current_approval.decision_note is not distinct from p_note then
      return jsonb_build_object('id', current_approval.id, 'status', current_approval.status);
    end if;
    raise exception using errcode = '55000', message = 'approval_already_resolved';
  end if;

  update ops.approvals a
  set status = p_decision,
      decided_at = now(),
      decided_by = p_actor,
      decision_note = p_note
  where a.id = p_approval_id
  returning a.* into current_approval;

  insert into ops.job_events (job_id, event, actor, summary, details)
  values (
    current_approval.job_id,
    'approval_resolved',
    p_actor::text,
    'Approval ' || p_decision,
    jsonb_build_object('approval_id', current_approval.id, 'decision', p_decision)
  );

  return jsonb_build_object('id', current_approval.id, 'status', current_approval.status);
end
$$;

create or replace function ops.record_external_completion(
  p_approval_id uuid,
  p_actor uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_approval ops.approvals%rowtype;
begin
  if p_approval_id is null or p_actor is null then
    raise exception using errcode = '22023', message = 'approval_and_actor_required';
  end if;

  select a.* into current_approval
  from ops.approvals a
  where a.id = p_approval_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'approval_not_found';
  end if;
  if current_approval.status <> 'approved' then
    raise exception using errcode = '55000', message = 'approval_not_approved';
  end if;
  if current_approval.external_action_completed_at is not null then
    if current_approval.external_action_completed_by = p_actor then
      return jsonb_build_object('id', current_approval.id, 'status', 'completed');
    end if;
    raise exception using errcode = '55000', message = 'external_action_already_completed';
  end if;

  update ops.approvals a
  set external_action_completed_at = now(),
      external_action_completed_by = p_actor
  where a.id = p_approval_id
  returning a.* into current_approval;

  insert into ops.job_events (job_id, event, actor, summary, details)
  values (
    current_approval.job_id,
    'external_action_completed',
    p_actor::text,
    'Approved external action recorded as complete',
    jsonb_build_object('approval_id', current_approval.id)
  );

  return jsonb_build_object('id', current_approval.id, 'status', 'completed');
end
$$;

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
        from ops.agents a
        order by a.ord, a.id
        limit 50
      ) agent_rows
    ), '[]'::jsonb),
    'jobs', coalesce((
      select jsonb_agg(to_jsonb(job_rows) order by job_rows.created_at desc, job_rows.id)
      from (
        select j.id, j.workflow_id, j.lead_id, j.agent_id, j.kind, j.status,
               j.priority, j.confidence, j.attempts, j.max_attempts, j.scheduled_for,
               j.locked_at, j.lock_owner, j.created_at, j.updated_at, j.completed_at,
               j.error_code, j.error_summary, j.is_state_changing
        from ops.jobs j
        order by j.created_at desc, j.id
        limit 100
      ) job_rows
    ), '[]'::jsonb),
    'approvals', coalesce((
      select jsonb_agg(to_jsonb(approval_rows) order by approval_rows.requested_at desc, approval_rows.id)
      from (
        select a.id, a.job_id, a.lead_id, a.action_type, a.title, a.preview,
               a.risk, a.status, a.requested_at, a.decided_at, a.decision_note,
               a.external_action_completed_at
        from ops.approvals a
        order by a.requested_at desc, a.id
        limit 50
      ) approval_rows
    ), '[]'::jsonb),
    'activity', coalesce((
      select jsonb_agg(to_jsonb(activity_rows) order by activity_rows.at desc, activity_rows.id desc)
      from (
        select e.id, e.job_id, e.at, e.event, e.actor, e.summary, e.details
        from ops.job_events e
        order by e.at desc, e.id desc
        limit 100
      ) activity_rows
    ), '[]'::jsonb)
  )
$$;

revoke execute on function ops.dispatch_work() from public, anon, authenticated;
revoke execute on function ops.offer_job(text) from public, anon, authenticated;
revoke execute on function ops.claim_job(text, uuid) from public, anon, authenticated;
revoke execute on function ops.heartbeat_job(text, uuid) from public, anon, authenticated;
revoke execute on function ops.complete_job(text, uuid, jsonb) from public, anon, authenticated;
revoke execute on function ops.fail_job(text, uuid, text, text, boolean) from public, anon, authenticated;
revoke execute on function ops.recover_expired_jobs() from public, anon, authenticated;
revoke execute on function ops.resolve_approval(uuid, text, text, uuid) from public, anon, authenticated;
revoke execute on function ops.record_external_completion(uuid, uuid) from public, anon, authenticated;
revoke execute on function ops.get_studio_snapshot() from public, anon, authenticated;

grant usage on schema ops to service_role;
grant execute on function ops.dispatch_work() to service_role;
grant execute on function ops.offer_job(text) to service_role;
grant execute on function ops.claim_job(text, uuid) to service_role;
grant execute on function ops.heartbeat_job(text, uuid) to service_role;
grant execute on function ops.complete_job(text, uuid, jsonb) to service_role;
grant execute on function ops.fail_job(text, uuid, text, text, boolean) to service_role;
grant execute on function ops.recover_expired_jobs() to service_role;
grant execute on function ops.resolve_approval(uuid, text, text, uuid) to service_role;
grant execute on function ops.record_external_completion(uuid, uuid) to service_role;
grant execute on function ops.get_studio_snapshot() to service_role;

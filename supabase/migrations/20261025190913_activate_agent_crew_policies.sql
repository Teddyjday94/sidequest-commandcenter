-- Disabled-by-default activation policy for the local Codex agent crew.
-- This migration is private to ops; it creates no cron schedule and performs no external action.

insert into ops.settings (key, value) values
  ('automation_agent_crew_enabled', 'false'),
  ('automation_canary_limit', '5'),
  ('automation_calibration_mode', 'true'),
  ('automation_review_min_confidence', '0.75'),
  ('automation_contact_freshness_days', '30'),
  ('automation_content_freshness_days', '14'),
  ('automation_tier_policy', '{"mechanical":"deterministic-only","fast":"bounded","standard":"review-required","deep":"review-required"}')
on conflict (key) do nothing;

insert into ops.agents
  (id, ord, name, role, status, schedule, hands_to, uses_ai, model_tier)
values
  ('contact-finder', 20, 'Contact Finder', 'Verifies public contact routes and business facts', 'Paused', 'Disabled', 'Quality Reviewer', true, 'fast'),
  ('sales-agent', 30, 'Sales Agent', 'Prepares personalized outreach drafts', 'Paused', 'Disabled', 'Quality Reviewer', true, 'standard'),
  ('mockup-builder', 40, 'Mockup Builder', 'Builds internal website mockup drafts', 'Paused', 'Disabled', 'Quality Reviewer', true, 'deep'),
  ('content-agent', 50, 'Content Agent', 'Prepares social content drafts', 'Paused', 'Disabled', 'Quality Reviewer', true, 'standard'),
  ('opportunity-analyst', 25, 'Opportunity Analyst', 'Qualifies opportunities from verified evidence', 'Paused', 'Handoff only', 'Quality Reviewer', true, 'standard'),
  ('quality-reviewer', 60, 'Quality Reviewer', 'Checks evidence, claims, and safety before owner approval', 'Paused', 'Handoff only', 'Thomas', true, 'standard')
on conflict (id) do update
set model_tier = excluded.model_tier;

insert into ops.missions
  (id, name, agent_id, job_kind, cadence_minutes, next_run_at, enabled,
   priority, max_attempts, input)
values
  (
    'contact-finder-recurring', 'Contact Finder', 'contact-finder', 'research',
    4320, now() + interval '3 days', false, 20, 3,
    '{"task_type":"contact_verification","handoff_policy":"reviewed-v1","calibration":true,"freshness_days":30,"requires_evidence":true}'::jsonb
  ),
  (
    'sales-agent-recurring', 'Sales Agent', 'sales-agent', 'draft',
    1440, now() + interval '1 day', false, 30, 3,
    '{"task_type":"sales_draft","handoff_policy":"reviewed-v1","calibration":true,"requires_evidence":true,"external_send_allowed":false}'::jsonb
  ),
  (
    'mockup-builder-recurring', 'Mockup Builder', 'mockup-builder', 'draft',
    4320, now() + interval '3 days', false, 40, 3,
    '{"task_type":"mockup_draft","handoff_policy":"reviewed-v1","calibration":true,"requires_evidence":true,"external_publish_allowed":false}'::jsonb
  ),
  (
    'content-agent-recurring', 'Content Agent', 'content-agent', 'draft',
    10080, now() + interval '7 days', false, 50, 3,
    '{"task_type":"content_draft","handoff_policy":"reviewed-v1","calibration":true,"freshness_days":14,"requires_evidence":true,"external_send_allowed":false}'::jsonb
  )
on conflict (id) do nothing;

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
  canary_limit integer;
  existing_canaries integer;
  remaining_slots integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('ops.dispatch_work'));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('ops.automation_gate'));

  if not coalesce((
    select pg_catalog.lower(s.value) = 'true'
    from ops.settings s
    where s.key = 'automation_agent_crew_enabled'
  ), false) then
    return jsonb_build_object('dispatched', 0, 'reason', 'agent_crew_disabled');
  end if;

  if coalesce((
    select pg_catalog.lower(s.value) = 'true'
    from ops.settings s
    where s.key = 'automation_emergency_stop'
  ), false) then
    return jsonb_build_object('dispatched', 0, 'reason', 'emergency_stop');
  end if;

  canary_limit := greatest(0, least(5, coalesce((
    select s.value::integer
    from ops.settings s
    where s.key = 'automation_canary_limit'
  ), 5)));

  if canary_limit = 0 then
    return jsonb_build_object('dispatched', 0, 'reason', 'canary_limit');
  end if;

  select count(*)::integer into existing_canaries
  from ops.jobs j
  where j.idempotency_key like 'dispatch:lead:%:contact_verification:v1'
     or j.idempotency_key like 'dispatch:lead:%:contact_verification:v2';
  remaining_slots := greatest(0, canary_limit - existing_canaries);

  if remaining_slots = 0 then
    return jsonb_build_object('dispatched', 0, 'reason', 'canary_limit');
  end if;

  for lead_row in
    select l.id, l.business
    from ops.leads l
    where l.automation_owner = 'codex-pilot'
      and l.stage = 'New'
      and not exists (
        select 1
        from ops.jobs j
        where j.idempotency_key in (
          'dispatch:lead:' || l.id || ':contact_verification:v1',
          'dispatch:lead:' || l.id || ':contact_verification:v2'
        )
      )
    order by l.created_at, l.id
    limit remaining_slots
    for update of l skip locked
  loop
    insert into ops.workflows (kind, subject_type, subject_id, status, current_step)
    values ('lead_pipeline', 'lead', lead_row.id, 'active', 'contact_verification')
    on conflict (kind, subject_type, subject_id)
      where status in ('active', 'waiting', 'blocked')
    do update set updated_at = now()
    returning id into workflow_id;

    job_id := null;
    insert into ops.jobs (
      workflow_id, lead_id, agent_id, kind, status, priority, input,
      idempotency_key, is_state_changing
    ) values (
      workflow_id, lead_row.id, 'contact-finder', 'contact_verification', 'queued', 25,
      jsonb_build_object(
        'lead_id', lead_row.id,
        'business', pg_catalog.left(lead_row.business, 200),
        'task_type', 'contact_verification',
        'handoff_policy', 'reviewed-v1',
        'calibration', true,
        'freshness_days', 30,
        'requires_evidence', true
      ),
      'dispatch:lead:' || lead_row.id || ':contact_verification:v2',
      false
    )
    on conflict (idempotency_key) do nothing
    returning id into job_id;

    if job_id is not null then
      insert into ops.job_events (job_id, event, actor, summary, details)
      values (
        job_id, 'queued', 'dispatcher', 'Queued canary contact verification',
        jsonb_build_object('lead_id', lead_row.id, 'canary', true)
      );
      dispatched := dispatched + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'dispatched', dispatched,
    'reason', case when existing_canaries + dispatched >= canary_limit then 'canary_limit' else 'complete' end
  );
end
$$;

create or replace function ops.assert_exact_jsonb_keys(
  p_value jsonb,
  p_keys text[]
) returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  key_count integer;
begin
  if p_value is null or pg_catalog.jsonb_typeof(p_value) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid_result_envelope';
  end if;
  select count(*)::integer into key_count from pg_catalog.jsonb_object_keys(p_value);
  if key_count <> pg_catalog.array_length(p_keys, 1) or not (p_value ?& p_keys) then
    raise exception using errcode = '22023', message = 'invalid_result_envelope';
  end if;
end
$$;

create or replace function ops.assert_bounded_string_array(
  p_value jsonb,
  p_max_items integer,
  p_max_length integer default 2000
) returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  item jsonb;
  item_text text;
begin
  if p_value is null or pg_catalog.jsonb_typeof(p_value) <> 'array'
    or pg_catalog.jsonb_array_length(p_value) > p_max_items then
    raise exception using errcode = '22023', message = 'invalid_result_envelope';
  end if;
  for item in select value from pg_catalog.jsonb_array_elements(p_value)
  loop
    if pg_catalog.jsonb_typeof(item) <> 'string' then
      raise exception using errcode = '22023', message = 'invalid_result_envelope';
    end if;
    item_text := item #>> '{}';
    if nullif(pg_catalog.btrim(item_text), '') is null or pg_catalog.char_length(item_text) > p_max_length then
      raise exception using errcode = '22023', message = 'invalid_result_envelope';
    end if;
  end loop;
end
$$;

create or replace function ops.assert_valid_job_result(
  p_job ops.jobs,
  p_result jsonb
) returns void
language plpgsql
set search_path = ''
as $$
declare
  evidence_item jsonb;
  output_value jsonb;
  parsed_observed_at timestamptz;
begin
  perform ops.assert_exact_jsonb_keys(
    p_result,
    array['job_id','workflow_id','agent_id','kind','lead_id','status','summary',
          'evidence','confidence','completed_operations','blockers','next_handoff','output']
  );

  if pg_catalog.jsonb_typeof(p_result -> 'job_id') <> 'string'
    or pg_catalog.jsonb_typeof(p_result -> 'workflow_id') <> 'string'
    or pg_catalog.jsonb_typeof(p_result -> 'agent_id') <> 'string'
    or pg_catalog.jsonb_typeof(p_result -> 'kind') <> 'string'
    or p_result ->> 'job_id' is distinct from p_job.id::text
    or p_result ->> 'workflow_id' is distinct from p_job.workflow_id::text
    or p_result ->> 'agent_id' is distinct from p_job.agent_id
    or p_result ->> 'kind' is distinct from p_job.kind
    or p_result ->> 'status' not in ('completed', 'blocked')
    or pg_catalog.jsonb_typeof(p_result -> 'summary') <> 'string'
    or nullif(pg_catalog.btrim(p_result ->> 'summary'), '') is null
    or pg_catalog.char_length(p_result ->> 'summary') > 1000
    or pg_catalog.jsonb_typeof(p_result -> 'next_handoff') <> 'string'
    or nullif(pg_catalog.btrim(p_result ->> 'next_handoff'), '') is null
    or pg_catalog.char_length(p_result ->> 'next_handoff') > 1000
    or pg_catalog.jsonb_typeof(p_result -> 'confidence') <> 'number'
    or (p_result ->> 'confidence')::numeric not between 0 and 1 then
    raise exception using errcode = '22023', message = 'invalid_result_envelope';
  end if;

  if (p_job.lead_id is null and pg_catalog.jsonb_typeof(p_result -> 'lead_id') <> 'null')
    or (p_job.lead_id is not null and (
      pg_catalog.jsonb_typeof(p_result -> 'lead_id') <> 'string'
      or p_result ->> 'lead_id' is distinct from p_job.lead_id
    )) then
    raise exception using errcode = '22023', message = 'invalid_result_envelope';
  end if;

  perform ops.assert_bounded_string_array(p_result -> 'completed_operations', 50);
  perform ops.assert_bounded_string_array(p_result -> 'blockers', 50);

  if pg_catalog.jsonb_typeof(p_result -> 'evidence') <> 'array'
    or pg_catalog.jsonb_array_length(p_result -> 'evidence') > 50
    or (p_result ->> 'status' = 'completed' and pg_catalog.jsonb_array_length(p_result -> 'evidence') = 0) then
    raise exception using errcode = '22023', message = 'invalid_result_envelope';
  end if;
  for evidence_item in select value from pg_catalog.jsonb_array_elements(p_result -> 'evidence')
  loop
    perform ops.assert_exact_jsonb_keys(
      evidence_item,
      array['fact','source_url','source_label','observed_at','confidence']
    );
    if pg_catalog.jsonb_typeof(evidence_item -> 'fact') <> 'string'
      or nullif(pg_catalog.btrim(evidence_item ->> 'fact'), '') is null
      or pg_catalog.char_length(evidence_item ->> 'fact') > 1000
      or pg_catalog.jsonb_typeof(evidence_item -> 'source_url') <> 'string'
      or nullif(pg_catalog.btrim(evidence_item ->> 'source_url'), '') is null
      or pg_catalog.char_length(evidence_item ->> 'source_url') > 2048
      or evidence_item ->> 'source_url' !~ '^https?://[^[:space:]]+$'
      or pg_catalog.jsonb_typeof(evidence_item -> 'source_label') <> 'string'
      or nullif(pg_catalog.btrim(evidence_item ->> 'source_label'), '') is null
      or pg_catalog.char_length(evidence_item ->> 'source_label') > 200
      or pg_catalog.jsonb_typeof(evidence_item -> 'observed_at') <> 'string'
      or nullif(pg_catalog.btrim(evidence_item ->> 'observed_at'), '') is null
      or pg_catalog.char_length(evidence_item ->> 'observed_at') > 64
      or evidence_item ->> 'observed_at' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
      or pg_catalog.jsonb_typeof(evidence_item -> 'confidence') <> 'number'
      or (evidence_item ->> 'confidence')::numeric not between 0 and 1 then
      raise exception using errcode = '22023', message = 'invalid_result_envelope';
    end if;
    begin
      parsed_observed_at := (evidence_item ->> 'observed_at')::timestamptz;
    exception when others then
      raise exception using errcode = '22023', message = 'invalid_result_envelope';
    end;
  end loop;

  output_value := p_result -> 'output';
  if p_job.kind in ('research', 'contact_verification') then
    perform ops.assert_exact_jsonb_keys(output_value, array['facts','contact_routes']);
    perform ops.assert_bounded_string_array(output_value -> 'facts', 100);
    perform ops.assert_bounded_string_array(output_value -> 'contact_routes', 25);
  elsif p_job.kind = 'qualification' then
    perform ops.assert_exact_jsonb_keys(output_value, array['score_factors','verified_hook','conflicts']);
    perform ops.assert_bounded_string_array(output_value -> 'score_factors', 25);
    perform ops.assert_bounded_string_array(output_value -> 'conflicts', 25);
    if pg_catalog.jsonb_typeof(output_value -> 'verified_hook') <> 'string'
      or nullif(pg_catalog.btrim(output_value ->> 'verified_hook'), '') is null
      or pg_catalog.char_length(output_value ->> 'verified_hook') > 1000 then
      raise exception using errcode = '22023', message = 'invalid_result_envelope';
    end if;
  elsif p_job.kind = 'draft' then
    perform ops.assert_exact_jsonb_keys(output_value, array['artifact_summary','artifact_refs']);
    perform ops.assert_bounded_string_array(output_value -> 'artifact_refs', 50);
    if pg_catalog.jsonb_typeof(output_value -> 'artifact_summary') <> 'string'
      or nullif(pg_catalog.btrim(output_value ->> 'artifact_summary'), '') is null
      or pg_catalog.char_length(output_value ->> 'artifact_summary') > 2000 then
      raise exception using errcode = '22023', message = 'invalid_result_envelope';
    end if;
  elsif p_job.kind = 'review' then
    perform ops.assert_exact_jsonb_keys(
      output_value,
      array['decision','failing_checks','evidence_gaps','revision_instructions']
    );
    if pg_catalog.jsonb_typeof(output_value -> 'decision') <> 'string'
      or output_value ->> 'decision' not in ('pass', 'revise', 'escalate') then
      raise exception using errcode = '22023', message = 'invalid_result_envelope';
    end if;
    perform ops.assert_bounded_string_array(output_value -> 'failing_checks', 50);
    perform ops.assert_bounded_string_array(output_value -> 'evidence_gaps', 50);
    perform ops.assert_bounded_string_array(output_value -> 'revision_instructions', 50);
  else
    raise exception using errcode = '22023', message = 'invalid_result_envelope';
  end if;
end
$$;

revoke all on function ops.assert_exact_jsonb_keys(jsonb, text[]) from public, anon, authenticated, service_role;
revoke all on function ops.assert_bounded_string_array(jsonb, integer, integer) from public, anon, authenticated, service_role;
revoke all on function ops.assert_valid_job_result(ops.jobs, jsonb) from public, anon, authenticated, service_role;

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
  source_job ops.jobs%rowtype;
  result_confidence numeric;
  minimum_confidence numeric;
  has_evidence boolean := false;
  review_job_id uuid;
  revision_job_id uuid;
  approval_id uuid;
  review_decision text;
  revision_count integer;
begin
  if p_worker_id is null or pg_catalog.btrim(p_worker_id) = '' or p_job_id is null then
    raise exception using errcode = '22023', message = 'worker_and_job_required';
  end if;
  if p_result is null or pg_catalog.jsonb_typeof(p_result) <> 'object'
    or pg_catalog.octet_length(p_result::text) > 32768 then
    raise exception using errcode = '22023', message = 'invalid_result';
  end if;

  if not exists (
    select 1 from ops.worker_devices w
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
  if current_job.status = 'blocked'
    and current_job.output = p_result
    and exists (
      select 1 from ops.job_events e
      where e.job_id = current_job.id
        and e.event = 'quality_escalated'
        and e.actor in (p_worker_id, 'quality-policy')
    ) then
    return jsonb_build_object('id', current_job.id, 'status', current_job.status);
  end if;
  if current_job.status <> 'running' then
    raise exception using errcode = '55000', message = 'job_not_running';
  end if;
  if current_job.lock_owner is distinct from p_worker_id then
    raise exception using errcode = '42501', message = 'worker_mismatch';
  end if;

  perform ops.assert_valid_job_result(current_job, p_result);

  result_confidence := (p_result ->> 'confidence')::numeric;

  if current_job.input ->> 'handoff_policy' is distinct from 'reviewed-v1' then
    update ops.jobs j
    set status = 'completed', output = p_result, confidence = result_confidence,
        completed_at = now()
    where j.id = p_job_id
    returning j.* into current_job;

    update ops.agents a
    set current_job_id = null, state = 'idle', health = 'healthy', last_heartbeat = now()
    where a.id = current_job.agent_id and a.current_job_id = p_job_id;

    insert into ops.job_events (job_id, event, actor, summary, details)
    values (
      p_job_id, 'completed', p_worker_id,
      pg_catalog.left(coalesce(nullif(p_result ->> 'summary', ''), 'Job completed'), 500),
      jsonb_build_object('confidence', result_confidence)
    );
    return jsonb_build_object('id', current_job.id, 'status', current_job.status);
  end if;

  minimum_confidence := greatest(0, least(1, coalesce((
    select s.value::numeric
    from ops.settings s
    where s.key = 'automation_review_min_confidence'
  ), 0.75)));

  if current_job.kind <> 'review' then
    has_evidence := case
      when p_result ? 'evidence'
        and pg_catalog.jsonb_typeof(p_result -> 'evidence') = 'array'
      then pg_catalog.jsonb_array_length(p_result -> 'evidence') > 0
      else false
    end;

    if p_result ->> 'status' = 'blocked'
      or not has_evidence
      or result_confidence is null
      or result_confidence < minimum_confidence then
      update ops.jobs j
      set status = 'blocked', output = p_result, confidence = result_confidence,
          locked_at = null, lock_owner = null,
          error_code = case
            when p_result ->> 'status' = 'blocked' then 'worker_blocked'
            when not has_evidence then 'missing_evidence'
            else 'low_confidence'
          end,
          error_summary = case
            when p_result ->> 'status' = 'blocked' then 'Worker reported blockers that require manual review'
            when not has_evidence then 'Evidence is required before quality review'
            else 'Result confidence is below the quality threshold'
          end
      where j.id = p_job_id
      returning j.* into current_job;

      update ops.workflows w
      set status = 'blocked', current_step = 'manual_review'
      where w.id = current_job.workflow_id;
      update ops.agents a
      set current_job_id = null, state = 'blocked', health = 'degraded', last_heartbeat = now()
      where a.id = current_job.agent_id and a.current_job_id = p_job_id;

      insert into ops.job_events (job_id, event, actor, summary, details)
      values (
        p_job_id, 'quality_escalated', p_worker_id,
        case
          when p_result ->> 'status' = 'blocked' then 'Worker blockers require manual review'
          when not has_evidence then 'Missing evidence requires manual review'
          else 'Low confidence requires manual review'
        end,
        jsonb_build_object(
          'reason', current_job.error_code,
          'confidence', result_confidence,
          'minimum_confidence', minimum_confidence
        )
      );
      return jsonb_build_object('id', current_job.id, 'status', 'blocked', 'handoff', 'manual_review');
    end if;

    update ops.jobs j
    set status = 'completed', output = p_result, confidence = result_confidence,
        completed_at = now()
    where j.id = p_job_id
    returning j.* into current_job;

    insert into ops.jobs (
      workflow_id, parent_job_id, lead_id, agent_id, kind, status, priority,
      input, max_attempts, idempotency_key, is_state_changing
    ) values (
      current_job.workflow_id, current_job.id, current_job.lead_id,
      'quality-reviewer', 'review', 'queued', current_job.priority,
      jsonb_build_object(
        'task_type', 'quality_review',
        'handoff_policy', 'reviewed-v1',
        'source_job_id', current_job.id,
        'source_agent_id', current_job.agent_id,
        'source_kind', current_job.kind,
        'lead_id', current_job.lead_id,
        'producer_input', current_job.input,
        'producer_result', p_result,
        'producer_output', p_result -> 'output',
        'producer_evidence', p_result -> 'evidence',
        'revision_count', coalesce((current_job.input ->> 'revision_count')::integer, 0),
        'external_send_allowed', false
      ),
      current_job.max_attempts,
      'quality-review:' || current_job.id::text || ':v1',
      false
    )
    on conflict (idempotency_key) do nothing
    returning id into review_job_id;

    if review_job_id is null then
      select j.id into review_job_id
      from ops.jobs j
      where j.idempotency_key = 'quality-review:' || current_job.id::text || ':v1';
    else
      insert into ops.job_events (job_id, event, actor, summary, details)
      values (
        review_job_id, 'review_queued', 'quality-policy',
        'Queued evidence and safety review',
        jsonb_build_object('source_job_id', current_job.id)
      );
    end if;

    update ops.workflows w
    set status = 'waiting', current_step = 'quality_review'
    where w.id = current_job.workflow_id;
    update ops.agents a
    set current_job_id = null, state = 'idle', health = 'healthy', last_heartbeat = now()
    where a.id = current_job.agent_id and a.current_job_id = p_job_id;
    insert into ops.job_events (job_id, event, actor, summary, details)
    values (
      p_job_id, 'completed', p_worker_id,
      pg_catalog.left(coalesce(nullif(p_result ->> 'summary', ''), 'Producer job completed'), 500),
      jsonb_build_object('confidence', result_confidence, 'review_job_id', review_job_id)
    );

    return jsonb_build_object(
      'id', current_job.id, 'status', 'completed',
      'handoff', 'quality_review', 'review_job_id', review_job_id
    );
  end if;

  if current_job.agent_id <> 'quality-reviewer' or current_job.parent_job_id is null then
    raise exception using errcode = '22023', message = 'invalid_review_job';
  end if;

  select j.* into source_job
  from ops.jobs j
  where j.id = current_job.parent_job_id;
  if not found then
    raise exception using errcode = '22023', message = 'review_source_not_found';
  end if;

  review_decision := pg_catalog.lower(coalesce(p_result -> 'output' ->> 'decision', ''));
  if review_decision not in ('pass', 'revise', 'escalate') then
    raise exception using errcode = '22023', message = 'invalid_review_decision';
  end if;

  if review_decision = 'pass' then
    update ops.jobs j
    set status = 'completed', output = p_result, confidence = result_confidence,
        completed_at = now()
    where j.id = p_job_id
    returning j.* into current_job;

    insert into ops.approvals (job_id, lead_id, action_type, title, preview, risk, status)
    values (
      current_job.id, current_job.lead_id, 'owner_review',
      pg_catalog.left('Review ' || coalesce(source_job.input ->> 'task_type', source_job.kind), 500),
      jsonb_build_object(
        'source_job_id', source_job.id,
        'source_agent_id', source_job.agent_id,
        'task_type', coalesce(source_job.input ->> 'task_type', source_job.kind),
        'artifact', coalesce(source_job.output -> 'output', source_job.output),
        'review', p_result,
        'external_send_allowed', false,
        'owner_must_act', true
      ),
      'medium', 'pending'
    )
    returning id into approval_id;

    update ops.workflows w
    set status = 'waiting', current_step = 'owner_approval'
    where w.id = current_job.workflow_id;
    update ops.agents a
    set current_job_id = null, state = 'waiting_for_thomas', health = 'healthy', last_heartbeat = now()
    where a.id = current_job.agent_id and a.current_job_id = p_job_id;
    insert into ops.job_events (job_id, event, actor, summary, details)
    values (
      current_job.id, 'approval_requested', 'quality-policy',
      'Quality review passed; waiting for Thomas',
      jsonb_build_object('approval_id', approval_id, 'external_send_allowed', false)
    );

    return jsonb_build_object(
      'id', current_job.id, 'status', 'completed',
      'handoff', 'owner_approval', 'approval_id', approval_id
    );
  end if;

  revision_count := coalesce((source_job.input ->> 'revision_count')::integer, 0);
  if review_decision = 'revise' and revision_count < 1 then
    update ops.jobs j
    set status = 'completed', output = p_result, confidence = result_confidence,
        completed_at = now()
    where j.id = p_job_id
    returning j.* into current_job;

    insert into ops.jobs (
      workflow_id, parent_job_id, lead_id, agent_id, kind, status, priority,
      input, max_attempts, idempotency_key, is_state_changing
    ) values (
      source_job.workflow_id, current_job.id, source_job.lead_id,
      source_job.agent_id, source_job.kind, 'queued', source_job.priority,
      source_job.input || jsonb_build_object(
        'lead_id', source_job.lead_id,
        'revision_count', 1,
        'revision_instructions', coalesce(
          p_result -> 'output' -> 'revision_instructions',
          pg_catalog.to_jsonb(p_result ->> 'summary')
        ),
        'previous_result', source_job.output
      ),
      source_job.max_attempts,
      'revision:' || source_job.id::text || ':1',
      false
    )
    on conflict (idempotency_key) do nothing
    returning id into revision_job_id;

    if revision_job_id is null then
      select j.id into revision_job_id
      from ops.jobs j
      where j.idempotency_key = 'revision:' || source_job.id::text || ':1';
    else
      insert into ops.job_events (job_id, event, actor, summary, details)
      values (
        revision_job_id, 'revision_queued', 'quality-policy',
        'Queued the one permitted revision',
        jsonb_build_object('review_job_id', current_job.id, 'revision_count', 1)
      );
    end if;

    update ops.workflows w
    set status = 'active', current_step = source_job.kind
    where w.id = current_job.workflow_id;
    update ops.agents a
    set current_job_id = null, state = 'idle', health = 'healthy', last_heartbeat = now()
    where a.id = current_job.agent_id and a.current_job_id = p_job_id;

    return jsonb_build_object(
      'id', current_job.id, 'status', 'completed',
      'handoff', 'revision', 'revision_job_id', revision_job_id
    );
  end if;

  update ops.jobs j
  set status = 'blocked', output = p_result, confidence = result_confidence,
      locked_at = null, lock_owner = null,
      error_code = case when review_decision = 'revise' then 'revision_limit_reached' else 'review_escalated' end,
      error_summary = case when review_decision = 'revise'
        then 'Quality review failed after the one permitted revision'
        else 'Quality reviewer escalated the result for manual review' end
  where j.id = p_job_id
  returning j.* into current_job;

  update ops.workflows w
  set status = 'blocked', current_step = 'manual_review'
  where w.id = current_job.workflow_id;
  update ops.agents a
  set current_job_id = null, state = 'blocked', health = 'degraded', last_heartbeat = now()
  where a.id = current_job.agent_id and a.current_job_id = p_job_id;
  insert into ops.job_events (job_id, event, actor, summary, details)
  values (
    current_job.id, 'quality_escalated', 'quality-policy', current_job.error_summary,
    jsonb_build_object('reason', current_job.error_code, 'revision_count', revision_count)
  );

  return jsonb_build_object('id', current_job.id, 'status', 'blocked', 'handoff', 'manual_review');
end
$$;

revoke execute on function ops.dispatch_work() from public, anon, authenticated;
revoke execute on function ops.complete_job(text, uuid, jsonb) from public, anon, authenticated;

grant usage on schema ops to service_role;
grant execute on function ops.dispatch_work() to service_role;
grant execute on function ops.complete_job(text, uuid, jsonb) to service_role;

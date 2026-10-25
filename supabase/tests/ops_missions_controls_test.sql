begin;

select * from no_plan();

select has_table('ops', 'missions', 'missions table exists');
select has_column('ops', 'missions', 'id', 'missions.id exists');
select has_column('ops', 'missions', 'name', 'missions.name exists');
select has_column('ops', 'missions', 'agent_id', 'missions.agent_id exists');
select has_column('ops', 'missions', 'job_kind', 'missions.job_kind exists');
select has_column('ops', 'missions', 'cadence_minutes', 'missions.cadence_minutes exists');
select has_column('ops', 'missions', 'next_run_at', 'missions.next_run_at exists');
select has_column('ops', 'missions', 'enabled', 'missions.enabled exists');
select has_column('ops', 'missions', 'priority', 'missions.priority exists');
select has_column('ops', 'missions', 'max_attempts', 'missions.max_attempts exists');
select has_column('ops', 'missions', 'input', 'missions.input exists');
select has_column('ops', 'missions', 'last_dispatched_at', 'missions.last_dispatched_at exists');

select has_table('ops', 'autonomy_events', 'autonomy events table exists');
select has_column('ops', 'autonomy_events', 'actor', 'autonomy_events.actor exists');
select has_column('ops', 'autonomy_events', 'event', 'autonomy_events.event exists');
select has_column('ops', 'autonomy_events', 'summary', 'autonomy_events.summary exists');
select has_column('ops', 'autonomy_events', 'details', 'autonomy_events.details exists');

select has_function('ops', 'dispatch_due_missions', array['timestamp with time zone'], 'mission dispatcher exists');
select has_function('ops', 'set_mission_enabled', array['text', 'boolean', 'uuid'], 'mission toggle exists');
select has_function('ops', 'set_emergency_stop', array['boolean', 'uuid'], 'emergency stop setter exists');
select has_function('ops', 'get_autonomy_status', array[]::text[], 'autonomy status reader exists');

select lives_ok(
  $$insert into ops.agents (id, name, role, status)
    values
      ('mission-research', 'Mission Research', 'Researches approved public information', 'Live'),
      ('mission-review', 'Mission Review', 'Reviews internal drafts', 'Live')$$,
  'mission agents can be created'
);
select lives_ok(
  $$insert into ops.worker_devices (id, display_name, token_hash, status, capabilities)
    values ('mission-worker', 'Mission Worker', repeat('9', 64), 'active', '["kind:research"]'::jsonb)$$,
  'an active mission worker can be created'
);

select lives_ok(
  $$insert into ops.missions
      (id, name, agent_id, job_kind, cadence_minutes, next_run_at, enabled, priority, max_attempts, input)
    values
      ('weekday-research', 'Weekday research', 'mission-research', 'research', 1440,
       '2026-10-26 14:00:00+00', true, 20, 9, '{"scope":"public-business-info"}'::jsonb),
      ('disabled-review', 'Disabled review', 'mission-review', 'review', 1440,
       '2026-10-26 14:00:00+00', false, 30, 2, '{}'::jsonb)$$,
  'mission fixtures can be created'
);

select is(
  ops.dispatch_due_missions('2026-10-26 10:00:00+00')->>'reason',
  'outside_operating_window',
  'missions do not dispatch before 7 AM America/Chicago'
);
select is(
  (select count(*)::bigint from ops.jobs where idempotency_key like 'mission:%'),
  0::bigint,
  'outside-window dispatch creates no jobs'
);

select is(
  (ops.dispatch_due_missions('2026-10-26 15:00:00+00')->>'created')::integer,
  1,
  'one enabled due mission creates one job inside the operating window'
);
select is(
  (select count(*)::bigint from ops.jobs where idempotency_key like 'mission:weekday-research:%'),
  1::bigint,
  'the mission creates one idempotent due-slot job'
);
select is(
  (select max_attempts from ops.jobs where idempotency_key like 'mission:weekday-research:%'),
  3,
  'the server caps mission retries even when the mission requests more'
);
select is(
  (ops.dispatch_due_missions('2026-10-26 15:00:00+00')->>'created')::integer,
  0,
  'repeating the same dispatcher tick creates no duplicate job'
);
select is(
  (select count(*)::bigint from ops.jobs where idempotency_key like 'mission:disabled-review:%'),
  0::bigint,
  'a disabled mission never creates work'
);

select lives_ok(
  $$select ops.set_mission_enabled(
      'disabled-review',
      true,
      '41000000-0000-4000-8000-000000000001'
    )$$,
  'the owner can enable a mission through the fixed procedure'
);
select lives_ok(
  $$select ops.set_mission_enabled(
      'disabled-review',
      true,
      '41000000-0000-4000-8000-000000000001'
    )$$,
  'repeating the same mission toggle is idempotent'
);
select is(
  (
    select count(*)::bigint
    from ops.autonomy_events
    where event = 'mission_enabled' and details->>'mission_id' = 'disabled-review'
  ),
  1::bigint,
  'an idempotent mission toggle records one audit event'
);

select lives_ok(
  $$select ops.set_emergency_stop(
      true,
      '41000000-0000-4000-8000-000000000001'
    )$$,
  'the owner can engage the emergency stop'
);
select is(
  ops.dispatch_due_missions('2026-10-27 15:00:00+00')->>'reason',
  'emergency_stop',
  'emergency stop prevents new mission dispatch'
);
select is(
  ops.offer_job('mission-worker'),
  null::jsonb,
  'emergency stop offers no queued work'
);
select throws_ok(
  $$select ops.claim_job(
      'mission-worker',
      (select id from ops.jobs where idempotency_key like 'mission:weekday-research:%' limit 1)
    )$$,
  '55000',
  'automation_stopped',
  'emergency stop prevents a new job claim'
);
select lives_ok(
  $$select ops.set_emergency_stop(
      false,
      '41000000-0000-4000-8000-000000000001'
    )$$,
  'the owner can release the emergency stop'
);
select is(
  (
    select count(*)::bigint
    from ops.autonomy_events
    where event in ('emergency_stop_engaged', 'emergency_stop_released')
  ),
  2::bigint,
  'stop changes are recorded in an audit trail'
);

select lives_ok(
  $$insert into ops.settings (key, value) values ('automation_daily_job_limit', '1')
    on conflict (key) do update set value = excluded.value$$,
  'the daily mission limit can be configured internally'
);
select is(
  (ops.dispatch_due_missions('2026-10-27 15:00:00+00')->>'created')::integer,
  1,
  'the next local day permits one mission job'
);
select is(
  (ops.dispatch_due_missions('2026-10-27 16:00:00+00')->>'reason'),
  'daily_limit',
  'the dispatcher stops after the server daily job limit'
);

select ok(
  (ops.get_autonomy_status()->>'emergencyStop')::boolean = false
    and (ops.get_autonomy_status()->>'dailyJobLimit')::integer = 1
    and (ops.get_autonomy_status()->>'maximumAttempts')::integer = 3
    and (ops.get_autonomy_status()->>'runtimeMinutes')::integer = 15
    and ops.get_autonomy_status()->>'timezone' = 'America/Chicago',
  'autonomy status reports the effective server-side controls'
);

select is(
  (
    select count(*)::bigint
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'ops'
      and p.proname in (
        'dispatch_due_missions', 'set_mission_enabled',
        'set_emergency_stop', 'get_autonomy_status'
      )
      and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
  ),
  4::bigint,
  'every mission control procedure pins its search path'
);
select is(
  (
    select count(*)::bigint
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'ops'
      and p.proname in ('dispatch_due_missions', 'set_emergency_stop', 'offer_job', 'claim_job')
      and pg_get_functiondef(p.oid) like '%ops.automation_gate%'
  ),
  4::bigint,
  'dispatch, stop, offer, and claim share one transaction-level automation gate'
);
select is(
  has_function_privilege('anon', 'ops.dispatch_due_missions(timestamp with time zone)', 'execute'),
  false,
  'anon cannot dispatch missions'
);
select is(
  has_function_privilege('authenticated', 'ops.set_emergency_stop(boolean, uuid)', 'execute'),
  false,
  'authenticated users cannot change the emergency stop directly'
);
select is(
  has_function_privilege('service_role', 'ops.get_autonomy_status()', 'execute'),
  true,
  'the server service role can read autonomy status'
);
select is(
  (
    select count(*)::bigint
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'ops'
      and c.relname in ('missions', 'autonomy_events')
      and c.relrowsecurity
  ),
  2::bigint,
  'row-level security is enabled on mission control tables'
);

select * from finish();
rollback;


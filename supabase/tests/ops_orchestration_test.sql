begin;

select * from no_plan();

select has_table('ops', 'workflows', 'workflows table exists');
select has_column('ops', 'workflows', 'id', 'workflows.id exists');
select has_column('ops', 'workflows', 'kind', 'workflows.kind exists');
select has_column('ops', 'workflows', 'subject_type', 'workflows.subject_type exists');
select has_column('ops', 'workflows', 'subject_id', 'workflows.subject_id exists');
select has_column('ops', 'workflows', 'status', 'workflows.status exists');
select has_column('ops', 'workflows', 'current_step', 'workflows.current_step exists');
select has_column('ops', 'workflows', 'created_at', 'workflows.created_at exists');
select has_column('ops', 'workflows', 'updated_at', 'workflows.updated_at exists');
select has_column('ops', 'workflows', 'completed_at', 'workflows.completed_at exists');

select has_table('ops', 'jobs', 'jobs table exists');
select has_column('ops', 'jobs', 'id', 'jobs.id exists');
select has_column('ops', 'jobs', 'workflow_id', 'jobs.workflow_id exists');
select has_column('ops', 'jobs', 'parent_job_id', 'jobs.parent_job_id exists');
select has_column('ops', 'jobs', 'lead_id', 'jobs.lead_id exists');
select has_column('ops', 'jobs', 'agent_id', 'jobs.agent_id exists');
select has_column('ops', 'jobs', 'kind', 'jobs.kind exists');
select has_column('ops', 'jobs', 'status', 'jobs.status exists');
select has_column('ops', 'jobs', 'priority', 'jobs.priority exists');
select has_column('ops', 'jobs', 'input', 'jobs.input exists');
select has_column('ops', 'jobs', 'output', 'jobs.output exists');
select has_column('ops', 'jobs', 'confidence', 'jobs.confidence exists');
select has_column('ops', 'jobs', 'attempts', 'jobs.attempts exists');
select has_column('ops', 'jobs', 'max_attempts', 'jobs.max_attempts exists');
select has_column('ops', 'jobs', 'scheduled_for', 'jobs.scheduled_for exists');
select has_column('ops', 'jobs', 'locked_at', 'jobs.locked_at exists');
select has_column('ops', 'jobs', 'lock_owner', 'jobs.lock_owner exists');
select has_column('ops', 'jobs', 'started_at', 'jobs.started_at exists');
select has_column('ops', 'jobs', 'completed_at', 'jobs.completed_at exists');
select has_column('ops', 'jobs', 'error_code', 'jobs.error_code exists');
select has_column('ops', 'jobs', 'error_summary', 'jobs.error_summary exists');
select has_column('ops', 'jobs', 'idempotency_key', 'jobs.idempotency_key exists');
select has_column('ops', 'jobs', 'is_state_changing', 'jobs.is_state_changing exists');
select has_column('ops', 'jobs', 'created_at', 'jobs.created_at exists');
select has_column('ops', 'jobs', 'updated_at', 'jobs.updated_at exists');

select has_table('ops', 'job_events', 'job_events table exists');
select has_column('ops', 'job_events', 'id', 'job_events.id exists');
select has_column('ops', 'job_events', 'job_id', 'job_events.job_id exists');
select has_column('ops', 'job_events', 'at', 'job_events.at exists');
select has_column('ops', 'job_events', 'event', 'job_events.event exists');
select has_column('ops', 'job_events', 'actor', 'job_events.actor exists');
select has_column('ops', 'job_events', 'summary', 'job_events.summary exists');
select has_column('ops', 'job_events', 'details', 'job_events.details exists');

select has_table('ops', 'approvals', 'approvals table exists');
select has_column('ops', 'approvals', 'id', 'approvals.id exists');
select has_column('ops', 'approvals', 'job_id', 'approvals.job_id exists');
select has_column('ops', 'approvals', 'lead_id', 'approvals.lead_id exists');
select has_column('ops', 'approvals', 'action_type', 'approvals.action_type exists');
select has_column('ops', 'approvals', 'title', 'approvals.title exists');
select has_column('ops', 'approvals', 'preview', 'approvals.preview exists');
select has_column('ops', 'approvals', 'risk', 'approvals.risk exists');
select has_column('ops', 'approvals', 'status', 'approvals.status exists');
select has_column('ops', 'approvals', 'requested_at', 'approvals.requested_at exists');
select has_column('ops', 'approvals', 'decided_at', 'approvals.decided_at exists');
select has_column('ops', 'approvals', 'decided_by', 'approvals.decided_by exists');
select has_column('ops', 'approvals', 'decision_note', 'approvals.decision_note exists');
select has_column('ops', 'approvals', 'external_action_completed_at', 'approvals.external_action_completed_at exists');
select has_column('ops', 'approvals', 'external_action_completed_by', 'approvals.external_action_completed_by exists');

select has_table('ops', 'evidence', 'evidence table exists');
select has_column('ops', 'evidence', 'id', 'evidence.id exists');
select has_column('ops', 'evidence', 'lead_id', 'evidence.lead_id exists');
select has_column('ops', 'evidence', 'kind', 'evidence.kind exists');
select has_column('ops', 'evidence', 'value', 'evidence.value exists');
select has_column('ops', 'evidence', 'source_url', 'evidence.source_url exists');
select has_column('ops', 'evidence', 'source_label', 'evidence.source_label exists');
select has_column('ops', 'evidence', 'observed_at', 'evidence.observed_at exists');
select has_column('ops', 'evidence', 'confidence', 'evidence.confidence exists');
select has_column('ops', 'evidence', 'verified_by', 'evidence.verified_by exists');

select has_table('ops', 'memory_items', 'memory_items table exists');
select has_column('ops', 'memory_items', 'id', 'memory_items.id exists');
select has_column('ops', 'memory_items', 'scope', 'memory_items.scope exists');
select has_column('ops', 'memory_items', 'scope_id', 'memory_items.scope_id exists');
select has_column('ops', 'memory_items', 'kind', 'memory_items.kind exists');
select has_column('ops', 'memory_items', 'fact', 'memory_items.fact exists');
select has_column('ops', 'memory_items', 'source_job_id', 'memory_items.source_job_id exists');
select has_column('ops', 'memory_items', 'valid_from', 'memory_items.valid_from exists');
select has_column('ops', 'memory_items', 'expires_at', 'memory_items.expires_at exists');
select has_column('ops', 'memory_items', 'superseded_by', 'memory_items.superseded_by exists');

select has_table('ops', 'inbound_messages', 'inbound_messages table exists');
select has_column('ops', 'inbound_messages', 'id', 'inbound_messages.id exists');
select has_column('ops', 'inbound_messages', 'provider', 'inbound_messages.provider exists');
select has_column('ops', 'inbound_messages', 'provider_message_id', 'inbound_messages.provider_message_id exists');
select has_column('ops', 'inbound_messages', 'provider_thread_id', 'inbound_messages.provider_thread_id exists');
select has_column('ops', 'inbound_messages', 'sender_email', 'inbound_messages.sender_email exists');
select has_column('ops', 'inbound_messages', 'received_at', 'inbound_messages.received_at exists');
select has_column('ops', 'inbound_messages', 'classification', 'inbound_messages.classification exists');
select has_column('ops', 'inbound_messages', 'summary', 'inbound_messages.summary exists');
select has_column('ops', 'inbound_messages', 'lead_id', 'inbound_messages.lead_id exists');
select has_column('ops', 'inbound_messages', 'match_status', 'inbound_messages.match_status exists');
select has_column('ops', 'inbound_messages', 'processed_at', 'inbound_messages.processed_at exists');
select has_column('ops', 'inbound_messages', 'created_at', 'inbound_messages.created_at exists');

select has_table('ops', 'worker_devices', 'worker_devices table exists');
select has_column('ops', 'worker_devices', 'id', 'worker_devices.id exists');
select has_column('ops', 'worker_devices', 'display_name', 'worker_devices.display_name exists');
select has_column('ops', 'worker_devices', 'token_hash', 'worker_devices.token_hash exists');
select has_column('ops', 'worker_devices', 'status', 'worker_devices.status exists');
select has_column('ops', 'worker_devices', 'capabilities', 'worker_devices.capabilities exists');
select has_column('ops', 'worker_devices', 'enrolled_at', 'worker_devices.enrolled_at exists');
select has_column('ops', 'worker_devices', 'last_seen_at', 'worker_devices.last_seen_at exists');
select has_column('ops', 'worker_devices', 'revoked_at', 'worker_devices.revoked_at exists');

select has_column('ops', 'agents', 'current_job_id', 'agents.current_job_id exists');
select has_column('ops', 'agents', 'state', 'agents.state exists');
select has_column('ops', 'agents', 'queue_depth', 'agents.queue_depth exists');
select has_column('ops', 'agents', 'health', 'agents.health exists');
select has_column('ops', 'agents', 'model_tier', 'agents.model_tier exists');
select has_column('ops', 'agents', 'last_heartbeat', 'agents.last_heartbeat exists');
select has_column('ops', 'leads', 'automation_owner', 'leads.automation_owner exists');

select lives_ok(
  $$insert into ops.agents (id, name, role, status)
    values ('ci-agent', 'CI Agent', 'Database test worker', 'Live')$$,
  'a test agent fixture can be created'
);
select lives_ok(
  $$insert into ops.leads (id, business)
    values ('L-CI', 'CI Fixture Business')$$,
  'a test lead fixture can be created'
);
select lives_ok(
  $$insert into ops.workflows (id, kind, subject_type, subject_id, status, current_step)
    values ('10000000-0000-0000-0000-000000000001', 'lead_pipeline', 'lead', 'L-CI', 'active', 'qualify')$$,
  'an active lead workflow can be created'
);
select throws_ok(
  $$insert into ops.workflows (id, kind, subject_type, subject_id, status, current_step)
    values ('10000000-0000-0000-0000-000000000002', 'lead_pipeline', 'lead', 'L-CI', 'active', 'contact')$$,
  '23505',
  'duplicate key value violates unique constraint "workflows_active_subject_uq"',
  'a second active workflow for the same lead is rejected'
);

select throws_ok(
  $$insert into ops.jobs (id, workflow_id, agent_id, kind, status, idempotency_key)
    values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'ci-agent', 'test', 'unknown', 'ci-invalid-status')$$,
  '23514',
  'new row for relation "jobs" violates check constraint "jobs_status_check"',
  'jobs rejects an unknown status'
);

select lives_ok(
  $$insert into ops.jobs
      (id, workflow_id, lead_id, agent_id, kind, status, idempotency_key, is_state_changing)
    values
      ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'L-CI', 'ci-agent', 'update_lead', 'running', 'ci-running-one', true)$$,
  'one state-changing job can run for a lead'
);
select throws_ok(
  $$insert into ops.jobs
      (id, workflow_id, lead_id, agent_id, kind, status, idempotency_key, is_state_changing)
    values
      ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'L-CI', 'ci-agent', 'update_lead', 'running', 'ci-running-two', true)$$,
  '23505',
  'duplicate key value violates unique constraint "jobs_running_lead_state_change_uq"',
  'a lead cannot have two running state-changing jobs'
);

select lives_ok(
  $$insert into ops.inbound_messages
      (id, provider, provider_message_id, sender_email, received_at, classification, summary)
    values
      ('30000000-0000-0000-0000-000000000001', 'gmail', 'provider-message-ci', 'lead@example.com', now(), 'reply', 'Interested')$$,
  'an inbound provider message can be recorded'
);
select throws_ok(
  $$insert into ops.inbound_messages
      (id, provider, provider_message_id, sender_email, received_at, classification, summary)
    values
      ('30000000-0000-0000-0000-000000000002', 'gmail', 'provider-message-ci', 'other@example.com', now(), 'reply', 'Duplicate')$$,
  '23505',
  'duplicate key value violates unique constraint "inbound_messages_provider_message_uq"',
  'provider message identifiers cannot be processed twice'
);

select is(
  (
    select count(*)::bigint
    from information_schema.table_privileges
    where table_schema = 'ops'
      and grantee in ('PUBLIC', 'anon', 'authenticated')
  ),
  0::bigint,
  'ops tables grant no privileges to public API roles'
);
select is(has_schema_privilege('anon', 'ops', 'usage'), false, 'anon has no ops schema usage');
select is(has_schema_privilege('authenticated', 'ops', 'usage'), false, 'authenticated has no ops schema usage');
select is(
  (
    select count(*)::bigint
    from pg_namespace n
    cross join lateral aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
    where n.nspname = 'ops'
      and a.grantee = 0
      and a.privilege_type in ('USAGE', 'CREATE')
  ),
  0::bigint,
  'PUBLIC has no ops schema privileges'
);
select is(
  (
    select count(*)::bigint
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'ops'
      and c.relname in (
        'workflows', 'jobs', 'job_events', 'approvals',
        'evidence', 'memory_items', 'inbound_messages', 'worker_devices'
      )
      and c.relrowsecurity
  ),
  8::bigint,
  'row-level security is enabled on every orchestration table'
);

select * from finish();
rollback;

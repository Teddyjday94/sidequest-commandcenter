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

select has_function('ops', 'dispatch_work', array[]::text[], 'dispatch_work exists');
select has_function('ops', 'offer_job', array['text'], 'offer_job(text) exists');
select has_function('ops', 'claim_job', array['text', 'uuid'], 'claim_job(text, uuid) exists');
select has_function('ops', 'heartbeat_job', array['text', 'uuid'], 'heartbeat_job(text, uuid) exists');
select has_function('ops', 'complete_job', array['text', 'uuid', 'jsonb'], 'complete_job(text, uuid, jsonb) exists');
select has_function('ops', 'fail_job', array['text', 'uuid', 'text', 'text', 'boolean'], 'fail_job contract exists');
select has_function('ops', 'recover_expired_jobs', array[]::text[], 'recover_expired_jobs exists');
select has_function('ops', 'resolve_approval', array['uuid', 'text', 'text', 'uuid'], 'resolve_approval contract exists');
select has_function('ops', 'record_external_completion', array['uuid', 'uuid'], 'record_external_completion exists');
select has_function('ops', 'get_studio_snapshot', array[]::text[], 'get_studio_snapshot exists');

select lives_ok(
  $$insert into ops.agents (id, name, role, status)
    values ('finder', 'Contact Finder', 'Verifies contact routes', 'Live')$$,
  'dispatcher agent fixture can be created'
);
select lives_ok(
  $$insert into ops.worker_devices (id, display_name, token_hash, status, capabilities)
    values
      ('worker-one', 'Worker One', repeat('1', 64), 'active',
       '["kind:priority_high","kind:priority_low","kind:retry_test","kind:expired_test"]'::jsonb),
      ('worker-two', 'Worker Two', repeat('2', 64), 'active', '["kind:priority_low"]'::jsonb)$$,
  'active worker fixtures can be created'
);
select lives_ok(
  $$insert into ops.leads (id, business, stage, automation_owner)
    values ('L-DISPATCH', 'Dispatch Fixture Business', 'New', 'codex-pilot')$$,
  'a canary lead fixture can be created'
);

select lives_ok($$select ops.dispatch_work()$$, 'dispatcher accepts an eligible canary lead');
select lives_ok($$select ops.dispatch_work()$$, 'dispatcher can be repeated safely');
select is(
  (
    select count(*)::bigint
    from ops.workflows
    where kind = 'lead_pipeline'
      and subject_type = 'lead'
      and subject_id = 'L-DISPATCH'
      and status in ('active', 'waiting', 'blocked')
  ),
  1::bigint,
  'dispatcher creates one active workflow per eligible lead'
);
select is(
  (
    select count(*)::bigint
    from ops.jobs
    where idempotency_key = 'dispatch:lead:L-DISPATCH:contact_verification:v1'
  ),
  1::bigint,
  'dispatcher creates one idempotent contact-verification job'
);

select lives_ok(
  $$insert into ops.workflows (id, kind, subject_type, subject_id, status, current_step)
    values ('11000000-0000-0000-0000-000000000001', 'ci_queue', 'test', 'priority', 'active', 'queue')$$,
  'queue workflow fixture can be created'
);
select lives_ok(
  $$insert into ops.jobs
      (id, workflow_id, agent_id, kind, status, priority, idempotency_key)
    values
      ('21000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'ci-agent', 'priority_high', 'queued', 1, 'ci-priority-high'),
      ('21000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000001', 'ci-agent', 'priority_low', 'queued', 50, 'ci-priority-low')$$,
  'priority queue fixtures can be created'
);
select is(
  ops.offer_job('worker-two')->>'id',
  '21000000-0000-0000-0000-000000000002',
  'a worker is offered only a job allowed by its explicit kind capability'
);
select is(
  ops.claim_job('worker-two', '21000000-0000-0000-0000-000000000001'),
  null::jsonb,
  'a worker cannot claim a job outside its explicit capabilities'
);
select is(
  ops.offer_job('worker-one')->>'id',
  '21000000-0000-0000-0000-000000000001',
  'offer_job returns the highest-priority available job without claiming it'
);
select is(
  (select status from ops.jobs where id = '21000000-0000-0000-0000-000000000001'),
  'queued',
  'offering a job does not create a lease'
);
select lives_ok(
  $$select ops.claim_job('worker-one', '21000000-0000-0000-0000-000000000001')$$,
  'an active worker can claim the offered job'
);
select throws_ok(
  $$select ops.heartbeat_job('worker-two', '21000000-0000-0000-0000-000000000001')$$,
  '42501',
  'worker_mismatch',
  'a different worker cannot renew the lease'
);
select lives_ok(
  $$update ops.jobs
    set locked_at = now() - interval '10 minutes'
    where id = '21000000-0000-0000-0000-000000000001'$$,
  'lease age can be arranged for renewal testing'
);
select lives_ok(
  $$select ops.heartbeat_job('worker-one', '21000000-0000-0000-0000-000000000001')$$,
  'the owning worker can renew its lease'
);
select ok(
  (
    select locked_at > now() - interval '1 minute'
      and locked_at + interval '15 minutes' between now() + interval '14 minutes' and now() + interval '16 minutes'
    from ops.jobs
    where id = '21000000-0000-0000-0000-000000000001'
  ),
  'heartbeat renews the job to a fifteen-minute lease'
);
select throws_ok(
  $$select ops.complete_job(
      'worker-one',
      '21000000-0000-0000-0000-000000000002',
      '{"summary":"not claimed"}'::jsonb
    )$$,
  '55000',
  'job_not_running',
  'a queued job cannot jump directly to completed'
);
select lives_ok(
  $$select ops.complete_job(
      'worker-one',
      '21000000-0000-0000-0000-000000000001',
      '{"summary":"done","confidence":0.8}'::jsonb
    )$$,
  'the owning worker can complete a running job'
);
select lives_ok(
  $$select ops.complete_job(
      'worker-one',
      '21000000-0000-0000-0000-000000000001',
      '{"summary":"done","confidence":0.8}'::jsonb
    )$$,
  'repeating the same completion is idempotent'
);
select is(
  (
    select count(*)::bigint
    from ops.job_events
    where job_id = '21000000-0000-0000-0000-000000000001'
      and event = 'completed'
  ),
  1::bigint,
  'idempotent completion records one completed event'
);

select lives_ok(
  $$insert into ops.jobs
      (id, workflow_id, agent_id, kind, status, priority, max_attempts, idempotency_key)
    values
      ('22000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'ci-agent', 'retry_test', 'queued', 20, 2, 'ci-retry-test')$$,
  'retry fixture can be created'
);
select lives_ok(
  $$select ops.claim_job('worker-one', '22000000-0000-0000-0000-000000000001')$$,
  'retry fixture can be claimed once'
);
select lives_ok(
  $$select ops.fail_job(
      'worker-one',
      '22000000-0000-0000-0000-000000000001',
      'temporary',
      'Try again',
      true
    )$$,
  'a retryable first failure returns the job to the queue'
);
select is(
  (select status from ops.jobs where id = '22000000-0000-0000-0000-000000000001'),
  'queued',
  'retryable work is queued while attempts remain'
);
select lives_ok(
  $$select ops.claim_job('worker-one', '22000000-0000-0000-0000-000000000001')$$,
  'retry fixture can be claimed for its final attempt'
);
select lives_ok(
  $$select ops.fail_job(
      'worker-one',
      '22000000-0000-0000-0000-000000000001',
      'temporary',
      'Still failing',
      true
    )$$,
  'the final retryable failure is handled without another retry'
);
select is(
  (select status from ops.jobs where id = '22000000-0000-0000-0000-000000000001'),
  'blocked',
  'retry budget exhaustion blocks the job'
);
select is(
  (select attempts from ops.jobs where id = '22000000-0000-0000-0000-000000000001'),
  2,
  'claim attempts never exceed max_attempts'
);

select lives_ok(
  $$insert into ops.jobs
      (id, workflow_id, agent_id, kind, status, priority, attempts, max_attempts,
       locked_at, lock_owner, started_at, idempotency_key)
    values
      ('23000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'ci-agent', 'expired_test', 'running', 30, 1, 3,
       now() - interval '16 minutes', 'worker-one', now() - interval '20 minutes', 'ci-expired-test')$$,
  'expired lease fixture can be created'
);
select is(
  ops.claim_job('worker-one', '23000000-0000-0000-0000-000000000001'),
  null::jsonb,
  'an expired existing claim is not returned to its former worker'
);
select throws_ok(
  $$select ops.heartbeat_job('worker-one', '23000000-0000-0000-0000-000000000001')$$,
  '55000',
  'job_lease_expired',
  'an expired worker cannot renew its lease'
);
select throws_ok(
  $$select ops.complete_job(
      'worker-one',
      '23000000-0000-0000-0000-000000000001',
      '{"summary":"late result"}'::jsonb
    )$$,
  '55000',
  'job_lease_expired',
  'an expired worker cannot complete a recovered candidate'
);
select throws_ok(
  $$select ops.fail_job(
      'worker-one',
      '23000000-0000-0000-0000-000000000001',
      'late_failure',
      'Lease already expired',
      true
    )$$,
  '55000',
  'job_lease_expired',
  'an expired worker cannot mutate failure state'
);
select throws_ok(
  $$select ops.fail_job(
      'worker-one',
      '23000000-0000-0000-0000-000000000001',
      'lease_expired',
      'Worker lease expired before completion',
      true
    )$$,
  '55000',
  'job_lease_expired',
  'an expired worker cannot imitate the internal lease-recovery transition'
);
select lives_ok($$select ops.recover_expired_jobs()$$, 'expired leases can be recovered');
select ok(
  (
    select status = 'queued' and lock_owner is null and locked_at is null
    from ops.jobs
    where id = '23000000-0000-0000-0000-000000000001'
  ),
  'an expired job with retries remaining returns to the queue'
);

select lives_ok(
  $$insert into ops.approvals
      (id, job_id, action_type, title, risk, status)
    values
      ('31000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', 'send_draft', 'Review the draft', 'medium', 'pending')$$,
  'pending approval fixture can be created'
);
select lives_ok(
  $$select ops.resolve_approval(
      '31000000-0000-0000-0000-000000000001',
      'approved',
      'Reviewed',
      '41000000-0000-0000-0000-000000000001'
    )$$,
  'a pending approval can be resolved'
);
select lives_ok(
  $$select ops.resolve_approval(
      '31000000-0000-0000-0000-000000000001',
      'approved',
      'Reviewed',
      '41000000-0000-0000-0000-000000000001'
    )$$,
  'repeating the same approval decision is idempotent'
);
select is(
  (
    select count(*)::bigint
    from ops.job_events
    where job_id = '21000000-0000-0000-0000-000000000001'
      and event = 'approval_resolved'
  ),
  1::bigint,
  'idempotent approval records one decision event'
);
select throws_ok(
  $$select ops.resolve_approval(
      '31000000-0000-0000-0000-000000000001',
      'rejected',
      'Changed decision',
      '41000000-0000-0000-0000-000000000001'
    )$$,
  '55000',
  'approval_already_resolved',
  'a resolved approval cannot transition to a conflicting decision'
);
select lives_ok(
  $$select ops.record_external_completion(
      '31000000-0000-0000-0000-000000000001',
      '41000000-0000-0000-0000-000000000001'
    )$$,
  'approved work can be marked externally complete'
);
select lives_ok(
  $$select ops.record_external_completion(
      '31000000-0000-0000-0000-000000000001',
      '41000000-0000-0000-0000-000000000001'
    )$$,
  'external completion is idempotent'
);
select is(
  (
    select count(*)::bigint
    from ops.job_events
    where job_id = '21000000-0000-0000-0000-000000000001'
      and event = 'external_action_completed'
  ),
  1::bigint,
  'idempotent external completion records one event'
);

select ok(
  jsonb_typeof(ops.get_studio_snapshot()->'agents') = 'array'
    and jsonb_typeof(ops.get_studio_snapshot()->'jobs') = 'array'
    and jsonb_typeof(ops.get_studio_snapshot()->'approvals') = 'array'
    and jsonb_typeof(ops.get_studio_snapshot()->'activity') = 'array',
  'studio snapshot returns bounded purpose-built collections'
);

select is(
  (
    select count(*)::bigint
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'ops'
      and p.proname in (
        'dispatch_work', 'offer_job', 'claim_job', 'heartbeat_job', 'complete_job',
        'fail_job', 'recover_expired_jobs', 'resolve_approval',
        'record_external_completion', 'get_studio_snapshot'
      )
      and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
  ),
  10::bigint,
  'every orchestration function pins its search path'
);
select is(
  has_function_privilege('anon', 'ops.dispatch_work()', 'execute'),
  false,
  'anon cannot execute orchestration functions'
);
select is(
  has_function_privilege('authenticated', 'ops.dispatch_work()', 'execute'),
  false,
  'authenticated cannot execute orchestration functions'
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

begin;

select * from no_plan();

select is(
  (
    select count(*)::bigint
    from ops.missions
    where id in (
      'contact-finder-recurring', 'sales-agent-recurring',
      'mockup-builder-recurring', 'content-agent-recurring'
    )
  ),
  4::bigint,
  'the four agent crew missions are seeded'
);

select is(
  (
    select count(*)::bigint
    from ops.missions
    where id in (
      'contact-finder-recurring', 'sales-agent-recurring',
      'mockup-builder-recurring', 'content-agent-recurring'
    )
      and not enabled
  ),
  4::bigint,
  'every agent crew mission is disabled by default'
);

select is(
  (
    select jsonb_object_agg(id, job_kind order by id)
    from ops.missions
    where id in (
      'contact-finder-recurring', 'sales-agent-recurring',
      'mockup-builder-recurring', 'content-agent-recurring'
    )
  ),
  '{"contact-finder-recurring":"research","content-agent-recurring":"draft","mockup-builder-recurring":"draft","sales-agent-recurring":"draft"}'::jsonb,
  'mission kinds stay inside the generic worker contract'
);

select is(
  (
    select jsonb_object_agg(id, model_tier order by id)
    from ops.agents
    where id in (
      'contact-finder', 'sales-agent', 'mockup-builder',
      'content-agent', 'opportunity-analyst', 'quality-reviewer'
    )
  ),
  '{"contact-finder":"fast","content-agent":"standard","mockup-builder":"deep","opportunity-analyst":"standard","quality-reviewer":"standard","sales-agent":"standard"}'::jsonb,
  'agent rows use explicit model tiers without naming providers or models'
);

select ok(
  (select value = 'false' from ops.settings where key = 'automation_agent_crew_enabled')
    and (select value = '5' from ops.settings where key = 'automation_canary_limit')
    and (select value = 'true' from ops.settings where key = 'automation_calibration_mode')
    and (select value = '0.75' from ops.settings where key = 'automation_review_min_confidence'),
  'crew defaults are disabled, calibrated, confidence-gated, and capped at five'
);

select lives_ok(
  $$insert into ops.leads (id, business, stage, automation_owner, created_at)
    values
      ('L-ACT-01', 'Activation Eligible 1', 'New', 'codex-pilot', '2026-10-01 00:01:00+00'),
      ('L-ACT-02', 'Activation Eligible 2', 'New', 'codex-pilot', '2026-10-01 00:02:00+00'),
      ('L-ACT-03', 'Activation Eligible 3', 'New', 'codex-pilot', '2026-10-01 00:03:00+00'),
      ('L-ACT-04', 'Activation Eligible 4', 'New', 'codex-pilot', '2026-10-01 00:04:00+00'),
      ('L-ACT-05', 'Activation Eligible 5', 'New', 'codex-pilot', '2026-10-01 00:05:00+00'),
      ('L-ACT-06', 'Activation Eligible 6', 'New', 'codex-pilot', '2026-10-01 00:06:00+00'),
      ('L-ACT-LEGACY', 'Activation Legacy', 'New', null, '2026-09-01 00:00:00+00'),
      ('L-ACT-OPTOUT', 'Activation Opted Out', 'Opted out', 'codex-pilot', '2026-09-01 00:00:00+00')$$,
  'canary, legacy, and opted-out lead fixtures can be created'
);

select is(
  (ops.dispatch_work()->>'dispatched')::integer,
  0,
  'the disabled crew flag creates zero canary jobs'
);

select lives_ok(
  $$insert into ops.settings (key, value) values ('automation_agent_crew_enabled', 'true')
    on conflict (key) do update set value = excluded.value$$,
  'the test can enable the internal canary dispatcher'
);

select is(
  (ops.dispatch_work()->>'dispatched')::integer,
  5,
  'one dispatcher run creates at most five canary jobs'
);

select is(
  (
    select count(*)::bigint
    from ops.jobs
    where idempotency_key like 'dispatch:lead:L-ACT-%:contact_verification:v2'
  ),
  5::bigint,
  'the hard canary cap is enforced even when six leads are eligible'
);

select is(
  (ops.dispatch_work()->>'dispatched')::integer,
  0,
  'repeating the dispatcher is idempotent for the selected canary cohort'
);

select is(
  (
    select count(*)::bigint
    from ops.jobs
    where lead_id in ('L-ACT-06', 'L-ACT-LEGACY', 'L-ACT-OPTOUT')
  ),
  0::bigint,
  'overflow, legacy-owned, and opted-out leads are excluded'
);

select is(
  (
    select count(*)::bigint
    from ops.jobs
    where idempotency_key like 'dispatch:lead:L-ACT-%:contact_verification:v2'
      and agent_id = 'contact-finder'
      and kind = 'contact_verification'
      and input->>'handoff_policy' = 'reviewed-v1'
      and not is_state_changing
  ),
  5::bigint,
  'canary jobs use the contact-finder worker contract and require reviewed handoff'
);

select lives_ok(
  $$insert into ops.worker_devices (id, display_name, token_hash, status, capabilities)
    values (
      'activation-worker', 'Activation Worker', repeat('a', 64), 'active',
      '["kind:contact_verification","kind:draft","kind:review"]'::jsonb
    )$$,
  'a policy test worker can be created'
);

select lives_ok(
  $$insert into ops.workflows
      (id, kind, subject_type, subject_id, status, current_step)
    values
      ('51000000-0000-4000-8000-000000000001', 'activation_test', 'test', 'missing-evidence', 'active', 'draft'),
      ('51000000-0000-4000-8000-000000000002', 'activation_test', 'test', 'low-confidence', 'active', 'draft'),
      ('51000000-0000-4000-8000-000000000003', 'activation_test', 'test', 'review-pass', 'active', 'draft'),
      ('51000000-0000-4000-8000-000000000004', 'activation_test', 'test', 'one-revision', 'active', 'draft')$$,
  'quality-loop workflow fixtures can be created'
);

select lives_ok(
  $$insert into ops.jobs
      (id, workflow_id, agent_id, kind, status, input, attempts, max_attempts,
       locked_at, lock_owner, started_at, idempotency_key)
    values
      ('52000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000001',
       'sales-agent', 'draft', 'running', '{"handoff_policy":"reviewed-v1","task_type":"sales_draft"}'::jsonb,
       1, 3, now(), 'activation-worker', now(), 'activation:missing-evidence'),
      ('52000000-0000-4000-8000-000000000002', '51000000-0000-4000-8000-000000000002',
       'sales-agent', 'draft', 'running', '{"handoff_policy":"reviewed-v1","task_type":"sales_draft"}'::jsonb,
       1, 3, now(), 'activation-worker', now(), 'activation:low-confidence'),
      ('52000000-0000-4000-8000-000000000003', '51000000-0000-4000-8000-000000000003',
       'sales-agent', 'draft', 'running', '{"handoff_policy":"reviewed-v1","task_type":"sales_draft"}'::jsonb,
       1, 3, now(), 'activation-worker', now(), 'activation:review-pass'),
      ('52000000-0000-4000-8000-000000000004', '51000000-0000-4000-8000-000000000004',
       'content-agent', 'draft', 'running', '{"handoff_policy":"reviewed-v1","task_type":"content_draft"}'::jsonb,
       1, 3, now(), 'activation-worker', now(), 'activation:one-revision')$$,
  'quality-loop producer jobs can be created'
);

select throws_ok(
  $$select ops.complete_job(
      'activation-worker', '52000000-0000-4000-8000-000000000004',
      '{"job_id":"wrong-job","summary":"not a valid worker envelope"}'::jsonb
    )$$,
  '22023',
  'invalid_result_envelope',
  'reviewed jobs reject incomplete or mismatched worker envelopes'
);

select is(
  ops.complete_job(
    'activation-worker', '52000000-0000-4000-8000-000000000001',
    '{"job_id":"52000000-0000-4000-8000-000000000001","workflow_id":"51000000-0000-4000-8000-000000000001","agent_id":"sales-agent","kind":"draft","lead_id":null,"status":"completed","summary":"draft without sources","evidence":[],"confidence":0.95,"completed_operations":[],"blockers":[],"next_handoff":"quality_review","output":{"artifact_summary":"Draft without sources","artifact_refs":[]}}'::jsonb
  )->>'status',
  'blocked',
  'missing evidence is escalated instead of entering review'
);

select is(
  ops.complete_job(
    'activation-worker', '52000000-0000-4000-8000-000000000002',
    '{"job_id":"52000000-0000-4000-8000-000000000002","workflow_id":"51000000-0000-4000-8000-000000000002","agent_id":"sales-agent","kind":"draft","lead_id":null,"status":"completed","summary":"weak draft","evidence":[{"fact":"public fact","source_url":"https://example.com","source_label":"Public page","observed_at":"2026-10-25T12:00:00Z","confidence":0.40}],"confidence":0.40,"completed_operations":[],"blockers":[],"next_handoff":"quality_review","output":{"artifact_summary":"Weak draft","artifact_refs":[]}}'::jsonb
  )->>'status',
  'blocked',
  'low-confidence work is escalated instead of entering review'
);

select is(
  (
    select count(*)::bigint
    from ops.job_events
    where job_id in (
      '52000000-0000-4000-8000-000000000001',
      '52000000-0000-4000-8000-000000000002'
    )
      and event = 'quality_escalated'
  ),
  2::bigint,
  'policy escalations are explicit in the durable event ledger'
);

select lives_ok(
  $$select ops.complete_job(
      'activation-worker', '52000000-0000-4000-8000-000000000003',
      '{"job_id":"52000000-0000-4000-8000-000000000003","workflow_id":"51000000-0000-4000-8000-000000000003","agent_id":"sales-agent","kind":"draft","lead_id":null,"status":"completed","summary":"ready draft","evidence":[{"fact":"public contact found","source_url":"https://example.com/pass","source_label":"Public page","observed_at":"2026-10-25T12:00:00Z","confidence":0.91}],"confidence":0.91,"completed_operations":["drafted outreach"],"blockers":[],"next_handoff":"quality_review","output":{"artifact_summary":"Draft only","artifact_refs":[]}}'::jsonb
    )$$,
  'an evidenced producer result enters quality review'
);

select is(
  (
    select count(*)::bigint
    from ops.jobs
    where parent_job_id = '52000000-0000-4000-8000-000000000003'
      and agent_id = 'quality-reviewer'
      and kind = 'review'
      and status = 'queued'
      and input->'producer_output' = '{"artifact_summary":"Draft only","artifact_refs":[]}'::jsonb
      and jsonb_array_length(input->'producer_evidence') = 1
      and input ? 'lead_id'
  ),
  1::bigint,
  'producer completion creates exactly one quality-review job'
);

select lives_ok(
  $$select ops.claim_job(
      'activation-worker',
      (select id from ops.jobs where parent_job_id = '52000000-0000-4000-8000-000000000003')
    )$$,
  'the quality reviewer can claim the review job'
);

select lives_ok(
  $$select ops.complete_job(
      'activation-worker',
      (select id from ops.jobs where parent_job_id = '52000000-0000-4000-8000-000000000003'),
      jsonb_build_object(
        'job_id', (select id from ops.jobs where parent_job_id = '52000000-0000-4000-8000-000000000003')::text,
        'workflow_id', '51000000-0000-4000-8000-000000000003',
        'agent_id', 'quality-reviewer', 'kind', 'review', 'lead_id', null,
        'status', 'completed', 'summary', 'review passed',
        'evidence', '[{"fact":"producer evidence supports the draft","source_url":"https://example.com/pass","source_label":"Public page","observed_at":"2026-10-25T12:00:00Z","confidence":0.96}]'::jsonb,
        'confidence', 0.96, 'completed_operations', '["reviewed evidence"]'::jsonb,
        'blockers', '[]'::jsonb, 'next_handoff', 'owner_approval',
        'output', '{"decision":"pass","failing_checks":[],"evidence_gaps":[],"revision_instructions":[]}'::jsonb
      )
    )$$,
  'a passing review creates an owner approval handoff'
);

select ok(
  (
    select status = 'pending'
      and external_action_completed_at is null
      and preview->>'external_send_allowed' = 'false'
    from ops.approvals
    where job_id = (
      select id from ops.jobs where parent_job_id = '52000000-0000-4000-8000-000000000003'
    )
  ),
  'review pass stops at pending approval and never records an external send'
);

select lives_ok(
  $$select ops.complete_job(
      'activation-worker', '52000000-0000-4000-8000-000000000004',
      '{"job_id":"52000000-0000-4000-8000-000000000004","workflow_id":"51000000-0000-4000-8000-000000000004","agent_id":"content-agent","kind":"draft","lead_id":null,"status":"completed","summary":"content draft","evidence":[{"fact":"service detail","source_url":"https://example.com/revise","source_label":"Public page","observed_at":"2026-10-25T12:00:00Z","confidence":0.90}],"confidence":0.90,"completed_operations":["drafted content"],"blockers":[],"next_handoff":"quality_review","output":{"artifact_summary":"Draft","artifact_refs":[]}}'::jsonb
    )$$,
  'a second evidenced producer result enters review'
);

select lives_ok(
  $$select ops.claim_job(
      'activation-worker',
      (select id from ops.jobs where parent_job_id = '52000000-0000-4000-8000-000000000004')
    )$$,
  'the first revision review can be claimed'
);

select lives_ok(
  $$select ops.complete_job(
      'activation-worker',
      (select id from ops.jobs where parent_job_id = '52000000-0000-4000-8000-000000000004'),
      jsonb_build_object(
        'job_id', (select id from ops.jobs where parent_job_id = '52000000-0000-4000-8000-000000000004')::text,
        'workflow_id', '51000000-0000-4000-8000-000000000004',
        'agent_id', 'quality-reviewer', 'kind', 'review', 'lead_id', null,
        'status', 'completed', 'summary', 'one correction needed',
        'evidence', '[{"fact":"producer evidence does not support one claim","source_url":"https://example.com/revise","source_label":"Public page","observed_at":"2026-10-25T12:00:00Z","confidence":0.90}]'::jsonb,
        'confidence', 0.90, 'completed_operations', '["reviewed draft"]'::jsonb,
        'blockers', '[]'::jsonb, 'next_handoff', 'revision',
        'output', '{"decision":"revise","failing_checks":["unsupported claim"],"evidence_gaps":[],"revision_instructions":["Remove unsupported claim"]}'::jsonb
      )
    )$$,
  'the first reviewer failure requests one bounded revision'
);

select is(
  (
    select count(*)::bigint
    from ops.jobs
    where workflow_id = '51000000-0000-4000-8000-000000000004'
      and kind = 'draft'
      and input->>'revision_count' = '1'
      and input ? 'lead_id'
  ),
  1::bigint,
  'exactly one revision job is created'
);

select lives_ok(
  $$select ops.claim_job(
      'activation-worker',
      (select id from ops.jobs
       where workflow_id = '51000000-0000-4000-8000-000000000004'
         and kind = 'draft' and input->>'revision_count' = '1')
    )$$,
  'the single revision can be claimed'
);

select lives_ok(
  $$select ops.complete_job(
      'activation-worker',
      (select id from ops.jobs
       where workflow_id = '51000000-0000-4000-8000-000000000004'
         and kind = 'draft' and input->>'revision_count' = '1'),
      jsonb_build_object(
        'job_id', (select id from ops.jobs
          where workflow_id = '51000000-0000-4000-8000-000000000004'
            and kind = 'draft' and input->>'revision_count' = '1')::text,
        'workflow_id', '51000000-0000-4000-8000-000000000004',
        'agent_id', 'content-agent', 'kind', 'draft', 'lead_id', null,
        'status', 'completed', 'summary', 'revised content draft',
        'evidence', '[{"fact":"service detail","source_url":"https://example.com/revise","source_label":"Public page","observed_at":"2026-10-25T12:00:00Z","confidence":0.92}]'::jsonb,
        'confidence', 0.92, 'completed_operations', '["revised content"]'::jsonb,
        'blockers', '[]'::jsonb, 'next_handoff', 'quality_review',
        'output', '{"artifact_summary":"Corrected draft","artifact_refs":[]}'::jsonb
      )
    )$$,
  'the single revision returns to quality review'
);

select lives_ok(
  $$select ops.claim_job(
      'activation-worker',
      (select id from ops.jobs
       where workflow_id = '51000000-0000-4000-8000-000000000004'
         and kind = 'review'
         and parent_job_id = (
           select id from ops.jobs
           where workflow_id = '51000000-0000-4000-8000-000000000004'
             and kind = 'draft' and input->>'revision_count' = '1'
         ))
    )$$,
  'the second quality review can be claimed'
);

select is(
  ops.complete_job(
    'activation-worker',
    (select id from ops.jobs
     where workflow_id = '51000000-0000-4000-8000-000000000004'
       and kind = 'review'
       and parent_job_id = (
         select id from ops.jobs
         where workflow_id = '51000000-0000-4000-8000-000000000004'
           and kind = 'draft' and input->>'revision_count' = '1'
       )),
    jsonb_build_object(
      'job_id', (select id from ops.jobs
        where workflow_id = '51000000-0000-4000-8000-000000000004'
          and kind = 'review'
          and parent_job_id = (
            select id from ops.jobs
            where workflow_id = '51000000-0000-4000-8000-000000000004'
              and kind = 'draft' and input->>'revision_count' = '1'
          ))::text,
      'workflow_id', '51000000-0000-4000-8000-000000000004',
      'agent_id', 'quality-reviewer', 'kind', 'review', 'lead_id', null,
      'status', 'completed', 'summary', 'still unsafe',
      'evidence', '[{"fact":"revised output still contains an unsupported claim","source_url":"https://example.com/revise","source_label":"Public page","observed_at":"2026-10-25T12:00:00Z","confidence":0.91}]'::jsonb,
      'confidence', 0.91, 'completed_operations', '["reviewed revision"]'::jsonb,
      'blockers', '[]'::jsonb, 'next_handoff', 'manual_review',
      'output', '{"decision":"revise","failing_checks":["remaining unsafe claim"],"evidence_gaps":[],"revision_instructions":["A second rewrite would be required"]}'::jsonb
    )
  )->>'status',
  'blocked',
  'a second reviewer failure escalates instead of revising again'
);

select ok(
  (select status = 'blocked' from ops.workflows where id = '51000000-0000-4000-8000-000000000004')
    and (
      select count(*) = 1
      from ops.jobs
      where workflow_id = '51000000-0000-4000-8000-000000000004'
        and kind = 'draft' and input->>'revision_count' = '1'
    )
    and (
      select count(*) = 2
      from ops.jobs
      where workflow_id = '51000000-0000-4000-8000-000000000004'
        and kind = 'review'
    ),
  'the quality loop stops after one revision without recursive reviewer jobs'
);

select is(
  has_function_privilege('anon', 'ops.complete_job(text, uuid, jsonb)', 'execute'),
  false,
  'browser-anonymous callers cannot invoke quality transitions'
);

select is(
  has_function_privilege('authenticated', 'ops.dispatch_work()', 'execute'),
  false,
  'authenticated browser callers cannot run the canary dispatcher'
);

select is(
  has_function_privilege('service_role', 'ops.dispatch_work()', 'execute'),
  true,
  'the service role retains the internal dispatcher contract'
);

select * from finish();
rollback;

#!/usr/bin/env bash
set -euo pipefail

db_container="$(docker ps --filter 'name=supabase_db_sidequest-commandcenter' --format '{{.Names}}' | head -n 1)"
if [[ -z "$db_container" ]]; then
  echo 'Supabase database container was not found.' >&2
  exit 1
fi

worker_one_log="$(mktemp)"
worker_two_log="$(mktemp)"

cleanup() {
  docker exec -i "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres >/dev/null <<'SQL'
update ops.agents set current_job_id = null where id = 'race-agent';
delete from ops.job_events where job_id = '52000000-0000-0000-0000-000000000001';
delete from ops.jobs where id = '52000000-0000-0000-0000-000000000001';
delete from ops.workflows where id = '51000000-0000-0000-0000-000000000001';
delete from ops.worker_devices where id in ('race-worker-one', 'race-worker-two');
delete from ops.agents where id = 'race-agent';
SQL
  rm -f -- "$worker_one_log" "$worker_two_log"
}
trap cleanup EXIT

docker exec -i "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL'
insert into ops.worker_devices (id, display_name, token_hash, status, capabilities)
values
  ('race-worker-one', 'Race Worker One', repeat('3', 64), 'active', '["kind:race_claim"]'::jsonb),
  ('race-worker-two', 'Race Worker Two', repeat('4', 64), 'active', '["kind:race_claim"]'::jsonb);
insert into ops.agents (id, name, role, status)
values ('race-agent', 'Race Agent', 'Concurrency fixture', 'Live');
insert into ops.workflows (id, kind, subject_type, subject_id, status, current_step)
values ('51000000-0000-0000-0000-000000000001', 'ci_race', 'test', 'race', 'active', 'claim');
insert into ops.jobs (id, workflow_id, agent_id, kind, status, priority, idempotency_key)
values ('52000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001', 'race-agent', 'race_claim', 'queued', 1, 'ci-race-claim');
SQL

docker exec "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "begin; select ops.claim_job('race-worker-one', '52000000-0000-0000-0000-000000000001'); select pg_sleep(2); commit;" \
  >"$worker_one_log" 2>&1 &
worker_one_pid=$!

docker exec "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "begin; select ops.claim_job('race-worker-two', '52000000-0000-0000-0000-000000000001'); select pg_sleep(2); commit;" \
  >"$worker_two_log" 2>&1 &
worker_two_pid=$!

set +e
wait "$worker_one_pid"
worker_one_status=$?
wait "$worker_two_pid"
worker_two_status=$?
set -e

if [[ "$worker_one_status" -ne 0 || "$worker_two_status" -ne 0 ]]; then
  cat "$worker_one_log" "$worker_two_log" >&2
  exit 1
fi

race_result="$(docker exec -i "$db_container" psql -X -Atq -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL'
select concat_ws(
  '|',
  j.status,
  j.attempts,
  (select count(*) from ops.job_events e where e.job_id = j.id and e.event = 'claimed'),
  j.lock_owner
)
from ops.jobs j
where j.id = '52000000-0000-0000-0000-000000000001';
SQL
)"

if [[ ! "$race_result" =~ ^running\|1\|1\|race-worker-(one|two)$ ]]; then
  echo "Concurrent claim invariant failed: $race_result" >&2
  cat "$worker_one_log" "$worker_two_log" >&2
  exit 1
fi

echo "Concurrent claim passed: $race_result"

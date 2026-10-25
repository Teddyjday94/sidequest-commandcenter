#!/usr/bin/env bash
set -euo pipefail

db_container="$(docker ps --filter 'name=supabase_db_sidequest-commandcenter' --format '{{.Names}}' | head -n 1)"
if [[ -z "$db_container" ]]; then
  echo 'Supabase database container was not found.' >&2
  exit 1
fi

stop_log="$(mktemp)"
claim_log="$(mktemp)"

cleanup() {
  docker exec -i "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres >/dev/null <<'SQL'
update ops.settings set value = 'false' where key = 'automation_emergency_stop';
update ops.agents set current_job_id = null where id = 'stop-race-agent';
delete from ops.job_events where job_id = '62000000-0000-0000-0000-000000000001';
delete from ops.jobs where id = '62000000-0000-0000-0000-000000000001';
delete from ops.workflows where id = '61000000-0000-0000-0000-000000000001';
delete from ops.worker_devices where id = 'stop-race-worker';
delete from ops.agents where id = 'stop-race-agent';
SQL
  rm -f -- "$stop_log" "$claim_log"
}
trap cleanup EXIT

docker exec -i "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL'
update ops.settings set value = 'false' where key = 'automation_emergency_stop';
insert into ops.worker_devices (id, display_name, token_hash, status, capabilities)
values ('stop-race-worker', 'Stop Race Worker', repeat('6', 64), 'active', '["kind:stop_race"]'::jsonb);
insert into ops.agents (id, name, role, status)
values ('stop-race-agent', 'Stop Race Agent', 'Emergency-stop fixture', 'Live');
insert into ops.workflows (id, kind, subject_type, subject_id, status, current_step)
values ('61000000-0000-0000-0000-000000000001', 'ci_stop_race', 'test', 'stop-race', 'active', 'claim');
insert into ops.jobs (id, workflow_id, agent_id, kind, status, priority, idempotency_key)
values ('62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', 'stop-race-agent', 'stop_race', 'queued', 1, 'ci-stop-race');
SQL

docker exec "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "begin; select pg_advisory_xact_lock(hashtext('ops.automation_gate')); update ops.settings set value = 'true' where key = 'automation_emergency_stop'; select pg_sleep(2); commit;" \
  >"$stop_log" 2>&1 &
stop_pid=$!

sleep 0.5
set +e
docker exec "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "select ops.claim_job('stop-race-worker', '62000000-0000-0000-0000-000000000001');" \
  >"$claim_log" 2>&1
claim_status=$?
wait "$stop_pid"
stop_status=$?
set -e

if [[ "$stop_status" -ne 0 ]]; then
  cat "$stop_log" >&2
  exit 1
fi
if [[ "$claim_status" -eq 0 ]]; then
  echo 'A claim succeeded while the emergency stop transaction was committing.' >&2
  cat "$claim_log" >&2
  exit 1
fi

job_status="$(docker exec "$db_container" psql -X -Atq -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "select status from ops.jobs where id = '62000000-0000-0000-0000-000000000001';")"
if [[ "$job_status" != 'queued' ]]; then
  echo "Emergency-stop race changed the job state: $job_status" >&2
  exit 1
fi

echo 'Concurrent emergency stop passed: the queued job was not claimed.'

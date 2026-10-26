-- The server-side worker broker authenticates device tokens through this table.
-- Browser roles retain no direct access; only the server-held service role can read
-- worker identities and update their heartbeat timestamp.

revoke all on table ops.worker_devices from anon, authenticated;
grant select, update on table ops.worker_devices to service_role;

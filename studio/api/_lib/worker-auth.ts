import { createHash } from 'node:crypto'

import { HttpError } from './http.js'

type JsonRecord = Record<string, unknown>

export interface WorkerDevice {
  id: string
  displayName: string
  capabilities: string[]
}

interface WorkerDeviceRow {
  id: string
  display_name: string
  status: string
  capabilities: unknown
  revoked_at: string | null
}

interface WorkerDeviceQuery {
  maybeSingle(): Promise<{ data: WorkerDeviceRow | null; error: { message: string } | null }>
}

interface WorkerDeviceFilter {
  eq(column: 'token_hash', value: string): WorkerDeviceQuery
}

interface WorkerDeviceUpdate {
  eq(column: 'id', value: string): Promise<{ error: { message: string } | null }>
}

interface WorkerDeviceTable {
  select(columns: string): WorkerDeviceFilter
  update(values: JsonRecord): WorkerDeviceUpdate
}

export type WorkerProcedure =
  | 'offer_job'
  | 'claim_job'
  | 'heartbeat_job'
  | 'complete_job'
  | 'fail_job'

export interface WorkerAdminClient {
  schema(name: 'ops'): {
    from(table: 'worker_devices'): WorkerDeviceTable
    rpc(
      name: WorkerProcedure,
      args: Record<string, unknown>,
    ): Promise<{ data: unknown; error: { code?: string; message: string } | null }>
  }
}

const workerAuthorization = /^Worker ([A-Za-z0-9_-]{32,256})$/
const workerColumns = 'id,display_name,status,capabilities,revoked_at'

function parseWorkerToken(request: Request): string {
  const match = workerAuthorization.exec(request.headers.get('authorization') ?? '')
  const token = match?.[1]
  if (!token) throw new HttpError(401, 'worker_auth_required')
  return token
}

export function hashWorkerToken(token: string): string {
  return createHash('sha256').update(token, 'utf8').digest('hex')
}

export async function requireWorker(
  request: Request,
  admin: WorkerAdminClient,
  now: () => Date = () => new Date(),
): Promise<WorkerDevice> {
  const token = parseWorkerToken(request)
  const tokenHash = hashWorkerToken(token)
  const table = admin.schema('ops').from('worker_devices')
  const { data, error } = await table.select(workerColumns).eq('token_hash', tokenHash).maybeSingle()

  if (error) {
    console.error('worker_auth_lookup_failed')
    throw new HttpError(502, 'worker_unavailable')
  }
  if (!data || data.status !== 'active' || data.revoked_at !== null) {
    throw new HttpError(401, 'worker_not_authorized')
  }

  const capabilities = Array.isArray(data.capabilities)
    ? data.capabilities.filter((value): value is string => typeof value === 'string').slice(0, 32)
    : []
  const updateResult = await table.update({ last_seen_at: now().toISOString() }).eq('id', data.id)
  if (updateResult.error) {
    console.error('worker_last_seen_update_failed')
    throw new HttpError(502, 'worker_unavailable')
  }

  return {
    id: data.id.slice(0, 200),
    displayName: data.display_name.slice(0, 200),
    capabilities,
  }
}

export function throwWorkerProcedureError(error: { code?: string; message: string }): never {
  if (
    error.code === '55000' ||
    error.message === 'worker_mismatch' ||
    error.message === 'job_not_running'
  ) {
    throw new HttpError(409, 'worker_lease_conflict')
  }
  if (error.code === '42501' || error.message === 'worker_not_active') {
    throw new HttpError(401, 'worker_not_authorized')
  }
  if (error.code === '22023') throw new HttpError(400, 'worker_request_rejected')

  console.error('worker_procedure_failed')
  throw new HttpError(502, 'worker_unavailable')
}


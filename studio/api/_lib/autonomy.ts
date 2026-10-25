import { HttpError } from './http.js'
import type { OwnerAuthClient } from './owner-auth.js'

type JsonRecord = Record<string, unknown>

export interface AutonomyAdminClient extends OwnerAuthClient {
  schema(name: 'ops'): {
    rpc(
      name: 'set_mission_enabled' | 'set_emergency_stop',
      args: Record<string, unknown>,
    ): Promise<{ data: unknown; error: { code?: string; message: string } | null }>
  }
}

export function requireExactKeys(body: JsonRecord, allowed: readonly string[]): void {
  const allowedKeys = new Set(allowed)
  if (Object.keys(body).some((key) => !allowedKeys.has(key))) {
    throw new HttpError(400, 'invalid_request_body')
  }
}

export function enabledFrom(body: JsonRecord): boolean {
  if (typeof body.enabled !== 'boolean') throw new HttpError(400, 'invalid_enabled')
  return body.enabled
}

export function missionIdFrom(body: JsonRecord): string {
  const missionId = typeof body.missionId === 'string' ? body.missionId : ''
  if (!/^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$/.test(missionId)) {
    throw new HttpError(400, 'invalid_mission_id')
  }
  return missionId
}

export function throwAutonomyProcedureError(
  error: { code?: string; message: string },
  fallback: string,
): never {
  if (error.message === 'mission_not_found') throw new HttpError(404, 'mission_not_found')
  if (error.code === '22023') throw new HttpError(400, fallback)
  console.error('autonomy_procedure_failed')
  throw new HttpError(502, 'autonomy_unavailable')
}

import {
  enabledFrom,
  requireExactKeys,
  throwAutonomyProcedureError,
  type AutonomyAdminClient,
} from './_lib/autonomy.js'
import { requireCsrf } from './_lib/csrf.js'
import { readServerEnv } from './_lib/env.js'
import { errorResponse, HttpError, jsonResponse } from './_lib/http.js'
import { requireOwner, type OwnerSession } from './_lib/owner-auth.js'
import { getAdminClient } from './_lib/supabase.js'
import { readJsonObject } from './_lib/validation.js'

interface EmergencyStopDependencies {
  admin?: AutonomyAdminClient
  ownerUserId?: string
  csrf?: (request: Request, session: OwnerSession) => void
}

export function createEmergencyStopHandler(dependencies: EmergencyStopDependencies = {}) {
  return async function POST(request: Request): Promise<Response> {
    try {
      const admin = dependencies.admin ?? (getAdminClient() as unknown as AutonomyAdminClient)
      const ownerUserId = dependencies.ownerUserId ?? readServerEnv().ownerUserId
      const session = await requireOwner(request, { admin, ownerUserId })
      ;(dependencies.csrf ?? requireCsrf)(request, session)

      const body = await readJsonObject(request)
      requireExactKeys(body, ['enabled'])
      const enabled = enabledFrom(body)
      const { error } = await admin.schema('ops').rpc('set_emergency_stop', {
        p_enabled: enabled,
        p_actor: session.userId,
      })
      if (error) throwAutonomyProcedureError(error, 'emergency_stop_rejected')

      return jsonResponse({ enabled }, 200, { 'cache-control': 'private, no-store' })
    } catch (error) {
      if (!(error instanceof HttpError)) console.error('emergency_stop_failed')
      return errorResponse(error)
    }
  }
}

export const POST = createEmergencyStopHandler()

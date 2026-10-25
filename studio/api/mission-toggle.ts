import {
  enabledFrom,
  missionIdFrom,
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

interface MissionToggleDependencies {
  admin?: AutonomyAdminClient
  ownerUserId?: string
  csrf?: (request: Request, session: OwnerSession) => void
}

export function createMissionToggleHandler(dependencies: MissionToggleDependencies = {}) {
  return async function POST(request: Request): Promise<Response> {
    try {
      const admin = dependencies.admin ?? (getAdminClient() as unknown as AutonomyAdminClient)
      const ownerUserId = dependencies.ownerUserId ?? readServerEnv().ownerUserId
      const session = await requireOwner(request, { admin, ownerUserId })
      ;(dependencies.csrf ?? requireCsrf)(request, session)

      const body = await readJsonObject(request)
      requireExactKeys(body, ['missionId', 'enabled'])
      const missionId = missionIdFrom(body)
      const enabled = enabledFrom(body)
      const { error } = await admin.schema('ops').rpc('set_mission_enabled', {
        p_mission_id: missionId,
        p_enabled: enabled,
        p_actor: session.userId,
      })
      if (error) throwAutonomyProcedureError(error, 'mission_toggle_rejected')

      return jsonResponse({ id: missionId, enabled }, 200, { 'cache-control': 'private, no-store' })
    } catch (error) {
      if (!(error instanceof HttpError)) console.error('mission_toggle_failed')
      return errorResponse(error)
    }
  }
}

export const POST = createMissionToggleHandler()

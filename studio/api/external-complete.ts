import { requireCsrf } from './_lib/csrf.js'
import { readServerEnv } from './_lib/env.js'
import { errorResponse, HttpError, jsonResponse } from './_lib/http.js'
import { requireOwner, type OwnerSession } from './_lib/owner-auth.js'
import { getAdminClient } from './_lib/supabase.js'
import {
  approvalIdFrom,
  getApproval,
  normalizeApproval,
  readJsonObject,
  throwProcedureError,
  type ApprovalAdminClient,
} from './_lib/validation.js'

interface ExternalCompleteDependencies {
  admin?: ApprovalAdminClient
  ownerUserId?: string
  csrf?: (request: Request, session: OwnerSession) => void
}

export function createExternalCompleteHandler(dependencies: ExternalCompleteDependencies = {}) {
  return async function POST(request: Request): Promise<Response> {
    try {
      const admin = dependencies.admin ?? (getAdminClient() as unknown as ApprovalAdminClient)
      const ownerUserId = dependencies.ownerUserId ?? readServerEnv().ownerUserId
      const session = await requireOwner(request, { admin, ownerUserId })
      ;(dependencies.csrf ?? requireCsrf)(request, session)

      const approvalId = approvalIdFrom(await readJsonObject(request))
      const approval = await getApproval(admin, approvalId)
      if (approval.status !== 'approved') {
        throw new HttpError(409, 'approval_not_approved')
      }

      const { error } = await admin.schema('ops').rpc('record_external_completion', {
        p_approval_id: approvalId,
        p_actor: session.userId,
      })
      if (error) throwProcedureError(error, 'external_completion_conflict')

      const updated = await getApproval(admin, approvalId)
      return jsonResponse(normalizeApproval(updated), 200, { 'cache-control': 'private, no-store' })
    } catch (error) {
      if (!(error instanceof HttpError)) console.error('external_completion_failed')
      return errorResponse(error)
    }
  }
}

export const POST = createExternalCompleteHandler()

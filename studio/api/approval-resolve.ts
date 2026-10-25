import { requireCsrf } from './_lib/csrf.js'
import { readServerEnv } from './_lib/env.js'
import { errorResponse, HttpError, jsonResponse } from './_lib/http.js'
import { requireOwner, type OwnerSession } from './_lib/owner-auth.js'
import { getAdminClient } from './_lib/supabase.js'
import {
  approvalDecisionFrom,
  approvalIdFrom,
  approvalNoteFrom,
  getApproval,
  normalizeApproval,
  readJsonObject,
  throwProcedureError,
  type ApprovalAdminClient,
} from './_lib/validation.js'

interface ApprovalResolveDependencies {
  admin?: ApprovalAdminClient
  ownerUserId?: string
  csrf?: (request: Request, session: OwnerSession) => void
}

export function createApprovalResolveHandler(dependencies: ApprovalResolveDependencies = {}) {
  return async function POST(request: Request): Promise<Response> {
    try {
      const admin = dependencies.admin ?? (getAdminClient() as unknown as ApprovalAdminClient)
      const ownerUserId = dependencies.ownerUserId ?? readServerEnv().ownerUserId
      const session = await requireOwner(request, { admin, ownerUserId })
      ;(dependencies.csrf ?? requireCsrf)(request, session)

      const body = await readJsonObject(request)
      const approvalId = approvalIdFrom(body)
      const { databaseDecision } = approvalDecisionFrom(body)
      const note = approvalNoteFrom(body)
      const approval = await getApproval(admin, approvalId)
      const normalized = normalizeApproval(approval)

      if (approval.risk === 'high' && note === '') {
        throw new HttpError(400, 'high_risk_note_required')
      }
      if (databaseDecision === 'approved' && normalized.preview.length === 0) {
        throw new HttpError(409, 'approval_preview_required')
      }

      const { error } = await admin.schema('ops').rpc('resolve_approval', {
        p_approval_id: approvalId,
        p_decision: databaseDecision,
        p_note: note,
        p_actor: session.userId,
      })
      if (error) throwProcedureError(error, 'approval_conflict')

      const updated = await getApproval(admin, approvalId)
      return jsonResponse(normalizeApproval(updated), 200, { 'cache-control': 'private, no-store' })
    } catch (error) {
      if (!(error instanceof HttpError)) console.error('approval_resolve_failed')
      return errorResponse(error)
    }
  }
}

export const POST = createApprovalResolveHandler()

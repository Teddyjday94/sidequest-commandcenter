import type { ApprovalDTO } from '../../src/types.js'
import { approvalPreview } from './approval-preview.js'
import { HttpError } from './http.js'
import type { OwnerAuthClient } from './owner-auth.js'

type JsonRecord = Record<string, unknown>

export type ApprovalDecision = 'approve' | 'reject' | 'revise'
export type DatabaseApprovalDecision = 'approved' | 'rejected' | 'revised'

export interface ApprovalRecord {
  id: string
  job_id: string
  lead_id: string | null
  action_type: string
  title: string
  risk: string
  status: string
  requested_at: string | null
  decided_at: string | null
  decision_note: string | null
  external_action_completed_at: string | null
  preview: unknown
}

interface ApprovalQuery {
  maybeSingle(): Promise<{ data: ApprovalRecord | null; error: { code?: string; message: string } | null }>
}

interface ApprovalFilter {
  eq(column: 'id', value: string): ApprovalQuery
}

interface ApprovalTable {
  select(columns: string): ApprovalFilter
}

export interface ApprovalAdminClient extends OwnerAuthClient {
  schema(name: 'ops'): {
    from(table: 'approvals'): ApprovalTable
    rpc(
      name: 'resolve_approval' | 'record_external_completion',
      args: Record<string, unknown>,
    ): Promise<{ data: unknown; error: { code?: string; message: string } | null }>
  }
}

const approvalColumns = [
  'id',
  'job_id',
  'lead_id',
  'action_type',
  'title',
  'risk',
  'status',
  'requested_at',
  'decided_at',
  'decision_note',
  'external_action_completed_at',
  'preview',
].join(',')

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function object(value: unknown): JsonRecord {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new HttpError(400, 'invalid_json_body')
  }
  return value as JsonRecord
}

export async function readJsonObject(request: Request, maximumBytes = 8192): Promise<JsonRecord> {
  if (!request.headers.get('content-type')?.toLowerCase().startsWith('application/json')) {
    throw new HttpError(415, 'json_required')
  }

  const declaredLength = Number(request.headers.get('content-length') ?? '0')
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new HttpError(413, 'request_too_large')
  }

  const raw = await request.text()
  if (Buffer.byteLength(raw, 'utf8') > maximumBytes) {
    throw new HttpError(413, 'request_too_large')
  }

  try {
    return object(JSON.parse(raw) as unknown)
  } catch (error) {
    if (error instanceof HttpError) throw error
    throw new HttpError(400, 'invalid_json_body')
  }
}

export function approvalIdFrom(body: JsonRecord): string {
  const approvalId = typeof body.approvalId === 'string' ? body.approvalId : ''
  if (!uuidPattern.test(approvalId)) {
    throw new HttpError(400, 'invalid_approval_id')
  }
  return approvalId
}

export function approvalDecisionFrom(body: JsonRecord): {
  decision: ApprovalDecision
  databaseDecision: DatabaseApprovalDecision
} {
  const decision = body.decision
  if (decision !== 'approve' && decision !== 'reject' && decision !== 'revise') {
    throw new HttpError(400, 'invalid_approval_decision')
  }

  const databaseDecision = {
    approve: 'approved',
    reject: 'rejected',
    revise: 'revised',
  }[decision] as DatabaseApprovalDecision

  return { decision, databaseDecision }
}

export function approvalNoteFrom(body: JsonRecord): string {
  if (body.note === undefined || body.note === null) return ''
  if (typeof body.note !== 'string') throw new HttpError(400, 'invalid_approval_note')

  const note = body.note.trim()
  if (note.length > 2000) throw new HttpError(400, 'invalid_approval_note')
  return note
}

export async function getApproval(admin: ApprovalAdminClient, approvalId: string): Promise<ApprovalRecord> {
  const { data, error } = await admin
    .schema('ops')
    .from('approvals')
    .select(approvalColumns)
    .eq('id', approvalId)
    .maybeSingle()

  if (error) {
    console.error('approval_lookup_failed')
    throw new HttpError(502, 'approval_unavailable')
  }
  if (!data) throw new HttpError(404, 'approval_not_found')
  return data
}

export function normalizeApproval(row: ApprovalRecord): ApprovalDTO {
  return {
    id: row.id,
    jobId: row.job_id,
    leadId: row.lead_id,
    actionType: row.action_type,
    title: row.title,
    risk: row.risk,
    status: row.status,
    requestedAt: row.requested_at,
    decidedAt: row.decided_at,
    decisionNote: row.decision_note,
    externalActionCompletedAt: row.external_action_completed_at,
    preview: approvalPreview(row.action_type, row.preview),
  }
}

export function throwProcedureError(error: { code?: string; message: string }, fallback: string): never {
  const isConflict =
    error.code === '55000' ||
    error.message === 'approval_already_resolved' ||
    error.message === 'approval_not_approved' ||
    error.message === 'external_action_already_completed'

  if (isConflict) throw new HttpError(409, fallback)
  console.error('approval_procedure_failed')
  throw new HttpError(502, 'approval_unavailable')
}

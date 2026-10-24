import { describe, expect, it, vi } from 'vitest'

import { HttpError } from '../../api/_lib/http.js'
import { createApprovalResolveHandler } from '../../api/approval-resolve.js'
import { createExternalCompleteHandler } from '../../api/external-complete.js'

const ownerId = '41000000-0000-0000-0000-000000000001'
const approvalId = '31000000-0000-0000-0000-000000000001'

type ApprovalStatus = 'pending' | 'approved' | 'rejected' | 'revised'

function approvalRow(status: ApprovalStatus = 'pending', risk = 'medium') {
  return {
    id: approvalId,
    job_id: '21000000-0000-0000-0000-000000000001',
    lead_id: 'L01',
    action_type: 'send_draft',
    title: 'Review the draft',
    risk,
    status,
    requested_at: '2026-10-24T20:00:00Z',
    decided_at: status === 'pending' ? null : '2026-10-24T20:01:00Z',
    decision_note: status === 'pending' ? null : 'Reviewed',
    external_action_completed_at: null as string | null,
  }
}

function fakeAdmin(options: {
  userId?: string
  status?: ApprovalStatus
  risk?: string
  approvalExists?: boolean
  rpcError?: { code: string; message: string }
} = {}) {
  let row = approvalRow(options.status ?? 'pending', options.risk ?? 'medium')
  let mutations = 0
  const getUser = vi.fn().mockResolvedValue({
    data: { user: { id: options.userId ?? ownerId } },
    error: null,
  })
  const maybeSingle = vi.fn(async () => ({
    data: options.approvalExists === false ? null : { ...row },
    error: null,
  }))
  const eq = vi.fn().mockReturnValue({ maybeSingle })
  const select = vi.fn().mockReturnValue({ eq })
  const from = vi.fn().mockReturnValue({ select })
  const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
    if (options.rpcError) return { data: null, error: options.rpcError }
    if (name === 'resolve_approval') {
      const next = ['approved', 'rejected', 'revised'].includes(String(args.p_decision))
        ? (String(args.p_decision) as ApprovalStatus)
        : undefined
      if (row.status === 'pending' && next) {
        row = { ...row, status: next, decided_at: '2026-10-24T20:01:00Z', decision_note: String(args.p_note ?? '') }
        mutations += 1
      }
      return { data: { id: approvalId, status: row.status }, error: null }
    }
    if (name === 'record_external_completion') {
      mutations += 1
      row = { ...row, external_action_completed_at: '2026-10-24T20:02:00Z' }
      return { data: { id: approvalId, status: 'completed' }, error: null }
    }
    return { data: null, error: { code: 'unknown_rpc', message: 'unexpected procedure' } }
  })
  const schema = vi.fn().mockReturnValue({ from, rpc })

  return {
    client: { auth: { getUser }, schema },
    getUser,
    schema,
    from,
    rpc,
    mutationCount: () => mutations,
  }
}

function post(path: string, body: unknown) {
  return new Request(`https://studio.example.test/api/${path}`, {
    method: 'POST',
    headers: {
      authorization: 'Bearer valid-owner-token',
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  })
}

const allowCsrf = vi.fn()

describe('POST /api/approval-resolve', () => {
  it('rejects a non-owner before approval lookup or mutation', async () => {
    const admin = fakeAdmin({ userId: '42000000-0000-0000-0000-000000000002' })
    const handler = createApprovalResolveHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const response = await handler(post('approval-resolve', { approvalId, decision: 'approve', note: '' }))

    expect(response.status).toBe(403)
    expect(admin.schema).not.toHaveBeenCalled()
    expect(admin.rpc).not.toHaveBeenCalled()
  })

  it('rejects CSRF before approval lookup or mutation', async () => {
    const admin = fakeAdmin()
    const csrf = vi.fn(() => {
      throw new HttpError(403, 'csrf_rejected')
    })
    const handler = createApprovalResolveHandler({ admin: admin.client, ownerUserId: ownerId, csrf })

    const response = await handler(post('approval-resolve', { approvalId, decision: 'approve', note: '' }))

    expect(response.status).toBe(403)
    expect(admin.schema).not.toHaveBeenCalled()
  })

  it.each([
    [{ approvalId: 'not-a-uuid', decision: 'approve', note: '' }, 'invalid_approval_id'],
    [{ approvalId, decision: 'ship-it', note: '' }, 'invalid_approval_decision'],
  ])('rejects malformed input before a database call', async (body, errorCode) => {
    const admin = fakeAdmin()
    const handler = createApprovalResolveHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const response = await handler(post('approval-resolve', body))

    expect(response.status).toBe(400)
    expect(await response.json()).toEqual({ error: errorCode })
    expect(admin.schema).not.toHaveBeenCalled()
  })

  it('requires a non-empty note for a high-risk approval', async () => {
    const admin = fakeAdmin({ risk: 'high' })
    const handler = createApprovalResolveHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const response = await handler(post('approval-resolve', { approvalId, decision: 'approve', note: '  ' }))

    expect(response.status).toBe(400)
    expect(await response.json()).toEqual({ error: 'high_risk_note_required' })
    expect(admin.rpc).not.toHaveBeenCalled()
  })

  it('keeps a repeated identical decision idempotent with one database mutation', async () => {
    const admin = fakeAdmin()
    const handler = createApprovalResolveHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })
    const requestBody = { approvalId, decision: 'approve', note: 'Reviewed' }

    const first = await handler(post('approval-resolve', requestBody))
    const second = await handler(post('approval-resolve', requestBody))

    expect(first.status).toBe(200)
    expect(second.status).toBe(200)
    expect(admin.rpc).toHaveBeenCalledTimes(2)
    expect(admin.mutationCount()).toBe(1)
    expect(await second.json()).toMatchObject({ id: approvalId, status: 'approved', decisionNote: 'Reviewed' })
  })

  it('maps a database conflict to 409 without retrying the mutation', async () => {
    const admin = fakeAdmin({
      status: 'approved',
      rpcError: { code: '55000', message: 'approval_already_resolved' },
    })
    const handler = createApprovalResolveHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const response = await handler(
      post('approval-resolve', { approvalId, decision: 'reject', note: 'Conflicting decision' }),
    )

    expect(response.status).toBe(409)
    expect(await response.json()).toEqual({ error: 'approval_conflict' })
    expect(admin.rpc).toHaveBeenCalledTimes(1)
  })

  it('calls only the approval procedure and never performs an external action', async () => {
    const admin = fakeAdmin()
    const fetchSpy = vi.spyOn(globalThis, 'fetch')
    const handler = createApprovalResolveHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const response = await handler(
      post('approval-resolve', { approvalId, decision: 'approve', note: 'I will perform this myself' }),
    )

    expect(response.status).toBe(200)
    expect(admin.rpc.mock.calls.map(([name]) => name)).toEqual(['resolve_approval'])
    expect(fetchSpy).not.toHaveBeenCalled()
    fetchSpy.mockRestore()
  })
})

describe('POST /api/external-complete', () => {
  it('rejects completion before approval without a mutation', async () => {
    const admin = fakeAdmin({ status: 'pending' })
    const handler = createExternalCompleteHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const response = await handler(post('external-complete', { approvalId }))

    expect(response.status).toBe(409)
    expect(await response.json()).toEqual({ error: 'approval_not_approved' })
    expect(admin.rpc).not.toHaveBeenCalled()
  })

  it('records only manual completion and returns the normalized approval', async () => {
    const admin = fakeAdmin({ status: 'approved' })
    const fetchSpy = vi.spyOn(globalThis, 'fetch')
    const handler = createExternalCompleteHandler({ admin: admin.client, ownerUserId: ownerId, csrf: allowCsrf })

    const response = await handler(post('external-complete', { approvalId }))
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(admin.rpc.mock.calls.map(([name]) => name)).toEqual(['record_external_completion'])
    expect(body).toMatchObject({
      id: approvalId,
      status: 'approved',
      externalActionCompletedAt: '2026-10-24T20:02:00Z',
    })
    expect(fetchSpy).not.toHaveBeenCalled()
    fetchSpy.mockRestore()
  })
})

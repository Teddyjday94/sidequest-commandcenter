import { createHash } from 'node:crypto'

import { describe, expect, it, vi } from 'vitest'

import { createWorkerClaimHandler } from '../../api/worker-claim.js'
import { createWorkerFailHandler } from '../../api/worker-fail.js'
import { createWorkerHeartbeatHandler } from '../../api/worker-heartbeat.js'
import { createWorkerOfferHandler } from '../../api/worker-offer.js'
import { createWorkerResultHandler } from '../../api/worker-result.js'

const token = 'worker_token_abcdefghijklmnopqrstuvwxyz_1234567890'
const tokenHash = createHash('sha256').update(token, 'utf8').digest('hex')
const jobId = '21000000-0000-4000-8000-000000000001'

type WorkerStatus = 'active' | 'disabled' | 'revoked'

function fakeAdmin(options: {
  knownToken?: boolean
  status?: WorkerStatus
  rpcData?: unknown
  rpcError?: { code?: string; message: string }
} = {}) {
  const device = {
    id: 'worker-one',
    display_name: 'Thomas desktop',
    token_hash: tokenHash,
    status: options.status ?? 'active',
    capabilities: ['codex'],
    revoked_at: options.status === 'revoked' ? '2026-10-24T12:00:00Z' : null,
  }
  let lastSeenUpdates = 0
  const maybeSingle = vi.fn(async () => ({
    data: options.knownToken === false ? null : device,
    error: null,
  }))
  const selectEq = vi.fn().mockReturnValue({ maybeSingle })
  const select = vi.fn().mockReturnValue({ eq: selectEq })
  const updateEq = vi.fn(async () => {
    lastSeenUpdates += 1
    return { error: null }
  })
  const update = vi.fn().mockReturnValue({ eq: updateEq })
  const from = vi.fn().mockReturnValue({ select, update })
  const rpc = vi.fn(async () => ({
    data: options.rpcData === undefined ? { id: jobId, status: 'running' } : options.rpcData,
    error: options.rpcError ?? null,
  }))
  const schema = vi.fn().mockReturnValue({ from, rpc })

  return {
    client: { schema },
    from,
    rpc,
    lastSeenUpdates: () => lastSeenUpdates,
  }
}

function request(path: string, body?: unknown, authorization = `Worker ${token}`) {
  const init: RequestInit = {
    method: body === undefined ? 'GET' : 'POST',
    headers: {
      authorization,
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
  }
  if (body !== undefined) init.body = JSON.stringify(body)
  return new Request(`https://studio.example.test/api/${path}`, init)
}

describe('worker authentication', () => {
  it.each([
    ['', 'worker_auth_required'],
    ['Bearer owner-token', 'worker_auth_required'],
    ['Worker short', 'worker_auth_required'],
  ])('rejects missing or malformed worker authorization before database access', async (authorization, code) => {
    const admin = fakeAdmin()
    const handler = createWorkerOfferHandler({ admin: admin.client })

    const response = await handler(request('worker-offer', undefined, authorization))

    expect(response.status).toBe(401)
    expect(await response.json()).toEqual({ error: code })
    expect(admin.from).not.toHaveBeenCalled()
    expect(admin.rpc).not.toHaveBeenCalled()
  })

  it.each([
    [{ knownToken: false }, 'unknown token'],
    [{ status: 'disabled' as const }, 'disabled device'],
    [{ status: 'revoked' as const }, 'revoked device'],
  ])('rejects an invalid device before offering work: %s', async (options, _label) => {
    const admin = fakeAdmin(options)
    const handler = createWorkerOfferHandler({ admin: admin.client })

    const response = await handler(request('worker-offer'))

    expect(response.status).toBe(401)
    expect(await response.json()).toEqual({ error: 'worker_not_authorized' })
    expect(admin.rpc).not.toHaveBeenCalled()
    expect(admin.lastSeenUpdates()).toBe(0)
  })
})

describe('GET /api/worker-offer', () => {
  it('returns 204 for an empty queue without a response body', async () => {
    const admin = fakeAdmin({ rpcData: null })
    const handler = createWorkerOfferHandler({ admin: admin.client })

    const response = await handler(request('worker-offer'))

    expect(response.status).toBe(204)
    expect(await response.text()).toBe('')
    expect(admin.lastSeenUpdates()).toBe(1)
  })

  it('returns the bounded offer from the fixed offer procedure', async () => {
    const offer = { id: jobId, kind: 'lead-research', agent_id: 'finder', input: { leadId: 'L01' } }
    const admin = fakeAdmin({ rpcData: offer })
    const handler = createWorkerOfferHandler({ admin: admin.client })

    const response = await handler(request('worker-offer'))

    expect(response.status).toBe(200)
    expect(await response.json()).toEqual(offer)
    expect(admin.rpc).toHaveBeenCalledWith('offer_job', { p_worker_id: 'worker-one' })
  })
})

describe('worker job mutations', () => {
  it('claims only a canonical job id through the fixed claim procedure', async () => {
    const admin = fakeAdmin()
    const handler = createWorkerClaimHandler({ admin: admin.client })

    const response = await handler(request('worker-claim', { jobId }))

    expect(response.status).toBe(200)
    expect(admin.rpc).toHaveBeenCalledWith('claim_job', { p_worker_id: 'worker-one', p_job_id: jobId })
  })

  it('rejects a noncanonical job id before a procedure call', async () => {
    const admin = fakeAdmin()
    const handler = createWorkerHeartbeatHandler({ admin: admin.client })

    const response = await handler(request('worker-heartbeat', { jobId: 'not-a-job' }))

    expect(response.status).toBe(400)
    expect(await response.json()).toEqual({ error: 'invalid_job_id' })
    expect(admin.rpc).not.toHaveBeenCalled()
  })

  it.each([
    ['worker-heartbeat', createWorkerHeartbeatHandler],
    ['worker-result', createWorkerResultHandler],
  ])('maps a wrong-device lease conflict for %s without retrying', async (path, createHandler) => {
    const admin = fakeAdmin({ rpcError: { code: '42501', message: 'worker_mismatch' } })
    const handler = createHandler({ admin: admin.client })
    const body = path === 'worker-result' ? { jobId, result: { summary: 'done' } } : { jobId }

    const response = await handler(request(path, body))

    expect(response.status).toBe(409)
    expect(await response.json()).toEqual({ error: 'worker_lease_conflict' })
    expect(admin.rpc).toHaveBeenCalledTimes(1)
  })

  it('rejects an oversized result before database mutation', async () => {
    const admin = fakeAdmin()
    const handler = createWorkerResultHandler({ admin: admin.client })
    const oversized = request('worker-result', { jobId, result: { summary: 'x' } })
    oversized.headers.set('content-length', '65536')

    const response = await handler(oversized)

    expect(response.status).toBe(413)
    expect(await response.json()).toEqual({ error: 'request_too_large' })
    expect(admin.rpc).not.toHaveBeenCalled()
  })

  it('submits a bounded result object through complete_job', async () => {
    const admin = fakeAdmin({ rpcData: { id: jobId, status: 'completed' } })
    const handler = createWorkerResultHandler({ admin: admin.client })
    const result = { summary: 'Research complete', confidence: 0.88 }

    const response = await handler(request('worker-result', { jobId, result }))

    expect(response.status).toBe(200)
    expect(admin.rpc).toHaveBeenCalledWith('complete_job', {
      p_worker_id: 'worker-one',
      p_job_id: jobId,
      p_result: result,
    })
  })

  it('submits only a bounded typed failure through fail_job', async () => {
    const admin = fakeAdmin({ rpcData: { id: jobId, status: 'queued' } })
    const handler = createWorkerFailHandler({ admin: admin.client })

    const response = await handler(
      request('worker-fail', { jobId, code: 'network_timeout', summary: 'Browser timed out', retryable: true }),
    )

    expect(response.status).toBe(200)
    expect(admin.rpc).toHaveBeenCalledWith('fail_job', {
      p_worker_id: 'worker-one',
      p_job_id: jobId,
      p_code: 'network_timeout',
      p_summary: 'Browser timed out',
      p_retryable: true,
    })
  })

  it('redacts a database failure even when its message contains the raw token', async () => {
    const admin = fakeAdmin({ rpcError: { code: 'XX000', message: `connection failed for ${token}` } })
    const handler = createWorkerClaimHandler({ admin: admin.client })

    const response = await handler(request('worker-claim', { jobId }))
    const text = await response.text()

    expect(response.status).toBe(502)
    expect(text).toContain('worker_unavailable')
    expect(text).not.toContain(token)
  })
})

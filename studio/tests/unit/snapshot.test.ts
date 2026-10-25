import { describe, expect, it, vi } from 'vitest'

import { createSnapshotHandler } from '../../api/snapshot.js'

const ownerId = '41000000-0000-0000-0000-000000000001'

function adminClient(options: {
  userId?: string | null
  authError?: { message: string } | null
  data?: unknown
  rpcError?: { message: string } | null
} = {}) {
  const getUser = vi.fn().mockResolvedValue({
    data: { user: options.userId === undefined ? { id: ownerId } : options.userId ? { id: options.userId } : null },
    error: options.authError ?? null,
  })
  const rpc = vi.fn().mockResolvedValue({ data: options.data ?? {}, error: options.rpcError ?? null })
  const schema = vi.fn().mockReturnValue({ rpc })

  return { client: { auth: { getUser }, schema }, getUser, schema, rpc }
}

function ownerRequest(token = 'valid-owner-token') {
  return new Request('https://studio.example.test/api/snapshot', {
    headers: { authorization: `Bearer ${token}` },
  })
}

describe('GET /api/snapshot', () => {
  it('returns 403 for a valid non-owner before any database call', async () => {
    const admin = adminClient({ userId: '42000000-0000-0000-0000-000000000002' })
    const handler = createSnapshotHandler({ admin: admin.client, ownerUserId: ownerId })

    const response = await handler(ownerRequest())

    expect(response.status).toBe(403)
    expect(admin.schema).not.toHaveBeenCalled()
    expect(admin.rpc).not.toHaveBeenCalled()
  })

  it('returns 401 for an expired session before any database call', async () => {
    const admin = adminClient({ userId: null, authError: { message: 'expired private detail' } })
    const handler = createSnapshotHandler({ admin: admin.client, ownerUserId: ownerId })

    const response = await handler(ownerRequest('expired'))

    expect(response.status).toBe(401)
    expect(admin.rpc).not.toHaveBeenCalled()
  })

  it('returns a browser-safe DTO and drops arbitrary or secret fields', async () => {
    const admin = adminClient({
      data: {
        agents: [
          {
            id: 'finder',
            name: 'Contact Finder',
            role: 'Research',
            state: 'working',
            health: 'healthy',
            model_tier: 'mechanical',
            current_job_id: '21000000-0000-0000-0000-000000000001',
            queue_depth: 2,
            last_heartbeat: '2026-10-24T20:00:00Z',
            token_hash: 'must-not-leak',
          },
        ],
        jobs: [
          {
            id: '21000000-0000-0000-0000-000000000001',
            workflow_id: '11000000-0000-0000-0000-000000000001',
            lead_id: 'L01',
            agent_id: 'finder',
            kind: 'contact_verification',
            status: 'running',
            priority: 25,
            attempts: 1,
            max_attempts: 3,
            locked_at: '2026-10-24T20:00:00Z',
            lock_owner: 'worker-one',
            input: { rawEmailBody: 'must-not-leak' },
            output: { chainOfThought: 'must-not-leak' },
          },
        ],
        approvals: [
          {
            id: '31000000-0000-0000-0000-000000000001',
            job_id: '21000000-0000-0000-0000-000000000001',
            action_type: 'send_draft',
            title: 'Review draft',
            risk: 'medium',
            status: 'pending',
            requested_at: '2026-10-24T20:00:00Z',
            preview: {
              recipient: 'owner@example.test',
              subject: 'Website introduction',
              body: 'A bounded draft for review.',
              privatePrompt: 'must-not-leak',
            },
          },
        ],
        activity: [
          {
            id: 7,
            job_id: '21000000-0000-0000-0000-000000000001',
            at: '2026-10-24T20:00:00Z',
            event: 'claimed',
            actor: 'worker-one',
            summary: 'Worker claimed job',
            details: { accessToken: 'must-not-leak' },
          },
        ],
        pipeline: [{ stage: 'New', count: 3, arbitrary: 'drop-me' }],
        missions: [
          {
            id: 'weekday-research',
            name: 'Weekday research',
            agent_id: 'finder',
            job_kind: 'research',
            cadence_minutes: 1440,
            next_run_at: '2026-10-25T14:00:00Z',
            enabled: true,
            priority: 20,
            max_attempts: 3,
            last_dispatched_at: null,
            input: { privateInstructions: 'must-not-leak' },
          },
        ],
        autonomy: {
          emergencyStop: false,
          dailyJobLimit: 12,
          maximumAttempts: 3,
          runtimeMinutes: 15,
          windowStart: '07:00',
          windowEnd: '20:00',
          timezone: 'America/Chicago',
          arbitrarySetting: 'must-not-leak',
        },
        service_role_key: 'must-not-leak',
      },
    })
    const handler = createSnapshotHandler({
      admin: admin.client,
      ownerUserId: ownerId,
      now: () => new Date('2026-10-24T20:01:00Z'),
    })

    const response = await handler(ownerRequest())
    const body = await response.json()

    expect(response.status).toBe(200)
    expect(response.headers.get('cache-control')).toBe('private, no-store')
    expect(admin.schema).toHaveBeenCalledWith('ops')
    expect(admin.rpc).toHaveBeenCalledWith('get_studio_snapshot')
    expect(body).toMatchObject({
      serverTime: '2026-10-24T20:01:00.000Z',
      agents: [{ id: 'finder', state: 'working', queueDepth: 2 }],
      jobs: [{ id: '21000000-0000-0000-0000-000000000001', attempts: 1 }],
      approvals: [
        {
          id: '31000000-0000-0000-0000-000000000001',
          status: 'pending',
          preview: [
            { label: 'Recipient', value: 'owner@example.test' },
            { label: 'Subject', value: 'Website introduction' },
            { label: 'Draft', value: 'A bounded draft for review.' },
          ],
        },
      ],
      events: [{ id: 7, event: 'claimed' }],
      pipeline: [{ stage: 'New', count: 3 }],
      missions: [
        {
          id: 'weekday-research',
          name: 'Weekday research',
          agentId: 'finder',
          jobKind: 'research',
          cadenceMinutes: 1440,
          nextRunAt: '2026-10-25T14:00:00Z',
          enabled: true,
          priority: 20,
          maxAttempts: 3,
          lastDispatchedAt: null,
        },
      ],
      autonomy: {
        emergencyStop: false,
        dailyJobLimit: 12,
        maximumAttempts: 3,
        runtimeMinutes: 15,
        windowStart: '07:00',
        windowEnd: '20:00',
        timezone: 'America/Chicago',
      },
      heartbeats: [{ agentId: 'finder', health: 'healthy', lastHeartbeat: '2026-10-24T20:00:00Z' }],
    })
    expect(JSON.stringify(body)).not.toMatch(
      /must-not-leak|rawEmailBody|chainOfThought|token_hash|details|privateInstructions|arbitrarySetting/i,
    )
  })

  it('returns a bounded generic error without leaking service details', async () => {
    const admin = adminClient({ rpcError: { message: 'private database host and query detail' } })
    const handler = createSnapshotHandler({ admin: admin.client, ownerUserId: ownerId })

    const response = await handler(ownerRequest())
    const body = await response.json()

    expect(response.status).toBe(502)
    expect(body).toEqual({ error: 'snapshot_unavailable' })
    expect(JSON.stringify(body)).not.toContain('private database')
  })
})

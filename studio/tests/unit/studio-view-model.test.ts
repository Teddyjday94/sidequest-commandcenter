import { describe, expect, it } from 'vitest'

import {
  agentStateLabel,
  emergencyStopCopy,
  isWorkerOffline,
  prioritizeBrief,
  roomForAgent,
  sortApprovals,
  sortEvents,
} from '../../src/lib/store.js'
import type { ApprovalDTO, JobEventDTO, StudioSnapshot } from '../../src/types.js'

function snapshot(overrides: Partial<StudioSnapshot> = {}): StudioSnapshot {
  return {
    serverTime: '2026-10-24T20:05:00.000Z',
    agents: [],
    jobs: [],
    approvals: [],
    events: [],
    pipeline: [],
    heartbeats: [],
    missions: [],
    autonomy: {
      emergencyStop: false,
      dailyJobLimit: 12,
      maximumAttempts: 3,
      runtimeMinutes: 15,
      windowStart: '07:00',
      windowEnd: '20:00',
      timezone: 'America/Chicago',
    },
    ...overrides,
  }
}

describe('studio view model', () => {
  it('assigns the same agent to the same named room', () => {
    expect(roomForAgent('contact-finder')).toBe(roomForAgent('contact-finder'))
    expect(roomForAgent('contact-finder')).toMatch(/^(signal desk|draft room|review bay|dispatch table)$/)
  })

  it.each([
    ['working', 'In progress'],
    ['waiting_for_thomas', 'Needs owner'],
    ['handing_off', 'Handing off'],
    ['offline', 'Offline'],
  ] as const)('uses human state labels for %s', (state, label) => {
    expect(agentStateLabel(state)).toBe(label)
  })

  it('calculates worker-offline state from server time instead of browser time', () => {
    expect(isWorkerOffline('2026-10-24T20:02:59.000Z', '2026-10-24T20:05:00.000Z')).toBe(true)
    expect(isWorkerOffline('2026-10-24T20:03:01.000Z', '2026-10-24T20:05:00.000Z')).toBe(false)
    expect(isWorkerOffline(null, '2026-10-24T20:05:00.000Z')).toBe(true)
  })

  it('puts the emergency stop and high-risk approvals before routine queue notes', () => {
    const result = prioritizeBrief(
      snapshot({
        autonomy: { ...snapshot().autonomy, emergencyStop: true },
        approvals: [
          {
            id: 'a1', jobId: 'j1', leadId: null, actionType: 'send', title: 'Approve send', risk: 'high',
            status: 'pending', requestedAt: null, decidedAt: null, decisionNote: null,
            externalActionCompletedAt: null, preview: [], previewComplete: false,
          },
        ],
        jobs: [
          {
            id: 'j1', workflowId: 'w1', leadId: null, agentId: 'finder', kind: 'research', status: 'queued',
            priority: 50, confidence: null, attempts: 0, maxAttempts: 3, scheduledFor: null, lockedAt: null,
            lockOwner: null, createdAt: null, updatedAt: null, completedAt: null, errorCode: null,
            errorSummary: null, isStateChanging: false,
          },
        ],
      }),
    )

    expect(result.map((item) => item.kind)).toEqual(['stop', 'approval', 'queue'])
  })

  it('sorts activity newest first without mutating the snapshot', () => {
    const events: JobEventDTO[] = [
      { id: 1, jobId: 'j1', at: '2026-10-24T20:01:00Z', event: 'queued', actor: 'system', summary: 'Queued' },
      { id: 2, jobId: 'j1', at: '2026-10-24T20:03:00Z', event: 'claimed', actor: 'worker', summary: 'Claimed' },
    ]

    expect(sortEvents(events).map((event) => event.id)).toEqual([2, 1])
    expect(events.map((event) => event.id)).toEqual([1, 2])
  })

  it('orders pending approvals by risk, then request time', () => {
    const approval = (id: string, risk: string, requestedAt: string): ApprovalDTO => ({
      id, jobId: `job-${id}`, leadId: null, actionType: 'review', title: id, risk, status: 'pending',
      requestedAt, decidedAt: null, decisionNote: null, externalActionCompletedAt: null,
      preview: [], previewComplete: false,
    })
    const approvals = [
      approval('low', 'low', '2026-10-24T20:04:00Z'),
      approval('high-later', 'high', '2026-10-24T20:03:00Z'),
      approval('high-earlier', 'high', '2026-10-24T20:01:00Z'),
    ]

    expect(sortApprovals(approvals).map((item) => item.id)).toEqual(['high-earlier', 'high-later', 'low'])
  })

  it('uses unambiguous copy for both emergency-stop states', () => {
    expect(emergencyStopCopy(true)).toMatchObject({ label: 'Resume automation', confirmation: 'Resume new automated work?' })
    expect(emergencyStopCopy(false)).toMatchObject({ label: 'Stop automation', confirmation: 'Stop all new automated work?' })
  })
})

import type { AgentState, ApprovalDTO, JobEventDTO, StudioSnapshot } from '../types.js'

const rooms = ['signal desk', 'draft room', 'review bay', 'dispatch table'] as const
const riskOrder: Record<string, number> = { high: 0, medium: 1, low: 2 }

export interface BriefItem {
  kind: 'stop' | 'approval' | 'health' | 'queue' | 'clear'
  eyebrow: string
  title: string
  detail: string
}

export function roomForAgent(agentId: string): (typeof rooms)[number] {
  let hash = 0
  for (const character of agentId) hash = (hash * 31 + character.charCodeAt(0)) >>> 0
  return rooms[hash % rooms.length] ?? rooms[0]
}

export function agentStateLabel(state: AgentState): string {
  const labels: Record<AgentState, string> = {
    idle: 'Available',
    queued: 'Queued',
    working: 'In progress',
    reviewing: 'Reviewing',
    handing_off: 'Handing off',
    waiting_for_thomas: 'Needs owner',
    blocked: 'Blocked',
    offline: 'Offline',
  }
  return labels[state]
}

export function isWorkerOffline(
  lastHeartbeat: string | null,
  serverTime: string,
  thresholdMilliseconds = 120_000,
): boolean {
  if (!lastHeartbeat) return true
  const heartbeat = Date.parse(lastHeartbeat)
  const server = Date.parse(serverTime)
  if (!Number.isFinite(heartbeat) || !Number.isFinite(server)) return true
  return server - heartbeat > thresholdMilliseconds
}

export function sortEvents(events: readonly JobEventDTO[]): JobEventDTO[] {
  return [...events].sort((left, right) => {
    const byTime = Date.parse(right.at ?? '') - Date.parse(left.at ?? '')
    return Number.isNaN(byTime) || byTime === 0 ? right.id - left.id : byTime
  })
}

export function sortApprovals(approvals: readonly ApprovalDTO[]): ApprovalDTO[] {
  return [...approvals]
    .filter((approval) => approval.status === 'pending')
    .sort((left, right) => {
      const byRisk = (riskOrder[left.risk] ?? 3) - (riskOrder[right.risk] ?? 3)
      if (byRisk !== 0) return byRisk
      return Date.parse(left.requestedAt ?? '') - Date.parse(right.requestedAt ?? '')
    })
}

export function prioritizeBrief(snapshot: StudioSnapshot): BriefItem[] {
  const items: BriefItem[] = []
  if (snapshot.autonomy.emergencyStop) {
    items.push({
      kind: 'stop',
      eyebrow: 'Automation stopped',
      title: 'No new work can be offered or claimed.',
      detail: 'Running work may finish. Resume only after the reason for the stop is resolved.',
    })
  }

  const highRisk = sortApprovals(snapshot.approvals).filter((approval) => approval.risk === 'high')
  if (highRisk.length > 0) {
    items.push({
      kind: 'approval',
      eyebrow: 'Owner decision',
      title: `${highRisk.length} high-risk ${highRisk.length === 1 ? 'approval' : 'approvals'} waiting.`,
      detail: highRisk[0]?.title ?? 'Review the approval dock.',
    })
  }

  const unhealthy = snapshot.agents.filter(
    (agent) => agent.health === 'degraded' || agent.health === 'offline' || isWorkerOffline(agent.lastHeartbeat, snapshot.serverTime),
  )
  if (unhealthy.length > 0) {
    items.push({
      kind: 'health',
      eyebrow: 'Agent health',
      title: `${unhealthy.length} ${unhealthy.length === 1 ? 'agent needs' : 'agents need'} attention.`,
      detail: unhealthy.map((agent) => agent.name).join(', '),
    })
  }

  const queued = snapshot.jobs.filter((job) => job.status === 'queued')
  if (queued.length > 0) {
    items.push({
      kind: 'queue',
      eyebrow: 'Internal queue',
      title: `${queued.length} ${queued.length === 1 ? 'job is' : 'jobs are'} ready for internal work.`,
      detail: 'Sending, publishing, purchases, and deployment remain owner-gated.',
    })
  }

  if (items.length === 0) {
    items.push({
      kind: 'clear',
      eyebrow: 'Morning brief',
      title: 'No immediate intervention is required.',
      detail: 'The studio will surface real work here as it arrives.',
    })
  }
  return items
}

export function emergencyStopCopy(enabled: boolean): { label: string; confirmation: string; detail: string } {
  return enabled
    ? {
        label: 'Resume automation',
        confirmation: 'Resume new automated work?',
        detail: 'New internal jobs may be offered and claimed again.',
      }
    : {
        label: 'Stop automation',
        confirmation: 'Stop all new automated work?',
        detail: 'Running work may finish, but no new jobs will be offered or claimed.',
      }
}

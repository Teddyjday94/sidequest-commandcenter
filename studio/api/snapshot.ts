import { readServerEnv } from './_lib/env.js'
import { approvalPreview } from './_lib/approval-preview.js'
import { errorResponse, HttpError, jsonResponse } from './_lib/http.js'
import { requireOwner, type OwnerAuthClient } from './_lib/owner-auth.js'
import { getAdminClient } from './_lib/supabase.js'
import type {
  AgentDTO,
  AgentHealth,
  AgentState,
  ApprovalDTO,
  AutonomyDTO,
  JobDTO,
  JobEventDTO,
  MissionDTO,
  PipelineStageDTO,
  StudioSnapshot,
} from '../src/types.js'

interface SnapshotAdminClient extends OwnerAuthClient {
  schema(name: 'ops'): {
    rpc(name: 'get_studio_snapshot'): Promise<{ data: unknown; error: { message: string } | null }>
  }
}

interface SnapshotDependencies {
  admin?: SnapshotAdminClient
  ownerUserId?: string
  now?: () => Date
}

type JsonRecord = Record<string, unknown>

const agentStates = new Set<AgentState>([
  'idle',
  'queued',
  'working',
  'reviewing',
  'handing_off',
  'waiting_for_thomas',
  'blocked',
  'offline',
])
const agentHealth = new Set<AgentHealth>(['healthy', 'degraded', 'offline', 'unknown'])

function record(value: unknown): JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? (value as JsonRecord) : {}
}

function records(value: unknown, limit: number): JsonRecord[] {
  return Array.isArray(value) ? value.slice(0, limit).map(record) : []
}

function text(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value.slice(0, 2000) : fallback
}

function nullableText(value: unknown): string | null {
  return typeof value === 'string' ? value.slice(0, 2000) : null
}

function integer(value: unknown, fallback = 0): number {
  return typeof value === 'number' && Number.isSafeInteger(value) ? value : fallback
}

function numberOrNull(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function agentDto(row: JsonRecord): AgentDTO {
  const stateValue = text(row.state, 'blocked') as AgentState
  const healthValue = text(row.health, 'unknown') as AgentHealth
  return {
    id: text(row.id),
    name: text(row.name),
    role: text(row.role),
    status: text(row.status),
    state: agentStates.has(stateValue) ? stateValue : 'blocked',
    health: agentHealth.has(healthValue) ? healthValue : 'unknown',
    modelTier: text(row.model_tier, 'mechanical'),
    currentJobId: nullableText(row.current_job_id),
    queueDepth: Math.max(0, integer(row.queue_depth)),
    lastHeartbeat: nullableText(row.last_heartbeat),
    lastRun: nullableText(row.last_run),
    lastResult: nullableText(row.last_result),
  }
}

function jobDto(row: JsonRecord): JobDTO {
  return {
    id: text(row.id),
    workflowId: text(row.workflow_id),
    leadId: nullableText(row.lead_id),
    agentId: text(row.agent_id),
    kind: text(row.kind),
    status: text(row.status),
    priority: Math.max(0, integer(row.priority)),
    confidence: numberOrNull(row.confidence),
    attempts: Math.max(0, integer(row.attempts)),
    maxAttempts: Math.max(1, integer(row.max_attempts, 1)),
    scheduledFor: nullableText(row.scheduled_for),
    lockedAt: nullableText(row.locked_at),
    lockOwner: nullableText(row.lock_owner),
    createdAt: nullableText(row.created_at),
    updatedAt: nullableText(row.updated_at),
    completedAt: nullableText(row.completed_at),
    errorCode: nullableText(row.error_code),
    errorSummary: nullableText(row.error_summary),
    isStateChanging: row.is_state_changing === true,
  }
}

function approvalDto(row: JsonRecord): ApprovalDTO {
  const preview = approvalPreview(text(row.action_type), row.preview)
  return {
    id: text(row.id),
    jobId: text(row.job_id),
    leadId: nullableText(row.lead_id),
    actionType: text(row.action_type),
    title: text(row.title),
    risk: text(row.risk),
    status: text(row.status),
    requestedAt: nullableText(row.requested_at),
    decidedAt: nullableText(row.decided_at),
    decisionNote: nullableText(row.decision_note),
    externalActionCompletedAt: nullableText(row.external_action_completed_at),
    preview: preview.fields,
    previewComplete: preview.complete,
  }
}

function eventDto(row: JsonRecord): JobEventDTO {
  return {
    id: Math.max(0, integer(row.id)),
    jobId: text(row.job_id),
    at: nullableText(row.at),
    event: text(row.event),
    actor: text(row.actor),
    summary: text(row.summary),
  }
}

function pipelineDto(row: JsonRecord): PipelineStageDTO {
  return { stage: text(row.stage), count: Math.max(0, integer(row.count)) }
}

function missionDto(row: JsonRecord): MissionDTO {
  return {
    id: text(row.id),
    name: text(row.name),
    agentId: text(row.agent_id),
    jobKind: text(row.job_kind),
    cadenceMinutes: Math.max(15, integer(row.cadence_minutes, 15)),
    nextRunAt: nullableText(row.next_run_at),
    enabled: row.enabled === true,
    priority: Math.max(0, integer(row.priority)),
    maxAttempts: Math.min(10, Math.max(1, integer(row.max_attempts, 1))),
    lastDispatchedAt: nullableText(row.last_dispatched_at),
  }
}

function autonomyDto(value: unknown): AutonomyDTO {
  const row = record(value)
  return {
    emergencyStop: row.emergencyStop === true,
    dailyJobLimit: Math.min(100, Math.max(1, integer(row.dailyJobLimit, 12))),
    maximumAttempts: Math.min(10, Math.max(1, integer(row.maximumAttempts, 3))),
    runtimeMinutes: Math.min(60, Math.max(1, integer(row.runtimeMinutes, 15))),
    windowStart: text(row.windowStart, '07:00'),
    windowEnd: text(row.windowEnd, '20:00'),
    timezone: text(row.timezone, 'America/Chicago'),
  }
}

function normalizeSnapshot(value: unknown, now: Date): StudioSnapshot {
  const raw = record(value)
  const agents = records(raw.agents, 50).map(agentDto).filter((agent) => agent.id !== '')

  return {
    serverTime: now.toISOString(),
    agents,
    jobs: records(raw.jobs, 100).map(jobDto).filter((job) => job.id !== ''),
    approvals: records(raw.approvals, 50).map(approvalDto).filter((approval) => approval.id !== ''),
    events: records(raw.activity, 100).map(eventDto),
    pipeline: records(raw.pipeline, 30).map(pipelineDto).filter((stage) => stage.stage !== ''),
    missions: records(raw.missions, 50).map(missionDto).filter((mission) => mission.id !== ''),
    autonomy: autonomyDto(raw.autonomy),
    heartbeats: agents.map((agent) => ({
      agentId: agent.id,
      health: agent.health,
      lastHeartbeat: agent.lastHeartbeat,
    })),
  }
}

export function createSnapshotHandler(dependencies: SnapshotDependencies = {}) {
  return async function GET(request: Request): Promise<Response> {
    try {
      const admin =
        dependencies.admin ?? (getAdminClient() as unknown as SnapshotAdminClient)
      const ownerUserId = dependencies.ownerUserId ?? readServerEnv().ownerUserId
      await requireOwner(request, { admin, ownerUserId })

      const { data, error } = await admin.schema('ops').rpc('get_studio_snapshot')
      if (error) {
        console.error('snapshot_rpc_failed')
        throw new HttpError(502, 'snapshot_unavailable')
      }

      return jsonResponse(normalizeSnapshot(data, (dependencies.now ?? (() => new Date()))()), 200, {
        'cache-control': 'private, no-store',
      })
    } catch (error) {
      if (!(error instanceof HttpError)) console.error('snapshot_request_failed')
      return errorResponse(error)
    }
  }
}

export const GET = createSnapshotHandler()

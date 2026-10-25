export type AgentState =
  | 'idle'
  | 'queued'
  | 'working'
  | 'reviewing'
  | 'handing_off'
  | 'waiting_for_thomas'
  | 'blocked'
  | 'offline'

export type AgentHealth = 'healthy' | 'degraded' | 'offline' | 'unknown'

export interface AgentDTO {
  id: string
  name: string
  role: string
  status: string
  state: AgentState
  health: AgentHealth
  modelTier: string
  currentJobId: string | null
  queueDepth: number
  lastHeartbeat: string | null
  lastRun: string | null
  lastResult: string | null
}

export interface JobDTO {
  id: string
  workflowId: string
  leadId: string | null
  agentId: string
  kind: string
  status: string
  priority: number
  confidence: number | null
  attempts: number
  maxAttempts: number
  scheduledFor: string | null
  lockedAt: string | null
  lockOwner: string | null
  createdAt: string | null
  updatedAt: string | null
  completedAt: string | null
  errorCode: string | null
  errorSummary: string | null
  isStateChanging: boolean
}

export interface ApprovalDTO {
  id: string
  jobId: string
  leadId: string | null
  actionType: string
  title: string
  risk: string
  status: string
  requestedAt: string | null
  decidedAt: string | null
  decisionNote: string | null
  externalActionCompletedAt: string | null
  preview: ApprovalPreviewFieldDTO[]
  previewComplete: boolean
}

export interface ApprovalPreviewFieldDTO {
  label: string
  value: string
}

export interface JobEventDTO {
  id: number
  jobId: string
  at: string | null
  event: string
  actor: string
  summary: string
}

export interface PipelineStageDTO {
  stage: string
  count: number
}

export interface HeartbeatDTO {
  agentId: string
  health: AgentHealth
  lastHeartbeat: string | null
}

export interface MissionDTO {
  id: string
  name: string
  agentId: string
  jobKind: string
  cadenceMinutes: number
  nextRunAt: string | null
  enabled: boolean
  priority: number
  maxAttempts: number
  lastDispatchedAt: string | null
}

export interface AutonomyDTO {
  emergencyStop: boolean
  dailyJobLimit: number
  maximumAttempts: number
  runtimeMinutes: number
  windowStart: string
  windowEnd: string
  timezone: string
}

export interface StudioSnapshot {
  serverTime: string
  agents: AgentDTO[]
  jobs: JobDTO[]
  approvals: ApprovalDTO[]
  events: JobEventDTO[]
  pipeline: PipelineStageDTO[]
  heartbeats: HeartbeatDTO[]
  missions: MissionDTO[]
  autonomy: AutonomyDTO
}
